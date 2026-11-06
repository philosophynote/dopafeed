# 「読む」のタップ時の抽選。確率は dopamine.yml の xp.tiers、結果は tier の名前だけ
RSpec.describe XpRoulette do
  let(:tiers) { Dopamine.settings.dig(:xp, :tiers) }

  it "返すのは tier の名前" do
    random = Random.new(1)
    100.times { expect(Dopamine.tier_names).to include(described_class.draw(random: random)) }
  end

  it "seed 固定の Random で 10,000 回引くと各 tier の比率が probability ± 2 ポイントに収まる" do
    random = Random.new(20261103)
    trials = 10_000
    counts = Hash.new(0)
    trials.times { counts[described_class.draw(random: random)] += 1 }

    tiers.each do |tier|
      ratio = counts[tier[:name]].fdiv(trials)
      expect(ratio).to be_within(0.02).of(tier[:probability]), "#{tier[:name]}: #{ratio}"
    end
  end

  it "確率の合計は 1.0（yml の前提）" do
    expect(tiers.sum { |tier| tier[:probability] }).to be_within(0.0001).of(1.0)
  end
end
