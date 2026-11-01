RSpec.describe Dopamine do
  it "settings は config/dopamine.yml をそのまま返す" do
    expect(described_class.settings).to eq(Rails.application.config_for(:dopamine))
  end

  it "tier_names は xp.tiers の name を順に返す" do
    expected = Rails.application.config_for(:dopamine).dig(:xp, :tiers).map { |tier| tier[:name] }
    expect(described_class.tier_names).to eq(expected)
    expect(described_class.tier_names).not_to be_empty
  end
end
