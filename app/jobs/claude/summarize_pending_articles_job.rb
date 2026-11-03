module Claude
  # 要約待ちの記事を、その日の予算の残りぶんだけ {SummarizeArticleJob} に積む。定期実行は config/recurring.yml。
  # 記事を作った直後に積まない理由: 本文取得が終わる前に要約すると、フィードの薄い本文を要約したまま二度と直らない。
  # 1 回の本数の鍵は持たず claude.daily_call_limit だけで頭打ちにする。積み残しは次の回に回る
  class SummarizePendingArticlesJob < ApplicationJob
    queue_as :claude

    # @return [Integer] 積んだ数
    def perform
      remaining = Budget.new.remaining
      return 0 if remaining.zero?

      Article.awaiting_summary.newest_first.limit(remaining).to_a.each { |article| SummarizeArticleJob.perform_later(article) }.size
    end
  end
end
