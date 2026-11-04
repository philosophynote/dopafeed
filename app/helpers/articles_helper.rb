# リーダーの本文の描画。本文は他人のサイトから取った HTML なので、取得時（{ArticleContentFetcher}）と同じ許可リストで描く直前に消毒し直す
module ArticlesHelper
  # リンクと画像に足す属性。消毒の許可リストに足すので、元の HTML に同じ属性があっても害は無い
  ADDED_ATTRIBUTES = %w[target rel loading].freeze

  # 相対 URL は記事の URL で解決する（このアプリのホストで解決されると画像もリンクも壊れる）。
  # リンクは別タブにして、リーダーの流れを捨てさせない。消毒は書き換えの後にかけ、書き換えで紛れ込んだものも落とす
  #
  # @return [ActiveSupport::SafeBuffer]
  def article_body(article)
    fragment = Nokogiri::HTML5.fragment(article.content.to_s)
    fragment.css("a[href]").each do |link|
      absolutize(link, "href", article.url)
      link["target"] = "_blank"
      link["rel"] = "noopener noreferrer"
    end
    fragment.css("img[src]").each do |image|
      absolutize(image, "src", article.url)
      image["loading"] = "lazy"
    end
    sanitize(fragment.to_html, tags: ArticleContentFetcher::TAGS, attributes: ArticleContentFetcher::ATTRIBUTES + ADDED_ATTRIBUTES)
  end

  private

  # 解決できない URL は属性ごと捨てる（壊れたリンクより、ただの文字の方がよい）
  def absolutize(node, attribute, base)
    node[attribute] = URI.join(base, node[attribute].strip).to_s
  rescue URI::Error, ArgumentError
    node.remove_attribute(attribute)
  end
end
