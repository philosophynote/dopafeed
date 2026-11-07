RSpec.describe Claude::Client do
  it "ANTHROPIC_API_KEY が無ければ KeyError で止まる（黙って空キーで呼ばない）" do
    with_env("ANTHROPIC_API_KEY" => nil) do
      expect { described_class.build }.to raise_error(KeyError)
    end
  end

  it "ANTHROPIC_API_KEY があれば SDK のクライアントを返す" do
    with_env("ANTHROPIC_API_KEY" => "test-key") do
      expect(described_class.build).to be_a(Anthropic::Client)
    end
  end
end
