# フィードを 1 本取る Job。{FetchAllFeedsJob} が定期的に積む。
# 取得の失敗は {FeedFetcher} が feeds.last_error に残すので retry_on は付けない。次回の定期実行が再試行になる。
# 積んだ後にフィードが消されていたら何もせず捨てる
class FetchFeedJob < ApplicationJob
  queue_as :feeds

  discard_on ActiveJob::DeserializationError

  # @return [FeedFetcher::Result]
  def perform(feed)
    FeedFetcher.new(feed).call
  end
end
