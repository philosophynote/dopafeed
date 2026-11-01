# 購読フィードを 1 本取りに行き、新しい記事を作る（Unit 3）。{FetchFeedJob} からだけ呼ぶ。
# 条件付き GET（If-None-Match / If-Modified-Since）で変わっていなければ解析しない。
# 取得・解析の失敗は例外にせず feeds.last_error に日本語で残す（nil なら前回は成功）。再試行は次の定期実行に任せる。
# last_fetched_at は成功・失敗を問わず「試行した時刻」。Feeds 画面の「更新 N 分前」はジョブが生きている印。
# 既存の記事は更新しない（要約と読了を守る）。本文は feedjira の entry.content か summary をそのまま（記事ページは取らない。Unit 3b）。
# 想定外の例外（バグ）はそのまま上げ、Solid Queue の失敗に残す
class FeedFetcher
  # 取得の結果
  # @!attribute status [r]
  #   @return [Symbol] :updated（解析した）/ :not_modified（304）/ :failed（last_error に残した）
  # @!attribute created [r]
  #   @return [Integer] 新しく作った記事の数
  # @!attribute error [r]
  #   @return [String, nil] 失敗の文言（feeds.last_error と同じ）
  Result = Data.define(:status, :created, :error)

  # 記録して終わりにする失敗（HTTP エラー、接続エラー、解析エラー）
  class FetchError < StandardError; end

  # 追うリダイレクトの上限。インフラの定数で報酬の数字ではないので dopamine.yml には置かない
  MAX_REDIRECTS = 3
  # 接続エラーとして last_error に残す例外（DNS・接続・切断・TLS・壊れた gzip・不正な URL）。これ以外は上げる
  NETWORK_ERRORS = [ SocketError, SystemCallError, IOError, Timeout::Error, OpenSSL::SSL::SSLError, Net::ProtocolError, Zlib::Error, URI::Error ].freeze
  # 取りに行く URL の scheme。それ以外（mailto: / ftp: / file:）は失敗として記録する
  SCHEMES = %w[http https].freeze
  USER_AGENT = "Dopafeed (+https://github.com/philosophynote/dopafeed)".freeze

  # @param feed [Feed] 取りに行くフィード
  def initialize(feed)
    @feed = feed
  end

  # 取得して記事を作り、feeds の取得状態を更新する
  #
  # @return [Result]
  def call
    response = get(URI(feed.url))
    return not_modified if response.is_a?(Net::HTTPNotModified)

    created = import(parse(response.body.to_s))
    feed.update!(last_fetched_at: Time.current, last_error: nil, etag: response["ETag"], last_modified: response["Last-Modified"])
    Result.new(status: :updated, created: created, error: nil)
  rescue FetchError, Feedjira::NoParserAvailable => e
    failed(e.is_a?(FetchError) ? e.message : "フィードを解析できません")
  rescue *NETWORK_ERRORS => e
    failed("接続エラー (#{e.class.name})")
  end

  private

  attr_reader :feed

  # 条件付き GET。リダイレクトは MAX_REDIRECTS 回まで追う
  #
  # @param uri [URI::HTTP]
  # @param redirects [Integer] ここまでに追った回数
  # @return [Net::HTTPResponse] 2xx か 304
  # @raise [FetchError] 2xx / 304 以外、リダイレクト超過
  def get(uri, redirects = 0)
    raise FetchError, "URL が http(s) ではありません" unless SCHEMES.include?(uri.scheme)

    response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
      http.request(Net::HTTP::Get.new(uri, request_headers))
    end

    case response
    when Net::HTTPSuccess, Net::HTTPNotModified
      response
    when Net::HTTPRedirection
      raise FetchError, "リダイレクトが多すぎます" if redirects >= MAX_REDIRECTS
      raise FetchError, "サーバーエラー (HTTP #{response.code})" if response["Location"].blank?

      get(URI.join(uri, response["Location"]), redirects + 1)
    else
      raise FetchError, "サーバーエラー (HTTP #{response.code})"
    end
  end

  # @return [Hash{String => String}] UA と、前回の ETag / Last-Modified があれば条件付きヘッダ
  def request_headers
    {
      "User-Agent" => USER_AGENT,
      "Accept" => "application/rss+xml, application/atom+xml, application/xml, text/xml",
      "If-None-Match" => feed.etag,
      "If-Modified-Since" => feed.last_modified
    }.compact
  end

  # 本文を Feedjira で解析する。Feedjira は途中で切れた XML も黙って entries 空で返すので、先に Nokogiri の strict で閉じを確かめる
  #
  # @param body [String] 応答本文
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
  # 同じフィードの Job が重なって先に入られたら（url の一意制約）その entry は飛ばす
  #
  # @param parsed [Feedjira::Parser::RSS, Feedjira::Parser::Atom] Feedjira.parse の戻り
  # @return [Integer] 作った記事の数
  def import(parsed)
    parsed.entries.count do |entry|
      title = entry.title.to_s.strip
      url = entry.url.to_s.strip
      next false if title.blank? || !url.start_with?("http://", "https://")

      guid = entry.entry_id.presence || url
      next false if feed.articles.exists?(guid: guid) || Article.exists?(url: url)

      feed.articles.create!(title: title, url: url, guid: guid, published_at: entry.published, content: entry.content.presence || entry.summary)
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

  # @param message [String] last_error に残す文言
  # @return [Result] :failed
  def failed(message)
    feed.update!(last_fetched_at: Time.current, last_error: message)
    Result.new(status: :failed, created: 0, error: message)
  end
end
