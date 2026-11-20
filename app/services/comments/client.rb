module Comments
  # 要約の Claude::Client と同じく、gem の再試行は切り、待ち時間は設定から必ず取り、鍵は呼ぶたびの context にだけ入れる。
  # 思考込みで 8 人分を書くので、要約の claude.timeout_seconds とは別の待ち時間を使う。
  module Client
    PROVIDER = :xai

    def self.build
      api_key = ENV.fetch("XAI_API_KEY")
      timeout = Dopamine.settings.fetch(:comments).fetch(:timeout_seconds)
      RubyLLM.context do |config|
        config.xai_api_key = api_key
        config.request_timeout = timeout
        config.max_retries = 0
      end
    end
  end
end
