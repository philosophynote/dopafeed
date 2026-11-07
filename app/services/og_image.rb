require "ipaddr"

# 記事ページの HTML の meta から、記事を表す画像（og:image など）の URL を 1 つ選ぶ。HTTP は話さない。
# 画像はサーバーが取りに行かず端末が配信元から直に読むので、端末に読ませてよい URL だけ返す:
# https だけ（http は https のページで混在コンテンツになり、data: や javascript: は img の src に置かない）、
# 内部ネットワークを直に指す URL（IP・localhost）と userinfo 付きの URL は捨てる（記事の書き手に端末から LAN へ GET を打たせない）。
# 候補を順に試し、使えない候補は飛ばして次へ落ちる（http の og:image に https の twitter:image を添えるページや、
# og:image を複数並べるページがある）
class OgImage
  # 探す meta。先にあるものを優先する
  SELECTORS = [
    'meta[property="og:image:secure_url"]',
    'meta[property="og:image"]',
    'meta[name="twitter:image"]',
    'meta[property="twitter:image"]'
  ].freeze

  # @param html [String] UTF-8 の HTML
  # @param base [URI, String] 相対 URL を解く基準
  # @return [String, nil] 使える最初の候補の絶対 URL。どれも使えなければ nil
  def self.from(html, base)
    # meta は head にある。本文まで Nokogiri に通すと大きなページで重い（本文は readability がもう一度読む）
    document = Nokogiri::HTML(html[%r{\A.*?</head>}mi] || html)
    SELECTORS.lazy.flat_map { |selector| document.css(selector).to_a }.filter_map { |meta| usable(meta["content"], base) }.first
  end

  # @return [String, nil] 端末に読ませてよい絶対 URL。だめなら nil
  def self.usable(content, base)
    return if content.blank?

    uri = URI.join(base.to_s, content.strip)
    return unless uri.scheme == "https" && uri.host.present? && uri.userinfo.nil?
    return if internal_host?(uri.hostname)

    uri.to_s
  rescue URI::Error
    nil
  end
  private_class_method :usable

  # ホスト名として許す形。ASCII の英数字とハイフンのラベルを点で繋いだものだけ（IDN は punycode で来る）
  DNS_NAME = /\A[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)*\z/
  # ブラウザ（WHATWG URL）が IPv4 として読む最後のラベル（10 進・0x の 16 進）
  NUMERIC_LABEL = /\A(?:0x\h*|\d+)\z/

  # 名前は引かない（引くのは端末で、ここで引いても端末の答えとは限らない）。名前だけで内側と分かるものを捨てる。
  # 弾く書き方を数え上げず、許す形を絞る: ブラウザは 2130706433・0x7f000001・127.1・127%2e0%2e0%2e1 なども
  # 解いて 127.0.0.1 に直すので、IPAddr が読める正規の IP か、普通のホスト名の形のどちらかだけ通す
  def self.internal_host?(host)
    host = host.downcase.delete_suffix(".")
    return true if host == "localhost" || host.end_with?(".localhost")

    address = ip_address(host)
    return HttpGet::INTERNAL_RANGES.any? { |range| range.include?(address) } if address

    !host.match?(DNS_NAME) || host.split(".").last.match?(NUMERIC_LABEL)
  end
  private_class_method :internal_host?

  # @return [IPAddr, nil] 正規の IP の書き方なら IPAddr（IPv4-mapped IPv6 は中の IPv4）。でなければ nil
  def self.ip_address(host)
    address = IPAddr.new(host)
    address.ipv4_mapped? ? address.native : address
  rescue IPAddr::InvalidAddressError
    nil
  end
  private_class_method :ip_address
end
