# 記事ページの本文を取る Job。{FeedFetcher} が記事を作るたびに 1 本積む（Unit 3b）。
# 取得済み（content_fetched_at あり）なら何もしない。4xx・HTML 以外・本文なしは {ArticleContentFetcher} が content_error に残す。
# 待てば通るかもしれない失敗（{HttpGet::TransientError}: 408・429・5xx・接続エラー）は ActiveJob の既定の回数・間隔で
# やり直し、尽きたら失敗として記録する。同じホストへは 1 本ずつ（新しいフィードの初回に 20〜30 本を同時に叩いて 429 にならないため。
# 待ち時間は Solid Queue の既定）。積んだ後に記事が消されていたら何もせず捨てる
class FetchArticleContentJob < ApplicationJob
  queue_as :feeds

  discard_on ActiveJob::DeserializationError

  retry_on HttpGet::TransientError, wait: :polynomially_longer do |job, error|
    ArticleContentFetcher.new(job.arguments.first).record_failure(error.message)
  end

  limits_concurrency key: ->(article) { FetchArticleContentJob.host_of(article) }

  # @param article [Article]
  # @return [String] 記事 URL のホスト。読めない URL ならその URL
  def self.host_of(article)
    URI(article.url).host.presence || article.url
  rescue URI::Error
    article.url
  end

  # @param article [Article] 本文を取りに行く記事
  # @return [ArticleContentFetcher::Result, nil] 取得済みなら nil
  def perform(article)
    return if article.content_fetched_at.present?

    ArticleContentFetcher.new(article).call
  end
end
