module Dopamine
  def self.settings
    Rails.application.config_for(:dopamine)
  end

  def self.tier_names
    settings.dig(:xp, :tiers).map { |tier| tier[:name] }
  end

  def self.tier(name)
    settings.dig(:xp, :tiers).find { |tier| tier[:name] == name }
  end

  # 引用符の無い 07:30 は YAML が六十進数（27000 秒）として読むため、時刻表記に戻す。
  def self.clock_time(key)
    value = settings.dig(:push, key)
    case value
    when Integer then format("%02d:%02d", value / 3600, value % 3600 / 60)
    when String then value
    end
  end

  # 名前で頂点を決めると、上に段を足したときに頂点がずれる。
  def self.jackpot_tier
    settings.dig(:xp, :tiers).max_by { |tier| tier[:multiplier] }
  end
end
