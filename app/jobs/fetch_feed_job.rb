# フィードを 1 本取る Job。
# 取得の失敗は {FeedFetcher} が feeds.last_error に残すので retry_on は付けない。次回の定期実行が再試行になる。
# 積んだ後にフィードが消されていたら何もせず捨てる。
# 同じフィードの Job が待ち・実行中のときに積まれた分は捨てる（前の回が詰まっていると定期実行と手動の更新が重なり、同じ取得が 2 回走る）。
# 待たせずに捨てるのは、待たせても前の回の直後に同じ取得をもう一度するだけだから。
# ロックの持ち時間は Solid Queue の既定のまま。取得が長引いても終われば返るので、持ち時間で決まるのはワーカーが落ちたときに解けるまでの長さだけ
class FetchFeedJob < ApplicationJob
  queue_as :feeds

  discard_on ActiveJob::DeserializationError

  limits_concurrency key: ->(feed) { feed.id }, on_conflict: :discard

  def perform(feed)
    FeedFetcher.new(feed).call
  end
end
