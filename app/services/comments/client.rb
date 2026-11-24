module Comments
  # 呼び先が xAI で、流れの途中の待ちも数えるので、要約の claude.timeout_seconds とは別の待ち時間を使う。
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
