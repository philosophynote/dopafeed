module Claude
  # gem と Job の両方で再試行すると回数が掛け算になるため、gem 側は切る。
  # gem の既定の 300 秒では 1 本がスレッドを 5 分塞ぐため、設定が無くても既定値に戻さない。
  # 初期化子で RubyLLM 全体に鍵を入れると、鍵の無い箱では起動で落ちるか空の鍵のまま呼ぶので、呼ぶたびに context を作る。
  module Client
    PROVIDER = :anthropic

    def self.build
      api_key = ENV.fetch("ANTHROPIC_API_KEY")
      timeout = Dopamine.settings.fetch(:claude).fetch(:timeout_seconds)
      RubyLLM.context do |config|
        config.anthropic_api_key = api_key
        config.request_timeout = timeout
        config.max_retries = 0
      end
    end
  end
end
