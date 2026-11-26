RSpec.describe Comments::Client do
  let(:comments) { { personas_shown: 3, model: "grok-4.3", max_tokens: 4000, timeout_seconds: 60, stream_interval_ms: 250 } }

  before { allow(Dopamine).to receive(:settings).and_return(Dopamine.settings.merge(comments: comments)) }

  it "XAI_API_KEY が無ければ KeyError で止まる（黙って空キーで呼ばない）" do
    with_env("XAI_API_KEY" => nil) do
      expect { described_class.build }.to raise_error(KeyError)
    end
  end

  it "XAI_API_KEY を持つ RubyLLM の context を返し、鍵は RubyLLM の全体の設定に残さない" do
    with_env("XAI_API_KEY" => "test-key") do
      context = described_class.build

      expect(context).to be_a(RubyLLM::Context)
      expect(context.config.xai_api_key).to eq("test-key")
    end
    expect(RubyLLM.config.xai_api_key).not_to eq("test-key")
  end

  describe "HTTP の待ちと再試行" do
    around { |example| with_env("XAI_API_KEY" => "test-key") { example.run } }

    it "タイムアウトは comments.timeout_seconds で、gem は再試行しない（やり直しは Job だけが持つ）" do
      config = described_class.build.config

      expect(config.request_timeout).to eq(60)
      expect(config.max_retries).to eq(0)
    end

    it "yml の comments.timeout_seconds は同じ行のコメント Job の重なり止めの期間より短い（長いと期間が切れて 2 本目が払う）" do
      timeout = Rails.application.config_for(:dopamine).dig(:comments, :timeout_seconds)
      skip "config/dopamine.yml に comments.timeout_seconds がまだ無い" if timeout.nil?

      expect(timeout.seconds).to be < Comments::CommentPersonaJob.concurrency_duration
    end

    it "comments.timeout_seconds が無ければ KeyError で止まる（黙って gem の既定の 300 秒に落ちない）" do
      comments.delete(:timeout_seconds)

      expect { described_class.build }.to raise_error(KeyError, /timeout_seconds/)
    end
  end
end
