class FeedDocument
  class Error < StandardError; end

  # Feedjira だけでは途中で切れた XML も空のフィードとして通るため、先に閉じを確かめる。
  def self.parse(body)
    Nokogiri::XML(body, &:strict)
    Feedjira.parse(body)
  rescue Nokogiri::XML::SyntaxError, Feedjira::NoParserAvailable
    raise Error, "フィードを解析できません"
  end
end
