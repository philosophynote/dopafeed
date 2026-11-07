module Claude
  # Anthropic SDK のクライアントを作る唯一の場所。API キーは ENV（ADR 0002、.claude/skills/claude-api）。
  # ここ以外で Anthropic:: を触らないことは spec/structure/conventions_spec.rb が守る。
  #
  # SDK の再試行は切り、やり直しは Job の retry_on だけに持たせる。両方で再試行すると回数が掛け算になり、
  # {Budget} の台帳（呼ぶ前に 1 行）と実際の HTTP 要求の数がずれる。SDK の待ち（最大 8 秒）の間もスレッドを持ち続ける。
  # 0 は調整のつまみではなく役割分担なので dopamine.yml には置かない。
  #
  # 待ちの上限は SDK 既定の 600 秒では長すぎる。Solid Queue のスレッドは RSS の取得とも共有で、
  # 応答の来ない呼び出しが 1 本あるだけで他の Job が詰まる。limits_concurrency の期間（既定 3 分）より短くないと、
  # 同じ記事の 2 本目が走る窓も開く。鍵が無いときに黙って 600 秒へ戻らないよう fetch で止める
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
