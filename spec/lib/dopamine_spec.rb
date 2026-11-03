RSpec.describe Dopamine do
  it "settings は config/dopamine.yml をそのまま返す" do
    expect(described_class.settings).to eq(Rails.application.config_for(:dopamine))
  end

  it "tier_names は xp.tiers の name を順に返す" do
    expected = Rails.application.config_for(:dopamine).dig(:xp, :tiers).map { |tier| tier[:name] }
    expect(described_class.tier_names).to eq(expected)
    expect(described_class.tier_names).not_to be_empty
  end

  it "tier(name) は名前で引いた tier、無ければ nil" do
    name = described_class.tier_names.first
    expect(described_class.tier(name)[:name]).to eq(name)
    expect(described_class.tier("legendary")).to be_nil
  end

  it "jackpot_tier は倍率が最も高い tier（名前ではなく倍率で決める）" do
    tiers = Rails.application.config_for(:dopamine).dig(:xp, :tiers)
    expect(described_class.jackpot_tier).to eq(tiers.max_by { |tier| tier[:multiplier] })
    expect(described_class.jackpot_tier[:multiplier]).to be > tiers.first[:multiplier]
  end
end
