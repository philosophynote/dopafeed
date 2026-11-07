# 登録前の検証と定期取得の解析を揃える。HTTP と記事の保存は扱わない。
class FeedDocument
  # 通信の失敗と分けて、登録と定期取得で解析不能を同じ型として扱う。
  class Error < StandardError; end

  # Feedjira だけでは途中で切れた XML も空のフィードとして通るため、先に閉じを確かめる。
  def self.parse(body)
    Nokogiri::XML(body, &:strict)
    Feedjira.parse(body)
  rescue Nokogiri::XML::SyntaxError, Feedjira::NoParserAvailable
    raise Error, "フィードを解析できません"
  end
end
