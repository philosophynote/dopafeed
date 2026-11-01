# フィードを 1 本取る Job。{FetchAllFeedsJob} が定期的に積む（AddFeed の「追加」も即時に積む。第二の陣）。
# 取得の失敗は {FeedFetcher} が feeds.last_error に残すので retry_on は付けない。次回の定期実行が再試行になる
class FetchFeedJob < ApplicationJob
  queue_as :feeds

  # @param feed [Feed] 取りに行くフィード
  # @return [FeedFetcher::Result]
  def perform(feed)
    FeedFetcher.new(feed).call
  end
end
