# フィードの本文は抜粋や空の場合があるため、記事ページから取得する。
# 短い抽出結果で置き換えると、長い抜粋を Cookie バナーで潰すことがある。
# ruby-readability の文字コード推定は Ruby 4 で動かないため、GuessHtmlEncoding を使う。
class ArticleContentFetcher
  Result = Data.define(:status, :error)

  class ExtractError < StandardError; end

  HTML_TYPES = %w[text/html application/xhtml+xml].freeze
  # readability の既定（div と p だけ）では、見出し・コード・リンク・画像がテキストに潰れる。
  TAGS = %w[div p pre code h1 h2 h3 h4 ul ol li blockquote a img table thead tbody tr th td].freeze
  ATTRIBUTES = %w[href src].freeze

  def initialize(article)
    @article = article
    @image = {}
  end

  def call
    response = HttpGet.call(article.url, headers: { "Accept" => "text/html, application/xhtml+xml" }, content_types: HTML_TYPES)
    html = utf8(response.body.to_s, response["Content-Type"])
    # 移転元を基準にすると、相対画像 URL が別の場所を指してしまう。
    @image = { image_url: OgImage.from(html, response.uri || article.url) }
    content = extract(html)
    return kept if text_of(content).length < text_of(article.content.to_s).length

    article.update!(content: content, content_fetched_at: Time.current, content_error: nil, **image)
    Result.new(status: :fetched, error: nil)
  rescue HttpGet::TransientError
    raise
  rescue HttpGet::UnexpectedContentType => e
    record_failure("HTML ではありません (#{e.message.presence || "不明"})")
  rescue HttpGet::Error, ExtractError => e
    record_failure(e.message)
  end

  def record_failure(message)
    article.update!(content_fetched_at: Time.current, content_error: message, **image)
    Result.new(status: :failed, error: message)
  end

  private

  attr_reader :article, :image

  def utf8(body, content_type)
    encoding = GuessHtmlEncoding.guess(body, "Content-Type: #{content_type}")
    if encoding.nil? || !GuessHtmlEncoding.encoding_loaded?(encoding)
      html = body.dup.force_encoding(Encoding::UTF_8)
      raise ExtractError, "文字コードを判定できません" unless html.valid_encoding?

      return html
    end

    body.dup.force_encoding(encoding).encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
  end

  def extract(html)
    content = Readability::Document.new(html, encoding: Encoding::UTF_8.name, do_not_guess_encoding: true, tags: TAGS, attributes: ATTRIBUTES).content
    raise ExtractError, "本文を抽出できません" if text_of(content).length < Readability::Document::DEFAULT_OPTIONS[:min_text_length]

    content
  end

  def text_of(html)
    Loofah.fragment(html).text(encode_special_chars: false).strip
  end

  def kept
    article.update!(content_fetched_at: Time.current, content_error: nil, **image)
    Result.new(status: :kept, error: nil)
  end
end
