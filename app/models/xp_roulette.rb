module XpRoulette
  def self.draw(random: Random.new)
    tiers = Dopamine.settings.dig(:xp, :tiers)
    roll = random.rand
    cumulative = 0.0
    tiers.each do |tier|
      cumulative += tier[:probability]
      return tier[:name] if roll < cumulative
    end
    # 確率の合計が丸めで 1.0 に届かないときの受け皿
    tiers.last[:name]
  end
end
