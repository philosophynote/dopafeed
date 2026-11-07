# 記事ページの HTML から、カードに添える画像（og:image、無ければ twitter:image）の URL を 1 つ選ぶ。
# HTTP は話さない（取るのは {ArticleContentFetcher} が既に取った HTML）。画像そのものも取りに行かず、
# 端末が配信元から直に読む前提なので、https の URL だけ返す（http は https のページで混在コンテンツになり、
# data: や javascript: は img の src に置かない）
class OgImage
  # 探す meta。先にあるものを優先する
  SELECTORS = [
    'meta[property="og:image"]',
    'meta[name="twitter:image"]',
    'meta[property="twitter:image"]'
  ].freeze

  # @param html [String] UTF-8 の HTML
  # @param base [URI, String] 相対 URL を解く基準。リダイレクトを追った後の URL
  # @return [String, nil] https の絶対 URL。無い・壊れている・https でなければ nil
  def self.from(html, base)
    document = Nokogiri::HTML(html)
    content = SELECTORS.lazy.filter_map { |selector| document.at_css(selector)&.[]("content")&.strip.presence }.first
    return if content.nil?

    uri = URI.join(base.to_s, content)
    uri.to_s if uri.scheme == "https" && uri.host.present?
  rescue URI::Error
    nil
  end
end
