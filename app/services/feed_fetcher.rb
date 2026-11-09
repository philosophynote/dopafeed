# 既存の記事を更新すると要約と読了を失うため、新着だけ取り込む。
# 解析失敗の移転先を保存すると、フィードを廃止してトップへ転送するサイトで元の URL を失う。
class FeedFetcher
  Result = Data.define(:status, :created, :error)

  def initialize(feed)
    @feed = feed
  end

  def call
    response = HttpGet.call(feed.url, headers: conditional_headers)
    return not_modified(response.permanent_url) if response.is_a?(Net::HTTPNotModified)

    created = import(FeedDocument.parse(response.body.to_s))
    move_to(response.permanent_url)
    feed.update!(last_fetched_at: Time.current, last_error: nil, etag: response["ETag"], last_modified: response["Last-Modified"])
    Result.new(status: :updated, created: created, error: nil)
  rescue HttpGet::Error => e
    failed(e.message)
  rescue FeedDocument::Error
    failed("フィードを解析できません")
  end

  private

  attr_reader :feed

  def conditional_headers
    {
      "Accept" => "application/rss+xml, application/atom+xml, application/xml, text/xml",
      "If-None-Match" => feed.etag,
      "If-Modified-Since" => feed.last_modified
    }.compact
  end

  # 本番は queue が別 DB なので、Job を積めなければ記事も戻さないと次の取得で拾い直せない。
  # enqueue_after_transaction_commit を有効にすると、このロールバックが効かなくなる。
  def import(parsed)
    parsed.entries.count do |entry|
      title = entry.title.to_s.strip
      url = entry.url.to_s.strip
      next false if title.blank? || !url.start_with?("http://", "https://")

      guid = entry.entry_id.presence || url
      next false if feed.articles.exists?(guid: guid) || Article.exists?(url: url)

      Article.transaction do
        article = feed.articles.create!(title: title, url: url, guid: guid, published_at: entry.published, content: entry.content.presence || entry.summary)
        FetchArticleContentJob.perform_later(article)
      end
      true
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
      false
    end
  end

  # 移転先が他の購読の URL なら直さない（同じフィードを二つ購読している。どちらを残すかは人が決める）。
  # https から http への移転も直さない（一度の応答で以後ずっと平文で取りに行くことになる）
  def move_to(url)
    return if url.nil? || url == feed.url
    return if URI(feed.url).scheme == "https" && URI(url).scheme == "http"
    return keep_url(url) if Feed.exists?(url: url)

    feed.update!(url: url)
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
    feed.restore_attributes([ :url ])
    keep_url(url)
  end

  def keep_url(url)
    Rails.logger.info("[feeds] feed #{feed.id} は #{url} へ移転したが、同じ URL の購読があるので URL を直さない")
  end

  def not_modified(permanent_url)
    move_to(permanent_url)
    feed.update!(last_fetched_at: Time.current, last_error: nil)
    Result.new(status: :not_modified, created: 0, error: nil)
  end

  def failed(message)
    feed.update!(last_fetched_at: Time.current, last_error: message)
    Result.new(status: :failed, created: 0, error: message)
  end
end
