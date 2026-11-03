# HTTP GET を 1 箇所に。{FeedFetcher}（フィード）と {ArticleContentFetcher}（記事ページ）が使う。
# scheme の検査、リダイレクトの追従、2xx / 304 以外と接続エラーを {Error} に畳む（文言は feeds.last_error / articles.content_error にそのまま残る）。
# 時間を置けば通るかもしれない失敗（408・429・5xx・接続エラー）は {TransientError}。呼ぶ側が待ってやり直すか決める。
# content_types を渡すと、2xx でも Content-Type が合わない応答は本文を読まずに {UnexpectedContentType}（巨大な PDF や動画をメモリに載せない）。
# タイムアウトは dopamine.yml の fetch.timeout_seconds（接続・読み取りとも）
class HttpGet
  # 記録して終わりにする失敗（HTTP エラー、不正な URL）
  class Error < StandardError; end
  # 待てば通るかもしれない失敗（408・429・5xx・接続エラー）
  class TransientError < Error; end
  # content_types に無い Content-Type の応答。message は応答の Content-Type（無ければ空）
  class UnexpectedContentType < Error; end

  # 追うリダイレクトの上限。インフラの定数で報酬の数字ではないので dopamine.yml には置かない
  MAX_REDIRECTS = 3
  # 接続エラー（TransientError）に畳む例外（DNS・接続・切断・TLS・壊れた gzip）。これ以外は上げる
  NETWORK_ERRORS = [ SocketError, SystemCallError, IOError, Timeout::Error, OpenSSL::SSL::SSLError, Net::ProtocolError, Zlib::Error ].freeze
  # 取りに行く URL の scheme。それ以外（mailto: / ftp: / file:）は Error
  SCHEMES = %w[http https].freeze
  USER_AGENT = "Dopafeed (+https://github.com/philosophynote/dopafeed)".freeze

  # @param url [String] 取りに行く URL
  # @param headers [Hash{String => String}] 足すヘッダ（Accept、条件付き GET の If-None-Match など）
  # @param content_types [Array<String>, nil] 受け入れる Content-Type（小文字、パラメータ抜き）。nil なら何でも読む
  # @return [Net::HTTPResponse] 2xx か 304。本文は読み込み済み
  # @raise [Error] http(s) でない、壊れた URL、4xx、リダイレクト超過
  # @raise [TransientError] 408・429・5xx、接続エラー
  # @raise [UnexpectedContentType] content_types に無い Content-Type
  def self.call(url, headers: {}, content_types: nil)
    new(headers, content_types).get(URI(url))
  rescue URI::Error => e
    raise Error, "接続エラー (#{e.class.name})"
  rescue *NETWORK_ERRORS => e
    raise TransientError, "接続エラー (#{e.class.name})"
  end

  # @param headers [Hash{String => String}]
  # @param content_types [Array<String>, nil]
  def initialize(headers, content_types = nil)
    @headers = { "User-Agent" => USER_AGENT }.merge(headers)
    @content_types = content_types
  end

  # @param uri [URI::Generic]
  # @param redirects [Integer] ここまでに追った回数
  # @return [Net::HTTPResponse] 2xx か 304
  # @raise [Error, TransientError, UnexpectedContentType]
  def get(uri, redirects = 0)
    raise Error, "URL が http(s) ではありません" unless SCHEMES.include?(uri.scheme)

    response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: timeout, read_timeout: timeout) do |http|
      http.request(Net::HTTP::Get.new(uri, @headers)) do |res|
        raise UnexpectedContentType, res.content_type.to_s if res.is_a?(Net::HTTPSuccess) && unexpected_content_type?(res)

        res.read_body
      end
    end

    case response
    when Net::HTTPSuccess, Net::HTTPNotModified
      response
    when Net::HTTPRedirection
      raise Error, "リダイレクトが多すぎます" if redirects >= MAX_REDIRECTS
      raise Error, "サーバーエラー (HTTP #{response.code})" if response["Location"].blank?

      get(URI.join(uri, response["Location"]), redirects + 1)
    when Net::HTTPServerError, Net::HTTPTooManyRequests, Net::HTTPRequestTimeout
      raise TransientError, "サーバーエラー (HTTP #{response.code})"
    else
      raise Error, "サーバーエラー (HTTP #{response.code})"
    end
  end

  private

  # @return [Integer] 接続と読み取りそれぞれの待ち時間（秒）。dopamine.yml の fetch.timeout_seconds
  def timeout
    Dopamine.settings.dig(:fetch, :timeout_seconds)
  end

  # @param response [Net::HTTPResponse]
  # @return [Boolean] content_types が指定されていて、応答の Content-Type（大文字小文字を無視）がそこに無い
  def unexpected_content_type?(response)
    @content_types.present? && !@content_types.include?(response.content_type.to_s.downcase)
  end
end
