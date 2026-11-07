require "ipaddr"
require "resolv"

# HTTP GET の唯一の入口。フィードも記事ページも同じ検査と失敗の畳み方を通す。
# scheme の検査、宛先が内部ネットワークでないことの検査、リダイレクトの追従、本文サイズの上限、
# 2xx / 304 以外と接続エラーを {Error} に畳む（文言は feeds.last_error / articles.content_error にそのまま残る）。
# 時間を置けば通るかもしれない失敗は {TransientError}。呼ぶ側が待ってやり直すか決める。
# content_types を渡すと、2xx でも Content-Type が合わない応答は本文を読まずに {UnexpectedContentType}（巨大な PDF や動画をメモリに載せない）。
# タイムアウトは dopamine.yml の fetch.timeout_seconds（接続・読み取りとも）、本文の上限は fetch.max_body_megabytes
class HttpGet
  # 記録して終わりにする失敗（HTTP エラー、不正な URL、内部ネットワークの宛先、大きすぎる本文）
  class Error < StandardError; end
  # 待てば通るかもしれない失敗（408・429・5xx・接続エラー）
  class TransientError < Error; end
  # content_types に無い Content-Type の応答。message は応答の Content-Type（無ければ空）
  class UnexpectedContentType < Error; end

  # 上限で読むのをやめる本文。{Net::HTTPResponse#read_body} の dest に渡すと、解凍後のチャンクが << で届く
  # （gzip 爆弾も展開後の大きさで止まる）。String を継承するのは、読み終わった response.body がこれになり、
  # 呼ぶ側が普通の文字列として扱うため
  class BoundedBody < String
    def initialize(limit, message)
      super()
      @limit = limit
      @message = message
    end

    def <<(chunk)
      raise Error, @message if bytesize + chunk.bytesize > @limit

      super
    end
  end

  # 返す応答に足す、恒久移転の行き先
  module Moved
    # @return [String, nil] 最初の URL から 301 / 308 だけで辿った最後の URL。302 / 307 が挟まればその手前まで（一時的な寄り道の先は覚えない）。
    #   ホストを小文字にしてフラグメントを落とす（保存済みの URL と突き合わせるため）。移転が無ければ nil
    attr_accessor :permanent_url
  end

  PERMANENT_REDIRECTS = [ Net::HTTPMovedPermanently, Net::HTTPPermanentRedirect ].freeze
  # 追うリダイレクトの上限。インフラの定数で報酬の数字ではないので dopamine.yml には置かない
  MAX_REDIRECTS = 3
  # 接続エラー（TransientError）に畳む例外（DNS・接続・切断・TLS・壊れた gzip）。これ以外は上げる
  NETWORK_ERRORS = [ SocketError, SystemCallError, IOError, Timeout::Error, OpenSSL::SSL::SSLError, Net::ProtocolError, Zlib::Error, Resolv::ResolvError ].freeze
  # 取りに行く URL の scheme。それ以外（mailto: / ftp: / file:）は Error
  SCHEMES = %w[http https].freeze
  # 取りに行かない宛先。ループバック・プライベート・リンクローカル（クラウドのインスタンスメタデータ 169.254.169.254 を含む）・
  # 未指定・共有アドレス・マルチキャスト・予約帯（IETF 用、ベンチマーク用、240/4）。外部サイトへ飛ぶ記事リンクを日々取りに
  # 行くので、どこへ飛ばされても内側には届かせない。IPv6 の ::/96 は IPv4 互換（::127.0.0.1）で、中身を見ずに丸ごと塞ぐ
  INTERNAL_RANGES = %w[
    0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16 172.16.0.0/12 192.0.0.0/24 192.168.0.0/16
    198.18.0.0/15 224.0.0.0/4 240.0.0.0/4
    ::/96 fc00::/7 fe80::/10 ff00::/8
  ].map { |cidr| IPAddr.new(cidr) }.freeze
  USER_AGENT = "Dopafeed (+https://github.com/philosophynote/dopafeed)".freeze

  # @param headers [Hash{String => String}] 足すヘッダ（Accept、条件付き GET の If-None-Match など）
  # @param content_types [Array<String>, nil] 受け入れる Content-Type（小文字、パラメータ抜き）。nil なら何でも読む
  # @return [Net::HTTPResponse, Moved] 2xx か 304。本文は読み込み済み
  # @raise [Error] http(s) でない、壊れた URL、ホスト名の無い URL、内部ネットワークの宛先、4xx、リダイレクト超過、本文が上限超
  # @raise [TransientError] 408・429・5xx、接続エラー（名前が引けない場合を含む）
  # @raise [UnexpectedContentType] content_types に無い Content-Type
  def self.call(url, headers: {}, content_types: nil)
    fold_errors { new(headers, content_types).get(URI(url)) }
  end

  # 取りに行かずに宛先だけ検査する。自前で HTTP を話す相手にも同じ判定を通すため。
  # 繋ぐのは呼ぶ側なので、検査の後に名前を引き直される DNS rebinding までは防げない。申告の時点で内側を指す URL を弾くのが役目
  #
  # @return [nil]
  # @raise [Error] http(s) でない、壊れた URL、ホスト名の無い URL、内部ネットワークの宛先
  # @raise [TransientError] 名前が引けない
  def self.verify_external!(url)
    fold_errors { new({}).check!(URI(url)) }
    nil
  end

  # URI と接続の例外を {Error} / {TransientError} に畳む。呼ぶ側が rescue する型を 2 つに保つ
  def self.fold_errors
    yield
  rescue URI::Error => e
    raise Error, "接続エラー (#{e.class.name})"
  rescue *NETWORK_ERRORS => e
    raise TransientError, "接続エラー (#{e.class.name})"
  end
  private_class_method :fold_errors

  def initialize(headers, content_types = nil)
    @headers = { "User-Agent" => USER_AGENT }.merge(headers)
    @content_types = content_types
    @permanent_url = nil
    @permanent_chain = true
  end

  # @param redirects [Integer] ここまでに追った回数
  # @return [Net::HTTPResponse] 2xx か 304
  def get(uri, redirects = 0)
    # 検査した IP にそのまま繋ぐ（ipaddr:）。Net::HTTP に名前を引き直させると、検査の後で内部アドレスに変わる
    # DNS rebinding が通る。TLS の証明書検証と SNI はホスト名のまま。http_proxy 環境変数があると Net::HTTP は
    # プロキシに名前を引かせるので ipaddr: は効かない（本番に置かない前提）
    response = Net::HTTP.start(uri.hostname, uri.port, ipaddr: check!(uri), use_ssl: uri.scheme == "https", open_timeout: timeout, read_timeout: timeout) do |http|
      http.request(Net::HTTP::Get.new(uri, @headers)) do |res|
        raise UnexpectedContentType, res.content_type.to_s if res.is_a?(Net::HTTPSuccess) && unexpected_content_type?(res)
        raise Error, too_large if res.content_length.to_i > max_body_bytes

        res.read_body(BoundedBody.new(max_body_bytes, too_large))
      end
    end

    case response
    when Net::HTTPSuccess, Net::HTTPNotModified
      response.extend(Moved).tap { |res| res.permanent_url = @permanent_url }
    when Net::HTTPRedirection
      raise Error, "リダイレクトが多すぎます" if redirects >= MAX_REDIRECTS
      raise Error, "サーバーエラー (HTTP #{response.code})" if response["Location"].blank?

      location = URI.join(uri, response["Location"])
      remember_move(response, location)
      get(location, redirects + 1)
    when Net::HTTPServerError, Net::HTTPTooManyRequests, Net::HTTPRequestTimeout
      raise TransientError, "サーバーエラー (HTTP #{response.code})"
    else
      raise Error, "サーバーエラー (HTTP #{response.code})"
    end
  end

  # scheme・ホスト名・宛先の検査。繋ぐ前に通す
  #
  # @return [String] 繋いでよい IP（Net::HTTP の ipaddr: に渡す形）
  def check!(uri)
    raise Error, "URL が http(s) ではありません" unless SCHEMES.include?(uri.scheme)
    # 名前が引けない（空は DNS に回すと「引けない」になり、待っても通らないのに再試行される）
    raise Error, "URL にホスト名がありません" if uri.hostname.blank?

    resolve(uri.hostname)
  end

  private

  def remember_move(response, location)
    @permanent_chain &&= PERMANENT_REDIRECTS.any? { |klass| response.is_a?(klass) }
    @permanent_url = location.dup.tap { |uri| uri.fragment = nil }.normalize.to_s if @permanent_chain
  end

  # ホスト名を解き、解けた全アドレスが内部ネットワークでないことを確かめる。一つでも内側なら取りに行かない。
  # 繋ぐのは先頭の 1 つ（残りへのフォールバックは Net::HTTP に戻さない。戻すと名前を引き直す）
  #
  # @return [String] Net::HTTP の ipaddr: に渡す形
  def resolve(host)
    addresses = addresses_of(host)
    raise Resolv::ResolvError, "名前が引けません (#{host})" if addresses.empty?
    raise Error, "内部ネットワークの URL です" if addresses.any? { |address| internal?(address) }

    addresses.first.to_s
  end

  # @return [Array<IPAddr>] IP リテラルならそれ自身、名前なら /etc/hosts と DNS で解けた全アドレス
  def addresses_of(host)
    [ IPAddr.new(host) ]
  rescue IPAddr::InvalidAddressError
    # 既定の Resolv は死んだリゾルバ相手に 5・10・20・40 秒と粘り、それを A と AAAA、検索ドメインの候補ごとに
    # 繰り返す。問い合わせ 1 回ずつではなく名前解決の全体を fetch.timeout_seconds で切る
    Timeout.timeout(timeout, Resolv::ResolvTimeout) { Resolv.getaddresses(host) }.map { |address| IPAddr.new(address) }
  end

  # IPv4-mapped IPv6（::ffff:127.0.0.1）は中の IPv4 で判定する。そのままでは IPv6 の帯に当たらず素通りする
  def internal?(address)
    address = address.native if address.ipv4_mapped?
    INTERNAL_RANGES.any? { |range| range.include?(address) }
  end

  # @return [Integer] 接続と読み取りそれぞれの待ち時間（秒）。dopamine.yml の fetch.timeout_seconds
  def timeout
    Dopamine.settings.dig(:fetch, :timeout_seconds)
  end

  # @return [Integer] 本文（解凍後）の上限バイト数。dopamine.yml の fetch.max_body_megabytes
  def max_body_bytes
    Dopamine.settings.dig(:fetch, :max_body_megabytes) * 1024 * 1024
  end

  def too_large
    "応答が大きすぎます (#{Dopamine.settings.dig(:fetch, :max_body_megabytes)} MB 超)"
  end

  # @return [Boolean] content_types が指定されていて、応答の Content-Type（大文字小文字を無視）がそこに無い
  def unexpected_content_type?(response)
    @content_types.present? && !@content_types.include?(response.content_type.to_s.downcase)
  end
end
