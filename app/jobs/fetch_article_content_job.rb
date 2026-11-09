# 同じホストへ同時に 20〜30 本取りに行くと 429 になるため、1 本ずつ取得する。
# queue は別 DB なので、記事が見つからない場合もコミット前の可能性がある。既定回数だけ待ち、削除済みなら捨てる。
class FetchArticleContentJob < ApplicationJob
  queue_as :feeds

  retry_on ActiveJob::DeserializationError, wait: :polynomially_longer do |job, error|
    Rails.logger.info("[feeds] #{job.class.name} discarded: #{error.message}")
  end

  retry_on HttpGet::TransientError, wait: :polynomially_longer do |job, error|
    article = job.arguments.first
    ArticleContentFetcher.new(article).record_failure(error.message)
    Claude::SummarizeArticleJob.enqueue_if_awaiting(article)
  end

  limits_concurrency key: ->(article) { FetchArticleContentJob.host_of(article) }

  def self.host_of(article)
    URI(article.url).host.presence || article.url
  rescue URI::Error
    article.url
  end

  def perform(article)
    return if article.content_fetched_at.present?

    ArticleContentFetcher.new(article).call.tap { Claude::SummarizeArticleJob.enqueue_if_awaiting(article) }
  end
end
