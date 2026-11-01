# 記事ページを取りに行き、readability で本文を抜いて articles.content を置き換える（Unit 3b）。{FetchArticleContentJob} からだけ呼ぶ。
# フィードの entry 本文は Zenn なら抜粋、Hacker News ならほぼ空なので、要約（Unit 4）の入力には記事ページの本文が要る。
# 失敗（HTTP・接続・HTML 以外・本文なし）は例外にせず content_error に日本語で残し、content はフィードの本文のまま。
# content_fetched_at は成功・失敗を問わず試行時刻（Job の冪等の鍵。やり直すなら nil に戻す）。
# 文字コードは GuessHtmlEncoding で自前で推定して UTF-8 に直す（ruby-readability の推定は RUBY_VERSION 1.9〜3 でしか動かず、本番の Ruby 4 では素通りする）。
# 想定外の例外（バグ）はそのまま上げ、Solid Queue の失敗に残す
class ArticleContentFetcher
  # 取得の結果
  # @!attribute status [r]
  #   @return [Symbol] :fetched（content を置き換えた）/ :failed（content_error に残した）
  # @!attribute error [r]
  #   @return [String, nil] 失敗の文言（articles.content_error と同じ）
  Result = Data.define(:status, :error)

  # 記録して終わりにする失敗（HTML 以外、本文なし）
  class ExtractError < StandardError; end

  # 本文を抜く対象の Content-Type。PDF や画像は取らない
  HTML_TYPES = %w[text/html application/xhtml+xml].freeze

  # @param article [Article] 本文を取りに行く記事
  def initialize(article)
    @article = article
  end

  # 取得して content を置き換え、articles の取得状態を更新する
  #
  # @return [Result]
  def call
    response = HttpGet.call(article.url)
    raise ExtractError, "HTML ではありません (#{response.content_type.presence || "不明"})" unless HTML_TYPES.include?(response.content_type)

    content = extract(utf8(response.body.to_s, response["Content-Type"]))
    article.update!(content: content, content_fetched_at: Time.current, content_error: nil)
    Result.new(status: :fetched, error: nil)
  rescue HttpGet::Error, ExtractError => e
    article.update!(content_fetched_at: Time.current, content_error: e.message)
    Result.new(status: :failed, error: e.message)
  end

  private

  attr_reader :article

  # @param body [String] 応答本文（バイト列）
  # @param content_type [String, nil] Content-Type ヘッダ（charset の手がかり）
  # @return [String] UTF-8 の HTML。直せないバイトは置換文字にする
  def utf8(body, content_type)
    GuessHtmlEncoding.encode(body, "Content-Type: #{content_type}").encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
  end

  # @param html [String] UTF-8 の HTML
  # @return [String] readability が本文と判定した部分の HTML
  # @raise [ExtractError] 本文の文字数が readability の最小段落長（min_text_length）に満たない（JS 描画のページ、空のページ）
  def extract(html)
    content = Readability::Document.new(html, encoding: Encoding::UTF_8.name, do_not_guess_encoding: true).content
    raise ExtractError, "本文を抽出できません" if Loofah.fragment(content).text.strip.length < Readability::Document::DEFAULT_OPTIONS[:min_text_length]

    content
  end
end
