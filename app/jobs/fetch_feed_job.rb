# フィードを 1 本取る Job。{FetchAllFeedsJob} が定期的に積む（AddFeed の「追加」も即時に積む。第二の陣）。
# 取得の失敗は {FeedFetcher} が feeds.last_error に残すので retry_on は付けない。次回の定期実行が再試行になる。
# 積んだ後にフィードが消されていたら（Feeds 画面の削除）何もせず捨てる
class FetchFeedJob < ApplicationJob
  queue_as :feeds

  discard_on ActiveJob::DeserializationError

  # @param feed [Feed] 取りに行くフィード
  # @return [FeedFetcher::Result]
  def perform(feed)
    FeedFetcher.new(feed).call
  end
end
