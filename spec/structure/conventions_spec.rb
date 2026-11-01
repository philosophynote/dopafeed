# AGENTS.md の規約を文章ではなくテストで守る。失敗文に直し方を書く。
RSpec.describe "AGENTS.md の規約" do
  let(:app) { Rails.root.join("app") }

  it "Claude API は app/services/claude/ の中からしか呼ばない" do
    offenders = Dir[app.join("**/*.rb")].reject { |f| f.include?("/services/claude/") }
                                        .select { |f| File.read(f).match?(/Anthropic::|ANTHROPIC_API_KEY/) }
    expect(offenders).to be_empty, "Claude API の呼び出しは app/services/claude/ に移し、Job から呼べ:\n#{offenders.join("\n")}"
  end

  it "Claude のサービスはコントローラ・モデルから直接呼ばない（Job 経由）" do
    offenders = Dir[app.join("{controllers,models}/**/*.rb")]
                  .select { |f| File.read(f).match?(/Claude::\w+\.(new|call|perform)\b/) }
    expect(offenders).to be_empty, "コントローラ・モデルから Claude:: を直接呼ぶな。app/jobs/ の Job に perform_later させよ:\n#{offenders.join("\n")}"
  end

  it "XP・確率・秒数の数字は config/dopamine.yml にだけ置く" do
    pattern = /\b(xp|probability|multiplier|complete_after|daily_goal)\w*\s*[=:]\s*\d/i
    offenders = Dir[app.join("**/*.rb")].select { |f| File.read(f).match?(pattern) }
    expect(offenders).to be_empty, "数字を config/dopamine.yml に移し、Rails.application.config_for(:dopamine) で読め:\n#{offenders.join("\n")}"
  end

  it "React や外部 JS フレームワークを持ち込まない" do
    offenders = Dir[Rails.root.join("app/javascript/**/*.js")].select { |f| File.read(f).match?(/from ["'](react|vue|svelte|preact)/) }
    expect(offenders).to be_empty, "Hotwire（Turbo + Stimulus）だけを使え:\n#{offenders.join("\n")}"
  end
end
