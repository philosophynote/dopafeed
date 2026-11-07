require "rake"

RSpec.describe "summaries の rake task" do
  include ActiveJob::TestHelper

  before(:all) { Rails.application.load_tasks if Rake::Task.tasks.none? { |task| task.name.start_with?("summaries:") } }

  def run(name)
    Rake::Task[name].execute
  end

  describe "summaries:retry" do
    it "失敗した記事を要約待ちに戻し、件数と次に拾う時機を出す（API は呼ばない）" do
      failed = create_list(:article, 2, :summary_failed)

      expect { run("summaries:retry") }.to output(/2 本を要約待ちに戻しました/).to_stdout

      expect(Article.awaiting_summary).to match_array(failed)
      expect(ClaudeApiCall.count).to eq(0)
      expect(enqueued_jobs).to be_empty
    end

    it "失敗が無ければそう言う" do
      expect { run("summaries:retry") }.to output(/要約に失敗した記事はありません/).to_stdout
    end
  end

  describe "summaries:status" do
    it "要約済み・待ち・本文取得前・失敗の数、失敗の内訳、今日の予算を出す" do
      create_list(:article, 3)
      create(:article, :awaiting_summary)
      create(:article, :unsummarized)
      create_list(:article, 2, :summary_failed)
      create(:article, :summary_failed, summary_error: "本文が空")
      ClaudeApiCall.create!(purpose: "summary", model: "claude-haiku")

      expect { run("summaries:status") }.to output(<<~TEXT).to_stdout
        要約済み 3 / 要約待ち 1 / 本文取得前 1 / 失敗 3
        失敗の内訳:
          2 応答の形式が不正
          1 本文が空
        今日の予算: 1 / #{Claude::Budget.default_limit} 回
      TEXT
    end
  end
end
