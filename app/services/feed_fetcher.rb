# 購読フィードを 1 本取りに行き、新しい記事を作る。
# 条件付き GET（If-None-Match / If-Modified-Since）で変わっていなければ解析しない。
# 取得・解析の失敗は例外にせず feeds.last_error に日本語で残す。再試行は次の定期実行に任せる。
# last_fetched_at は失敗でも更新する（取得が止まっているのか、失敗し続けているのかを見分けるため）。
# 既存の記事は更新しない（要約と読了を守る）。本文はまず feedjira の entry.content か summary を入れ、記事ごとに {FetchArticleContentJob} を積んで
# 記事ページの本文で置き換える。HTTP は {HttpGet}。想定外の例外（バグ）はそのまま上げ、Solid Queue の失敗に残す
class FeedFetcher
  # 取得の結果
  # @!attribute status [r]
  #   @return [Symbol] :updated（解析した）/ :not_modified（304）/ :failed（last_error に残した）
  # @!attribute created [r]
  #   @return [Integer] 新しく作った記事の数
  # @!attribute error [r]
  #   @return [String, nil] 失敗の文言（feeds.last_error と同じ）
  Result = Data.define(:status, :created, :error)

  # 記録して終わりにする失敗（解析エラー。HTTP・接続エラーは {HttpGet::Error}）
  class FetchError < StandardError; end

  def initialize(feed)
    @feed = feed
  end

  # 取得して記事を作り、feeds の取得状態を更新する
  #
  # @return [Result]
  def call
    response = HttpGet.call(feed.url, headers: conditional_headers)
    return not_modified if response.is_a?(Net::HTTPNotModified)

    created = import(parse(response.body.to_s))
    feed.update!(last_fetched_at: Time.current, last_error: nil, etag: response["ETag"], last_modified: response["Last-Modified"])
    Result.new(status: :updated, created: created, error: nil)
  rescue HttpGet::Error, FetchError => e
    failed(e.message)
  rescue Feedjira::NoParserAvailable
    failed("フィードを解析できません")
  end

  private

  attr_reader :feed

  # @return [Hash{String => String}] Accept と、前回の ETag / Last-Modified があれば条件付きヘッダ
  def conditional_headers
    {
      "Accept" => "application/rss+xml, application/atom+xml, application/xml, text/xml",
      "If-None-Match" => feed.etag,
      "If-Modified-Since" => feed.last_modified
    }.compact
  end

  # 本文を Feedjira で解析する。Feedjira は途中で切れた XML も黙って entries 空で返すので、先に Nokogiri の strict で閉じを確かめる
  #
  # @return [Feedjira::Parser::RSS, Feedjira::Parser::Atom]
  # @raise [FetchError] XML として壊れている
  # @raise [Feedjira::NoParserAvailable] XML だがフィードではない
  def parse(body)
    Nokogiri::XML(body, &:strict)
    Feedjira.parse(body)
  rescue Nokogiri::XML::SyntaxError
    raise FetchError, "フィードを解析できません"
  end

  # 解析した entry を記事にする。title か http(s) の url の無い entry は飛ばす。
  # 重複は [feed_id, guid]（guid = entry_id、無ければ url）→ url（全フィードで一意）の順で見る。
  # 同じフィードの Job が重なって先に入られたら（url の一意制約）その entry は飛ばす。作った記事ごとに本文取得 Job を積む。
  # 記事の作成と Job の積み込みは 1 トランザクション: 本番は queue が別 DB なので、積めなければ記事ごと戻して次の取得でやり直す
  # （enqueue_after_transaction_commit は false。コミット後に積む設定にするとこの戻しが効かなくなる）
  #
  # @return [Integer] 作った記事の数
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

  # @return [Result] 304。試行時刻だけ更新し、ETag / Last-Modified は前回のまま
  def not_modified
    feed.update!(last_fetched_at: Time.current, last_error: nil)
    Result.new(status: :not_modified, created: 0, error: nil)
  end

  # @return [Result] :failed
  def failed(message)
    feed.update!(last_fetched_at: Time.current, last_error: message)
    Result.new(status: :failed, created: 0, error: message)
  end
end
