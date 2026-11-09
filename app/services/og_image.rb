require "ipaddr"

# 画像は端末が直に読むため、記事の書き手に端末の LAN へ GET を打たせない URL に絞る。
class OgImage
  SELECTORS = [
    'meta[property="og:image:secure_url"]',
    'meta[property="og:image"]',
    'meta[name="twitter:image"]',
    'meta[property="twitter:image"]'
  ].freeze

  def self.from(html, base)
    # meta は head にある。本文まで Nokogiri に通すと大きなページで重い（本文は readability がもう一度読む）
    document = Nokogiri::HTML(html[%r{\A.*?</head>}mi] || html)
    SELECTORS.lazy.flat_map { |selector| document.css(selector).to_a }.filter_map { |meta| usable(meta["content"], base) }.first
  end

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

  DNS_NAME = /\A[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)*\z/
  NUMERIC_LABEL = /\A(?:0x\h*|\d+)\z/

  # 名前は引かない（引くのは端末で、ここで引いても端末の答えとは限らない）。名前だけで内側と分かるものを捨てる。
  # 弾く書き方を数え上げず、許す形を絞る: ブラウザは 2130706433・0x7f000001・127.1・127%2e0%2e0%2e1 なども
  # 解いて 127.0.0.1 に直すので、IPAddr が読める正規の IP か、普通のホスト名の形のどちらかだけ通す
  def self.internal_host?(host)
    host = host.downcase.delete_suffix(".")
    return true if host == "localhost" || host.end_with?(".localhost")

    address = ip_address(host)
    return HttpGet.internal_address?(address) if address

    !host.match?(DNS_NAME) || host.split(".").last.match?(NUMERIC_LABEL)
  end
  private_class_method :internal_host?

  def self.ip_address(host)
    IPAddr.new(host)
  rescue IPAddr::InvalidAddressError
    nil
  end
  private_class_method :ip_address
end
