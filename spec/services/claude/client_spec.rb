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

  describe "HTTP の待ちと再試行" do
    around { |example| with_env("ANTHROPIC_API_KEY" => "test-key") { example.run } }

    it "タイムアウトは claude.timeout_seconds" do
      expect(described_class.build.timeout).to eq(Dopamine.settings.dig(:claude, :timeout_seconds))
    end

    it "claude.timeout_seconds は同じ記事の要約 Job の重なり止めの期間より短い（長いと期間が切れて 2 本目が走る）" do
      expect(Dopamine.settings.dig(:claude, :timeout_seconds).seconds).to be < Claude::SummarizeArticleJob.concurrency_duration
    end

    it "SDK は再試行しない（やり直しは Job の retry_on だけが持つ）" do
      expect(described_class.build.max_retries).to eq(0)
    end

    it "claude.timeout_seconds が無ければ KeyError で止まる（黙って 600 秒に落ちない）" do
      settings = Dopamine.settings
      settings[:claude] = settings[:claude].except(:timeout_seconds)
      allow(Dopamine).to receive(:settings).and_return(settings)

      expect { described_class.build }.to raise_error(KeyError, /timeout_seconds/)
    end
  end
end
