require "ipaddr"
require "resolv"

class HttpGet
  class Error < StandardError; end
  class TransientError < Error; end
  class UnexpectedContentType < Error; end

  # read_body の dest で展開後のサイズを制限しないと、gzip 爆弾を止められない。
  # response.body としても返るため String を継承する。
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

  module Moved
    attr_accessor :final_url

    # 一時的な寄り道の先を恒久移転として保存しない。
    attr_accessor :permanent_url
  end

  PERMANENT_REDIRECTS = [ Net::HTTPMovedPermanently, Net::HTTPPermanentRedirect ].freeze
  # 追うリダイレクトの上限。インフラの定数で報酬の数字ではないので dopamine.yml には置かない
  MAX_REDIRECTS = 3
  NETWORK_ERRORS = [ SocketError, SystemCallError, IOError, Timeout::Error, OpenSSL::SSL::SSLError, Net::ProtocolError, Zlib::Error, Resolv::ResolvError ].freeze
  SCHEMES = %w[http https].freeze
  # 外部リンクの転送先から、LAN やクラウドのメタデータへ到達させない。
  # IPv4 互換・ローカル NAT64・Teredo は内側の IPv4 を安全に検査できないため、帯ごと塞ぐ。
  INTERNAL_RANGES = %w[
    0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16 172.16.0.0/12 192.0.0.0/24 192.168.0.0/16
    198.18.0.0/15 224.0.0.0/4 240.0.0.0/4
    ::/96 64:ff9b:1::/48 2001::/32 fc00::/7 fe80::/10 ff00::/8
  ].map { |cidr| IPAddr.new(cidr) }.freeze
  # IPv6 の帯だけでは 2002:7f00:1:: のように埋め込まれた 127.0.0.1 を見落とす。
  EMBEDDED_IPV4 = { IPAddr.new("64:ff9b::/96") => 0, IPAddr.new("2002::/16") => 80 }.freeze
  USER_AGENT = "Dopafeed (+https://github.com/philosophynote/dopafeed)".freeze

  def self.call(url, headers: {}, content_types: nil)
    fold_errors { new(headers, content_types).get(URI(url)) }
  end

  # 接続を呼ぶ側に任せるため、検査後の再解決による DNS rebinding までは防げない。
  def self.verify_external!(url)
    fold_errors { new({}).check!(URI(url)) }
    nil
  end

  def self.internal_address?(address)
    address = embedded_ipv4(address) || address
    INTERNAL_RANGES.any? { |range| range.include?(address) }
  end

  def self.embedded_ipv4(address)
    return address.native if address.ipv4_mapped?

    EMBEDDED_IPV4.each do |range, shift|
      return IPAddr.new((address.to_i >> shift) & IPAddr::IN4MASK, Socket::AF_INET) if range.include?(address)
    end
    nil
  end
  private_class_method :embedded_ipv4

  def self.fold_errors
    yield
  rescue URI::Error => e
    raise Error, "接続エラー (#{e.class.name})"
  rescue *NETWORK_ERRORS => e
    raise TransientError, "接続エラー (#{e.class.name})"
  end
  private_class_method :fold_errors

  def initialize(headers, content_types = nil)
    # Accept-Encoding を呼ぶ側が決めると net-http は展開をやめ、本文の上限が圧縮後の大きさで数えられる（展開すると上限を超えて膨らむ）
    raise ArgumentError, "Accept-Encoding は HttpGet が決める" if headers.keys.any? { |key| key.to_s.casecmp?("Accept-Encoding") }

    @headers = { "User-Agent" => USER_AGENT }.merge(headers)
    @content_types = content_types
    @permanent_url = nil
    @permanent_chain = true
  end

  def get(uri, redirects = 0)
    # 検査した IP にそのまま繋ぐ（ipaddr:）。Net::HTTP に名前を引き直させると、検査の後で内部アドレスに変わる
    # DNS rebinding が通る。TLS の証明書検証と SNI はホスト名のまま。プロキシは第 3 引数の nil で切る（既定の :ENV だと
    # http_proxy 環境変数のプロキシに名前を引かせ、ipaddr: が効かない）
    response = Net::HTTP.start(uri.hostname, uri.port, nil, ipaddr: check!(uri), use_ssl: uri.scheme == "https", open_timeout: timeout, read_timeout: timeout) do |http|
      http.request(Net::HTTP::Get.new(uri, @headers)) do |res|
        raise UnexpectedContentType, res.content_type.to_s if res.is_a?(Net::HTTPSuccess) && unexpected_content_type?(res)
        raise Error, too_large if res.content_length.to_i > max_body_bytes

        res.read_body(BoundedBody.new(max_body_bytes, too_large))
      end
    end

    case response
    when Net::HTTPSuccess, Net::HTTPNotModified
      response.extend(Moved).tap do |res|
        res.permanent_url = @permanent_url
        res.final_url = uri.dup.tap { |location| location.fragment = nil }.normalize.to_s
      end
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

  # Net::HTTP に別アドレスへのフォールバックを任せると、名前を引き直される。
  def resolve(host)
    addresses = addresses_of(host)
    raise Resolv::ResolvError, "名前が引けません (#{host})" if addresses.empty?
    raise Error, "内部ネットワークの URL です" if addresses.any? { |address| self.class.internal_address?(address) }

    addresses.first.to_s
  end

  def addresses_of(host)
    [ IPAddr.new(host) ]
  rescue IPAddr::InvalidAddressError
    # 既定の Resolv は死んだリゾルバ相手に 5・10・20・40 秒と粘り、それを A と AAAA、検索ドメインの候補ごとに
    # 繰り返す。問い合わせ 1 回ずつではなく名前解決の全体を fetch.timeout_seconds で切る
    Timeout.timeout(timeout, Resolv::ResolvTimeout) { Resolv.getaddresses(host) }.map { |address| IPAddr.new(address) }
  end

  def timeout
    Dopamine.settings.dig(:fetch, :timeout_seconds)
  end

  def max_body_bytes
    Dopamine.settings.dig(:fetch, :max_body_megabytes) * 1024 * 1024
  end

  def too_large
    "応答が大きすぎます (#{Dopamine.settings.dig(:fetch, :max_body_megabytes)} MB 超)"
  end

  def unexpected_content_type?(response)
    @content_types.present? && !@content_types.include?(response.content_type.to_s.downcase)
  end
end
