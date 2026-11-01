# 記事ページの本文を取る Job。{FeedFetcher} が記事を作るたびに 1 本積む（Unit 3b）。
# 取得済み（content_fetched_at あり）なら何もしない。失敗は {ArticleContentFetcher} が content_error に残すので retry_on は付けない。
# 積んだ後に記事が消されていたら何もせず捨てる
class FetchArticleContentJob < ApplicationJob
  queue_as :feeds

  discard_on ActiveJob::DeserializationError

  # @param article [Article] 本文を取りに行く記事
  # @return [ArticleContentFetcher::Result, nil] 取得済みなら nil
  def perform(article)
    return if article.content_fetched_at.present?

    ArticleContentFetcher.new(article).call
  end
end
