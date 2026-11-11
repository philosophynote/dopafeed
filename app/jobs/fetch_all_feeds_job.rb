# 自分で全件取得すると、1 本の失敗や遅さが他のフィードを巻き込む。
class FetchAllFeedsJob < ApplicationJob
  queue_as :feeds

  def perform
    Feed.find_each { |feed| FetchFeedJob.perform_later(feed) }
  end
end
