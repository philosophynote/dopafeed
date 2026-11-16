RSpec.describe JudgeArticleJob, type: :job do
  include_context "判定が設定済み"

  let(:article) { create(:article, :awaiting_summary, :opened) }
  let(:scorer) { instance_double(Judgments::ArticleScorer) }
  let(:scores) { ArticleJudgment::AXES.index_with { 2.6 } }
  let(:result) { Judgments::ArticleScorer::Result.new(scores: scores, model: "typesafe/jev-1.14", input_tokens: 1200, cost: 0.0003) }

  before { allow(Judgments::ArticleScorer).to receive(:new).with(article).and_return(scorer) }

  it "6 軸の段・モデル・実費・判定の時刻を記事の判定として残す" do
    allow(scorer).to receive(:call).and_return(result)

    freeze_time { described_class.perform_now(article) }

    expect(article.reload.judgment).to have_attributes(scores.merge(model: "typesafe/jev-1.14", input_tokens: 1200, cost: 0.0003, failed_at: nil))
    expect(article.judgment).to be_judged
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
    allow(scorer).to receive(:call).and_raise(Judgments::ArticleScorer::Error, "API エラー (HTTP 400)")

    expect { described_class.perform_now(article) }.not_to have_enqueued_job(described_class)

    expect(article.reload.judgment).to have_attributes(error: "API エラー (HTTP 400)", judged_at: nil)
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
      with_env("OPENROUTER_API_KEY" => nil) do
        expect { described_class.enqueue_if_awaiting(article) }.not_to have_enqueued_job(described_class)
      end
    end
  end
end
