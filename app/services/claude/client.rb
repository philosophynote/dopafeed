module Claude
  # Anthropic SDK のクライアントを作る唯一の場所。API キーは ENV（ADR 0002、.claude/skills/claude-api）。
  # ここ以外で Anthropic:: を触らないことは spec/structure/conventions_spec.rb が守る。
  module Client
    def self.build
      Anthropic::Client.new(api_key: ENV.fetch("ANTHROPIC_API_KEY"))
    end
  end
end
