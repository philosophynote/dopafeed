require "ipaddr"

# 記事ページの HTML の meta から、記事を表す画像（og:image など）の URL を 1 つ選ぶ。HTTP は話さない。
# 画像はサーバーが取りに行かず端末が配信元から直に読むので、端末に読ませてよい URL だけ返す:
# https だけ（http は https のページで混在コンテンツになり、data: や javascript: は img の src に置かない）、
# 内部ネットワークの IP を直に書いた URL と userinfo 付きの URL は捨てる（記事の書き手に端末から LAN へ GET を打たせない）。
# 候補を順に試し、使えない候補は飛ばして次へ落ちる（http の og:image に https の twitter:image を添えるページがある）
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
    SELECTORS.lazy.filter_map { |selector| usable(document.at_css(selector)&.[]("content"), base) }.first
  end

  # @return [String, nil] 端末に読ませてよい絶対 URL。だめなら nil
  def self.usable(content, base)
    return if content.blank?

    uri = URI.join(base.to_s, content.strip)
    return unless uri.scheme == "https" && uri.host.present? && uri.userinfo.nil?
    return if internal_literal?(uri.hostname)

    uri.to_s
  rescue URI::Error
    nil
  end
  private_class_method :usable

  # 名前は引かない（引くのは端末で、ここで引いても端末の答えとは限らない）。IP を直に書いたものだけ見る
  def self.internal_literal?(host)
    address = IPAddr.new(host)
    address = address.native if address.ipv4_mapped?
    HttpGet::INTERNAL_RANGES.any? { |range| range.include?(address) }
  rescue IPAddr::InvalidAddressError
    false
  end
  private_class_method :internal_literal?
end
