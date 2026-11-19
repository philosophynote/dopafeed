class PurgeArticlesJob < ApplicationJob
  queue_as :feeds

  def perform
    result = ArticleRetention.call
    Rails.logger.info("[retention] 削除済み #{result.dismissed} 本、未読 #{result.unread} 本を消した")
  end
end
