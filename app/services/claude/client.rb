module Claude
  # SDK と Job の両方で再試行すると回数が掛け算になるため、SDK 側は切る。
  # 既定の 600 秒では 1 本がスレッドを 10 分塞ぐため、設定が無くても既定値に戻さない。
  module Client
    def self.build
      Anthropic::Client.new(
        api_key: ENV.fetch("ANTHROPIC_API_KEY"),
        timeout: Dopamine.settings.fetch(:claude).fetch(:timeout_seconds),
        max_retries: 0
      )
    end
  end
end
