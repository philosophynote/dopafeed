# 全フィードの取得を 1 本ずつ {FetchFeedJob} に積む。config/recurring.yml が定期的に呼ぶ（本番）。
# 自分では取りに行かない（1 本の失敗や遅さが他のフィードを巻き込まないため）
class FetchAllFeedsJob < ApplicationJob
  queue_as :feeds

  def perform
    Feed.find_each { |feed| FetchFeedJob.perform_later(feed) }
  end
end
