# HTTP GET を 1 箇所に。{FeedFetcher}（フィード）と {ArticleContentFetcher}（記事ページ）が使う。
# scheme の検査、リダイレクトの追従、2xx / 304 以外と接続エラーを {Error} に畳む（文言は feeds.last_error / articles.content_error にそのまま残る）。
# タイムアウトは Net::HTTP の既定（dopamine.yml に fetch.timeout_seconds が入ればそこから読む）。本文サイズの上限と SSRF 対策は #23
class HttpGet
  # 記録して終わりにする失敗（HTTP エラー、接続エラー、不正な URL）
  class Error < StandardError; end

  # 追うリダイレクトの上限。インフラの定数で報酬の数字ではないので dopamine.yml には置かない（PR #19 の提案欄）
  MAX_REDIRECTS = 3
  # 接続エラーとして畳む例外（DNS・接続・切断・TLS・壊れた gzip・不正な URL）。これ以外は上げる
  NETWORK_ERRORS = [ SocketError, SystemCallError, IOError, Timeout::Error, OpenSSL::SSL::SSLError, Net::ProtocolError, Zlib::Error, URI::Error ].freeze
  # 取りに行く URL の scheme。それ以外（mailto: / ftp: / file:）は Error
  SCHEMES = %w[http https].freeze
  USER_AGENT = "Dopafeed (+https://github.com/philosophynote/dopafeed)".freeze

  # @param url [String] 取りに行く URL
  # @param headers [Hash{String => String}] 足すヘッダ（条件付き GET の If-None-Match など）
  # @return [Net::HTTPResponse] 2xx か 304
  # @raise [Error] http(s) でない、2xx / 304 以外、リダイレクト超過、接続エラー
  def self.call(url, headers: {})
    new(headers).get(URI(url))
  rescue *NETWORK_ERRORS => e
    raise Error, "接続エラー (#{e.class.name})"
  end

  # @param headers [Hash{String => String}]
  def initialize(headers)
    @headers = { "User-Agent" => USER_AGENT }.merge(headers)
  end

  # @param uri [URI::Generic]
  # @param redirects [Integer] ここまでに追った回数
  # @return [Net::HTTPResponse] 2xx か 304
  # @raise [Error]
  def get(uri, redirects = 0)
    raise Error, "URL が http(s) ではありません" unless SCHEMES.include?(uri.scheme)

    response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
      http.request(Net::HTTP::Get.new(uri, @headers))
    end

    case response
    when Net::HTTPSuccess, Net::HTTPNotModified
      response
    when Net::HTTPRedirection
      raise Error, "リダイレクトが多すぎます" if redirects >= MAX_REDIRECTS
      raise Error, "サーバーエラー (HTTP #{response.code})" if response["Location"].blank?

      get(URI.join(uri, response["Location"]), redirects + 1)
    else
      raise Error, "サーバーエラー (HTTP #{response.code})"
    end
  end
end
