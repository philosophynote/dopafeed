require "rake"

RSpec.describe "judgments の rake" do
  include_context "判定が設定済み"

  before(:all) { Rails.application.load_tasks if Rake::Task.tasks.none? { |t| t.name == "judgments:backfill" } }

  after { [ backfill, status ].each(&:reenable) }

  let(:backfill) { Rake::Task["judgments:backfill"] }
  let(:status) { Rake::Task["judgments:status"] }
  let(:scores) { ArticleJudgment::AXES.index_with { 2.6 } }

  def completed_article(title, completed_at)
    create(:article, :awaiting_summary, title: title).tap do |article|
      create(:reading, :completed, article: article, opened_at: completed_at - 5.minutes)
    end
  end

  describe "judgments:backfill" do
    before do
      stub_request(:post, JudgmentHelper::ENDPOINT).to_return(body: judgment_response(scores), headers: { "Content-Type" => "application/json" })
    end

    it "完読した未判定の記事を、完読の新しい順に指定の本数だけ判定し、点を 1 行ずつ出す" do
      old = completed_article("古い完読", Time.zone.local(2026, 10, 1, 9))
      newer = completed_article("新しい完読", Time.zone.local(2026, 10, 3, 9))
      opened_only = create(:article, :awaiting_summary, :opened)

      expect { backfill.invoke("1") }.to output(/24 点 4\/4\/4\/4\/4\/4 新しい完読/).to_stdout

      expect(newer.reload.judgment).to be_judged
      expect(old.reload.judgment).to be_nil
      expect(opened_only.reload.judgment).to be_nil
    end

    it "本数が無い・0 以下・数でないなら、何も呼ばずに使い方を出して止まる（負の LIMIT は全件になる）" do
      completed_article("完読", Time.zone.local(2026, 10, 1, 9))

      [ nil, "0", "-1", "abc" ].each do |limit|
        expect { backfill.invoke(*limit) }.to raise_error(SystemExit).and output(/judgments:backfill\[20\]/).to_stderr
        backfill.reenable
      end
      expect(a_request(:post, JudgmentHelper::ENDPOINT)).not_to have_been_made
    end

    it "設定か API キーが揃っていなければ止まる" do
      with_env("TYPESAFE_API_KEY" => nil) do
        expect { backfill.invoke("1") }.to raise_error(SystemExit).and output(/TYPESAFE_API_KEY/).to_stderr
      end
    end

    it "判定できなかった記事は、失敗の理由を出して次へ進む" do
      completed_article("本文なし", Time.zone.local(2026, 10, 3, 9)).update!(content: nil)
      completed_article("本文あり", Time.zone.local(2026, 10, 1, 9))

      expect { backfill.invoke("2") }.to output(/失敗 本文が空 本文なし\n24 点 .* 本文あり/).to_stdout
    end

    it "一時的な失敗は、理由を画面に出して行を残さず、次の記事へ進む" do
      failing = completed_article("落ちる", Time.zone.local(2026, 10, 3, 9))
      completed_article("通る", Time.zone.local(2026, 10, 1, 9))
      stub_request(:post, JudgmentHelper::ENDPOINT)
        .to_return({ status: 503 }, { body: judgment_response(scores), headers: { "Content-Type" => "application/json" } })

      expect {
        expect { backfill.invoke("2") }.to output(/失敗 API エラー \(HTTP 503\).*打ち直せば.* 落ちる\n24 点 .* 通る/).to_stdout
      }.not_to have_enqueued_job(JudgeArticleJob)

      expect(failing.reload.judgment).to be_nil
    end

    it "鍵の誤り・残高切れは、理由を出して残りの記事を呼ばずに止まる" do
      completed_article("一本目", Time.zone.local(2026, 10, 3, 9))
      completed_article("二本目", Time.zone.local(2026, 10, 1, 9))
      stub_request(:post, JudgmentHelper::ENDPOINT).to_return(status: 402)

      expect { backfill.invoke("2") }.to raise_error(SystemExit).and output(/中止 API エラー \(HTTP 402\)/).to_stderr

      expect(a_request(:post, JudgmentHelper::ENDPOINT)).to have_been_made.once
      expect(ArticleJudgment.count).to eq(0)
    end

    it "日次の上限に達していたら、理由を出して 1 本も呼ばずに止まる" do
      completed_article("完読", Time.zone.local(2026, 10, 1, 9))
      allow(Claude::Budget).to receive(:default_limit).and_return(0)

      expect { backfill.invoke("1") }.to raise_error(SystemExit).and output(/中止 Claude daily call limit reached/).to_stderr

      expect(a_request(:post, JudgmentHelper::ENDPOINT)).not_to have_been_made
    end
  end

  describe "judgments:status" do
    it "判定済み・失敗・待ちの本数、合計点ごとの本数、軸ごとの平均、実費の合計を出す" do
      create(:article_judgment, **scores, cost: 0.0003)
      create(:article_judgment, **scores, originality: 3.6, cost: 0.0005)
      create(:article_judgment, :failed)
      create(:article, :awaiting_summary, :opened)

      expect { status.invoke }.to output(
        /判定済み 2 ・ 失敗 1 ・ 待ち 1\n25 点: 1 本\n24 点: 1 本\n平均 独自性 4\.5 ・ 深掘り 4\.0 .*\n実費 \$0\.0008（入力 2400 トークン。判定済みのぶんだけ/m
      ).to_stdout
    end

    it "費用の分からない判定だけなら、実費は 0 でなく不明と出す" do
      create(:article_judgment, **scores, cost: nil)

      expect { status.invoke }.to output(/実費 不明（入力 1200 トークン/).to_stdout
    end

    it "1 本も無くても落ちない" do
      expect { status.invoke }.to output(/判定済み 0 ・ 失敗 0 ・ 待ち 0/).to_stdout
    end
  end
end
