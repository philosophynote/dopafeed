# 記事を開いたときの抽選。確率は dopamine.yml の cards.rarities、結果は希少度の名前だけ
RSpec.describe RarityDraw do
  let(:rarities) { Dopamine.rarities }

  it "返すのは希少度の名前" do
    random = Random.new(1)
    100.times { expect(Dopamine.rarity_names).to include(described_class.draw(random: random)) }
  end

  it "seed 固定の Random で 10,000 回引くと各段の比率が probability ± 2 ポイントに収まる" do
    random = Random.new(20261103)
    trials = 10_000
    counts = Hash.new(0)
    trials.times { counts[described_class.draw(random: random)] += 1 }

    rarities.each do |rarity|
      ratio = counts[rarity[:name]].fdiv(trials)
      expect(ratio).to be_within(0.02).of(rarity[:probability]), "#{rarity[:name]}: #{ratio}"
    end
  end

  it "確率の合計は 1.0（yml の前提）" do
    expect(rarities.sum { |rarity| rarity[:probability] }).to be_within(0.0001).of(1.0)
  end

  it "段に数値の倍率を持たない（ADR 0020）" do
    expect(rarities.flat_map(&:keys).uniq).not_to include(:multiplier)
  end

  it "浮動小数の丸めで目が累積の合計を超えても、頂点の段に収める（外れ無し）" do
    random = instance_double(Random, rand: 1.0)
    expect(described_class.draw(random: random)).to eq(Dopamine.top_rarity[:name])
  end
end
