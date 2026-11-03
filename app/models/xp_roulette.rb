# 「読む」のタップ時の抽選。xp.tiers の probability に従って tier の名前を 1 つ返す。
# 倍率は返さない（保存するのは名前だけ、倍率は常に yml から。ADR 0006）
module XpRoulette
  # @param random [Random] テストで seed を固定するために差し替えられる
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
