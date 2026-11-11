module Dopamine
  def self.settings
    Rails.application.config_for(:dopamine)
  end

  def self.rarities
    settings.dig(:cards, :rarities)
  end

  def self.rarity_names
    rarities.map { |rarity| rarity[:name] }
  end

  def self.rarity(name)
    rarities.find { |rarity| rarity[:name] == name }
  end

  def self.base_rarity
    rarities.first
  end

  # 名前で頂点を決めると綴りに縛られ、確率では同率の段が増えたときに揺れるため、並び順を使う。
  def self.top_rarity
    rarities.last
  end

  # 引用符の無い 07:30 は YAML が六十進数（27000 秒）として読むため、時刻表記に戻す。
  def self.clock_time(key)
    value = settings.dig(:push, key)
    case value
    when Integer then format("%02d:%02d", value / 3600, value % 3600 / 60)
    when String then value
    end
  end
end
