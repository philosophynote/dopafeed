RSpec.describe Dopamine do
  let(:yml) { Rails.application.config_for(:dopamine) }

  it "settings は config/dopamine.yml をそのまま返す" do
    expect(described_class.settings).to eq(yml)
  end

  it "rarities は cards.rarities をそのまま、rarity_names はその name を順に返す" do
    expect(described_class.rarities).to eq(yml.dig(:cards, :rarities))
    expect(described_class.rarity_names).to eq(yml.dig(:cards, :rarities).map { |rarity| rarity[:name] })
    expect(described_class.rarity_names).not_to be_empty
  end

  it "rarity(name) は名前で引いた段、無ければ nil" do
    name = described_class.rarity_names.first
    expect(described_class.rarity(name)[:name]).to eq(name)
    expect(described_class.rarity("legendary")).to be_nil
  end

  it "top_rarity は yml の最後の段（名前や確率ではなく並び順で決める）" do
    expect(described_class.top_rarity).to eq(yml.dig(:cards, :rarities).last)
    expect(described_class.top_rarity[:probability]).to be < yml.dig(:cards, :rarities).first[:probability]
  end

  it "XP の鍵は無い（ADR 0020）" do
    expect(yml).not_to have_key(:xp)
    expect(yml[:daily_goal]).not_to have_key(:bonus_xp)
  end
end
