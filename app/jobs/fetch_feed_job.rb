# retry_on は付けず、次回の定期実行で再試行する。
# 重複を待たせても直後に同じ取得を繰り返すだけなので捨てる。
# ロック期限切れでは二重取得しうるが、調整用の期限を持つほどの害はない。
class FetchFeedJob < ApplicationJob
  queue_as :feeds

  discard_on ActiveJob::DeserializationError

  limits_concurrency key: ->(feed) { feed.id }, on_conflict: :discard

  def perform(feed)
    FeedFetcher.new(feed).call
  end
end
