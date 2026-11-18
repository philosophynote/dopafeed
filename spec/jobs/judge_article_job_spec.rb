RSpec.describe JudgeArticleJob, type: :job do
  include_context "判定が設定済み"

  let(:article) { create(:article, :awaiting_summary, :opened) }
  let(:scorer) { instance_double(Judgments::ArticleScorer) }
  let(:scores) { ArticleJudgment::AXES.index_with { 2.6 } }
  let(:result) { Judgments::ArticleScorer::Result.new(scores: scores, model: "jev-latest", input_tokens: 1200, cost: nil) }

  before { allow(Judgments::ArticleScorer).to receive(:new).with(article).and_return(scorer) }

  it "6 軸の段・モデル・実費・判定の時刻を記事の判定として残す" do
    allow(scorer).to receive(:call).and_return(result)

    freeze_time { described_class.perform_now(article) }

    expect(article.reload.judgment).to have_attributes(scores.merge(model: "jev-latest", input_tokens: 1200, cost: nil, failed_at: nil))
    expect(article.judgment).to be_judged
  end

  describe "枠（readings.tier）" do
    let(:rare) { Dopamine.rarity_names.second }
    let(:stream) { Turbo::StreamsChannel.send(:stream_name_from, [ article.reading, :tier ]) }

    before { article.reading.update!(tier: nil) }

    it "判定が届いたら、合計点の段を書き、待っている帯と区切りへ止まるリールを配る" do
      allow(scorer).to receive(:call).and_return(result.with(scores: scores_for(rare)))

      expect { described_class.perform_now(article) }.to have_broadcasted_to(stream).with { |html|
        # turbo-stream の中身は <template> に包まれ、HTML4 の parser は template の子を捨てるので外して読む
        band = Capybara.string(html.gsub(%r{</?template>}, "")).find("turbo-stream[action='replace'][target='rarity_reading_#{article.reading.id}']")
        expect(band).to have_css("[data-tier='#{rare}'][data-state='ready']", text: "24 点 レア ・ 完読でレアカード".sub("24", Dopamine.rarity(rare)[:min_total].to_s))
        expect(band).to have_css(".reel-inner", text: "レア")
        expect(band).to have_css("[data-sfx-cue-value='rare']", visible: :all)
        expect(band).to have_no_css("turbo-cable-stream-source", visible: :all)
      }

      expect(article.reading.reload.tier).to eq(rare)
    end

    it "時間を置いても通らない失敗・再試行の使い切り・予算切れ・拒否では、一番下の段に決めて配る（待たせ続けない）" do
      [
        -> { allow(scorer).to receive(:call).and_raise(Judgments::ArticleScorer::EmptyContent, "本文が空"); described_class.perform_now(article) },
        -> { allow(scorer).to receive(:call).and_raise(Judgments::ArticleScorer::TransientError, "API エラー (HTTP 503)"); perform_enqueued_jobs { described_class.perform_later(article) } },
        -> { allow(scorer).to receive(:call).and_raise(Claude::Budget::Exhausted, "limit"); described_class.perform_now(article) },
        -> { allow(scorer).to receive(:call).and_raise(Judgments::ArticleScorer::RejectedError, "API エラー (HTTP 422)"); described_class.perform_now(article) }
      ].each do |run|
        article.reading.update!(tier: nil)
        ArticleJudgment.delete_all

        expect { run.call }.to have_broadcasted_to(stream)
        expect(article.reading.reload.tier).to eq(Dopamine.base_rarity[:name])
      end
    end

    it "枠を書けなかったら判定の行も残さない（行だけ残ると、次の実行が判定済みと見て枠が空のまま残る）" do
      allow(scorer).to receive(:call).and_return(result.with(scores: scores_for(rare)))
      allow(Reading).to receive(:settle_tier!).and_raise(ActiveRecord::StatementTimeout, "busy")

      expect { described_class.new.perform(article) }.to raise_error(ActiveRecord::StatementTimeout)
      expect(ArticleJudgment.where(article: article)).to be_empty
      expect(Article.awaiting_judgment).to include(article)
    end

    it "再試行を待つ間は、枠を決めない" do
      allow(scorer).to receive(:call).and_raise(Judgments::ArticleScorer::TransientError, "API エラー (HTTP 503)")

      expect { described_class.perform_now(article) }.not_to have_broadcasted_to(stream)
      expect(article.reading.reload.tier).to be_nil
    end

    it "すでに枠が決まっている行は動かさず、配らない（過去のカードの付け直しは rake）" do
      article.reading.update!(tier: Dopamine.base_rarity[:name])
      allow(scorer).to receive(:call).and_return(result.with(scores: scores_for(rare)))

      expect { described_class.perform_now(article) }.not_to have_broadcasted_to(stream)
      expect(article.reading.reload.tier).to eq(Dopamine.base_rarity[:name])
    end
  end

  it "判定済み・失敗済みなら呼ばない（記事 1 本に 1 回。二度払いしない）" do
    create(:article_judgment, :failed, article: article)

    described_class.perform_now(article)

    expect(Judgments::ArticleScorer).not_to have_received(:new)
  end

  it "読むと決めていない記事は、積まれていても呼ばない" do
    article.reading.destroy!

    described_class.perform_now(article.reload)

    expect(Judgments::ArticleScorer).not_to have_received(:new)
  end

  it "呼んでいる間に別の実行が先に書いていたら、先の結果を残す" do
    allow(scorer).to receive(:call) do
      create(:article_judgment, article: Article.find(article.id), depth: 1.0)
      result
    end

    expect { described_class.perform_now(article) }.not_to raise_error

    expect(article.reload.judgment.depth).to eq(1.0)
  end

  it "時間を置いても通らない失敗は、再試行せず失敗として残す" do
    allow(scorer).to receive(:call).and_raise(Judgments::ArticleScorer::Error, "判定として読めない応答 (HTTP 200)")

    expect { described_class.perform_now(article) }.not_to have_enqueued_job(described_class)

    expect(article.reload.judgment).to have_attributes(error: "判定として読めない応答 (HTTP 200)", judged_at: nil)
    expect(article.judgment.failed_at).to be_present
  end

  it "一時的な失敗は再試行に回し、その間は失敗を残さない" do
    allow(scorer).to receive(:call).and_raise(Judgments::ArticleScorer::TransientError, "API エラー (HTTP 503)")

    expect { described_class.perform_now(article) }.to have_enqueued_job(described_class).with(article)

    expect(article.reload.judgment).to be_nil
  end

  it "再試行を使い切ったら失敗として残す" do
    allow(scorer).to receive(:call).and_raise(Judgments::ArticleScorer::TransientError, "API エラー (HTTP 503)")

    perform_enqueued_jobs { described_class.perform_later(article) }

    expect(article.reload.judgment).to have_attributes(error: "API エラー (HTTP 503)", judged_at: nil)
  end

  it "予算切れは捨てる。失敗も残さないので、次に開いたときにまた積める" do
    allow(scorer).to receive(:call).and_raise(Claude::Budget::Exhausted, "limit")

    expect { described_class.perform_now(article) }.not_to raise_error

    expect(article.reload.judgment).to be_nil
    expect(Article.awaiting_judgment).to include(article)
  end

  it "鍵・残高・モデル名・要求の形で拒まれたら捨てる。記事のせいではないので失敗を残さず、直した後に開き直せば積める" do
    allow(scorer).to receive(:call).and_raise(Judgments::ArticleScorer::RejectedError, "API エラー (HTTP 422)")

    expect { described_class.perform_now(article) }.not_to raise_error

    expect(article.reload.judgment).to be_nil
  end

  it "呼んでいる間に記事が消えていたら、何も残さず終わる" do
    allow(scorer).to receive(:call) do
      Article.find(article.id).destroy!
      result
    end

    expect { described_class.perform_now(article) }.not_to raise_error
  end

  it "積んだ後に記事が消えていたら捨てる" do
    described_class.perform_later(article)
    article.destroy!

    expect { perform_enqueued_jobs }.not_to raise_error
  end

  describe ".enqueue_if_awaiting" do
    it "判定待ちの記事なら積む" do
      expect { described_class.enqueue_if_awaiting(article) }.to have_enqueued_job(described_class).with(article).on_queue("judgments")
    end

    it "判定の行がある・読むと決めていない・本文取得前の記事では積まない" do
      judged = create(:article_judgment, article: create(:article, :awaiting_summary, :opened)).article
      articles = [ judged, create(:article, :awaiting_summary), create(:article, :opened, content_fetched_at: nil) ]

      expect { articles.each { |a| described_class.enqueue_if_awaiting(a) } }.not_to have_enqueued_job(described_class)
    end

    it "設定か API キーが揃っていなければ積まない（鍵の無い箱で失敗の Job を溜めない）" do
      with_env("TYPESAFE_API_KEY" => nil) do
        expect { described_class.enqueue_if_awaiting(article) }.not_to have_enqueued_job(described_class)
      end
    end
  end
end
