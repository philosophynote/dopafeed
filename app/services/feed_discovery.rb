# 購読先の URL とタイトルを検証する。保存と取得予約は {FeedRegistration} に委ねる。
class FeedDiscovery
  Result = Data.define(:url, :title)
  # 候補を探し終えた失敗と、直接入力されたフィードの解析失敗を分ける。
  class Error < StandardError; end
  # HttpGet の接続エラーとして握られず、探索全体を抜けるための例外。
  class Expired < StandardError; end
  HTML_TYPES = %w[text/html application/xhtml+xml].freeze
  FEED_TYPES = %w[application/rss+xml application/atom+xml].freeze
  PATHS = %w[/feed /rss /atom.xml /index.xml].freeze
  # 大量のリンクがあるページでも同期の外部取得を増やさないための通信上限。
  MAX_HTML_CANDIDATES = 5

  def self.call(url, &registered)
    Timeout.timeout(Dopamine.settings.dig(:fetch, :timeout_seconds), Expired) { new(url, registered).call }
  rescue Expired
    raise Error, "フィードの確認がタイムアウトしました。RSS/Atom の URL を入力してください"
  end

  def initialize(url, registered)
    @url, @registered = url, registered
  end

  def call
    response = HttpGet.call(@url)
    Result.new(@url, title(response))
  rescue FeedDocument::Error
    raise unless HTML_TYPES.include?(response.content_type.to_s.downcase)

    discover(response)
  end

  private

  def title(response)
    FeedDocument.parse(response.body.to_s).title.to_s.strip.presence || raise(FeedDocument::Error, "フィードのタイトルを取得できません")
  end

  def discover(response)
    base = response.final_url
    seen = [ @url, base ]
    links = Nokogiri::HTML(response.body.to_s).css("head link").filter_map do |node|
      next unless node["rel"].to_s.downcase.split.include?("alternate") && FEED_TYPES.include?(node["type"].to_s.split(";").first.to_s.strip.downcase)

      resolve(base, node["href"])
    end.uniq.reject { |url| seen.include?(url) }.first(MAX_HTML_CANDIDATES)
    candidates = (links + PATHS.map { |path| resolve(base, path) }).uniq - seen
    transient = false
    candidates.each do |url|
      return Result.new(url, nil) if @registered&.call(url)

      begin
        return Result.new(url, title(HttpGet.call(url)))
      rescue HttpGet::TransientError
        transient = true
      rescue HttpGet::Error, FeedDocument::Error
        next
      end
    end
    raise Error, transient ? "フィードを確認できませんでした。時間をおいて試すか、RSS/Atom の URL を入力してください" : "フィードが見つかりません"
  end

  def resolve(base, href)
    return if href.blank?

    uri = URI.join(base, href.strip)
    uri.fragment = nil
    uri.normalize.to_s if HttpGet::SCHEMES.include?(uri.scheme) && uri.hostname.present?
  rescue URI::Error
    nil
  end
end
