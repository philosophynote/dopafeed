# 記事を開いたときの抽選。cards.rarities の probability に従って希少度の名前を 1 つ返す。
# 保存するのは名前だけで、確率は常に yml から（ADR 0006）
module RarityDraw
  # @param random [Random] テストで seed を固定するために差し替えられる
  def self.draw(random: Random.new)
    rarities = Dopamine.rarities
    roll = random.rand
    cumulative = 0.0
    rarities.each do |rarity|
      cumulative += rarity[:probability]
      return rarity[:name] if roll < cumulative
    end
    # 確率の合計が丸めで 1.0 に届かないときの受け皿
    rarities.last[:name]
  end
end
