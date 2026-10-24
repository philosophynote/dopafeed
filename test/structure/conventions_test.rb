# frozen_string_literal: true

# AGENTS.md の規約を文章ではなくテストで守る。失敗文に直し方を書く。
require "test_helper"

class ConventionsTest < ActiveSupport::TestCase
  APP = Rails.root.join("app")

  test "Claude API は app/services/claude/ の中からしか呼ばない" do
    offenders = Dir[APP.join("**/*.rb")].reject { |f| f.include?("/services/claude/") }
                                         .select { |f| File.read(f).match?(/Anthropic::|ANTHROPIC_API_KEY/) }
    assert_empty offenders, "Claude API の呼び出しは app/services/claude/ に移し、Job から呼べ:\n#{offenders.join("\n")}"
  end

  test "Claude のサービスはコントローラ・モデルから直接呼ばない（Job 経由）" do
    offenders = Dir[APP.join("{controllers,models}/**/*.rb")]
                  .select { |f| File.read(f).match?(/Claude::\w+\.(new|call|perform)\b/) }
    assert_empty offenders, "コントローラ・モデルから Claude:: を直接呼ぶな。app/jobs/ の Job に perform_later させよ:\n#{offenders.join("\n")}"
  end

  test "XP・確率・秒数の数字は config/dopamine.yml にだけ置く" do
    pattern = /\b(xp|probability|multiplier|complete_after|daily_goal)\w*\s*[=:]\s*\d/i
    offenders = Dir[APP.join("**/*.rb")].select { |f| File.read(f).match?(pattern) }
    assert_empty offenders, "数字を config/dopamine.yml に移し、Rails.application.config_for(:dopamine) で読め:\n#{offenders.join("\n")}"
  end

  test "React や外部 JS フレームワークを持ち込まない" do
    offenders = Dir[Rails.root.join("app/javascript/**/*.js")].select { |f| File.read(f).match?(/from ["'](react|vue|svelte|preact)/) }
    assert_empty offenders, "Hotwire（Turbo + Stimulus）だけを使え:\n#{offenders.join("\n")}"
  end
end
