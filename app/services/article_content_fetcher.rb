# 記事ページを取りに行き、readability で本文を抜いて articles.content を置き換える。
# フィードの entry 本文は Zenn なら抜粋、Hacker News ならほぼ空なので、要約の入力には記事ページの本文が要る。
# 抜いた本文がフィードの本文より短ければ置き換えない（Zenn の長い抜粋を Cookie バナーで潰さない）。
# 失敗（HTTP 4xx・HTML 以外・本文なし・文字コード不明）は例外にせず content_error に日本語で残し、content はフィードの本文のまま。
# {HttpGet::TransientError} は握らずそのまま上げる（やり直すかどうかは Job が決める）。
# content_fetched_at は失敗でも入れる（Job の冪等の鍵。やり直すなら nil に戻す）。
# 文字コードは GuessHtmlEncoding で自前で推定して UTF-8 に直す（ruby-readability の推定は RUBY_VERSION 1.9〜3 でしか動かず、本番の Ruby 4 では素通りする）。
# 同じ HTML から {OgImage} で画像の URL を拾い image_url に残す。本文が抜けなくても（kept・抽出失敗）残し、
# HTML まで届かなかった失敗では前の値に触らない。
# 想定外の例外（バグ）はそのまま上げ、Solid Queue の失敗に残す
class ArticleContentFetcher
  # 取得の結果
  # @!attribute status [r]
  #   @return [Symbol] :fetched（content を置き換えた）/ :kept（抜けたがフィードの本文より短いので残した）/ :failed（content_error に残した）
  # @!attribute error [r]
  #   @return [String, nil] 失敗の文言（articles.content_error と同じ）
  Result = Data.define(:status, :error)

  # 記録して終わりにする失敗（本文なし、文字コード不明）
  class ExtractError < StandardError; end

  # 本文を抜く対象の Content-Type。PDF や画像は本文を読まずに閉じる
  HTML_TYPES = %w[text/html application/xhtml+xml].freeze
  # readability が残すタグと属性。既定（div と p だけ）だと見出し・コード・リンク・画像がテキストに潰れる
  TAGS = %w[div p pre code h1 h2 h3 h4 ul ol li blockquote a img table thead tbody tr th td].freeze
  ATTRIBUTES = %w[href src].freeze

  def initialize(article)
    @article = article
    @image = {}
  end

  # 取得して content を置き換え、articles の取得状態を更新する
  def call
    response = HttpGet.call(article.url, headers: { "Accept" => "text/html, application/xhtml+xml" }, content_types: HTML_TYPES)
    html = utf8(response.body.to_s, response["Content-Type"])
    # 相対の画像 URL は、リダイレクトを追った後の URL で解く
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

  # 失敗を記録する。content はフィードの本文のまま
  #
  # @return [Result] :failed
  def record_failure(message)
    article.update!(content_fetched_at: Time.current, content_error: message, **image)
    Result.new(status: :failed, error: message)
  end

  private

  attr_reader :article, :image

  # @param body [String] 応答本文（バイト列）
  # @param content_type [String, nil] Content-Type ヘッダ（charset の手がかり）
  # @return [String] UTF-8 の HTML。宣言された文字コードで読めないバイトは置換文字にする
  # @raise [ExtractError] charset がヘッダにも meta にも無く、UTF-8 としても読めない
  def utf8(body, content_type)
    encoding = GuessHtmlEncoding.guess(body, "Content-Type: #{content_type}")
    if encoding.nil? || !GuessHtmlEncoding.encoding_loaded?(encoding)
      html = body.dup.force_encoding(Encoding::UTF_8)
      raise ExtractError, "文字コードを判定できません" unless html.valid_encoding?

      return html
    end

    body.dup.force_encoding(encoding).encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
  end

  # @param html [String] UTF-8 の HTML
  # @return [String] readability が本文と判定した部分の HTML（TAGS / ATTRIBUTES だけ残る）
  # @raise [ExtractError] 本文の文字数が readability の最小段落長（min_text_length）に満たない（JS 描画のページ、空のページ）
  def extract(html)
    content = Readability::Document.new(html, encoding: Encoding::UTF_8.name, do_not_guess_encoding: true, tags: TAGS, attributes: ATTRIBUTES).content
    raise ExtractError, "本文を抽出できません" if text_of(content).length < Readability::Document::DEFAULT_OPTIONS[:min_text_length]

    content
  end

  # @return [String] タグを除いた文字列（& などは実体参照に戻さない）
  def text_of(html)
    Loofah.fragment(html).text(encode_special_chars: false).strip
  end

  # @return [Result] :kept。試行時刻だけ記録し content は残す
  def kept
    article.update!(content_fetched_at: Time.current, content_error: nil, **image)
    Result.new(status: :kept, error: nil)
  end
end
