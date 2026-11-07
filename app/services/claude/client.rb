module Claude
  # Anthropic SDK のクライアントを作る唯一の場所。API キーは ENV（ADR 0002、.claude/skills/claude-api）。
  # ここ以外で Anthropic:: を触らないことは spec/structure/conventions_spec.rb が守る。
  #
  # SDK の再試行は切り、やり直しは Job の retry_on だけに持たせる。両方で持つと回数が掛け算になる。
  # 0 は調整のつまみではなく役割分担なので dopamine.yml には置かない。
  # 待ちの上限を SDK 既定の 600 秒のままにすると、応答の来ない 1 本が Solid Queue のスレッドを 10 分塞ぐ。
  # 鍵が無いときに黙って 600 秒へ戻らないよう fetch で止める
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
