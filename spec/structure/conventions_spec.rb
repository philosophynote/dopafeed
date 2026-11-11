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

  it "確率・秒数・本数の数字は config/dopamine.yml にだけ置く（app/ と lib/）" do
    pattern = /\b(probability|multiplier|reveal_duration|complete_after|daily_goal)\w*\s*[=:]\s*\d/i
    offenders = Dir[Rails.root.join("{app,lib}/**/*.rb")].select { |f| File.read(f).match?(pattern) }
    expect(offenders).to be_empty, "数字を config/dopamine.yml に移し、Rails.application.config_for(:dopamine) で読め:\n#{offenders.join("\n")}"
  end

  it "React や外部 JS フレームワークを持ち込まない" do
    offenders = Dir[Rails.root.join("app/javascript/**/*.js")].select { |f| File.read(f).match?(/from ["'](react|vue|svelte|preact)/) }
    expect(offenders).to be_empty, "Hotwire（Turbo + Stimulus）だけを使え:\n#{offenders.join("\n")}"
  end

  it "app/ と lib/ のコメントに工程・画面の語を書かない（ADR 0009）" do
    # 「ADR 0002」「1 回」「#{...}」「URL の /#top」は通す。行頭が # のコメントだけ見る（行末コメントと =begin は見ない）
    process = /\bUnit(?:\s*\d|\b)|陣|\bPR\b|\bIssue\b|(?<![\w\/])#\d/i
    screen = /画面/
    offenders = Dir[Rails.root.join("{app,lib}/**/*.rb")].flat_map do |f|
      path = f.delete_prefix("#{Rails.root}/")
      forbidden = path.match?(%r{\A(app/(models|services|jobs)|lib)/}) ? Regexp.union(process, screen) : process
      File.foreach(f).with_index(1).filter_map do |line, no|
        "#{path}:#{no}: #{line.strip}" if line.match?(/^\s*#/) && line.match?(forbidden)
      end
    end
    expect(offenders).to be_empty, "工程は Issue と PR に、画面名は app/views と docs/screens に書き、コメントには「なぜ」だけ残せ（ADR 0009）:\n#{offenders.join("\n")}"
  end

  it "FeedFetcher と ArticleContentFetcher は app/jobs/ からだけ new する" do
    offenders = Dir[Rails.root.join("{app,lib}/**/*.rb")].reject { |f| f.include?("/app/jobs/") }
                                                          .select { |f| File.read(f).match?(/\b(FeedFetcher|ArticleContentFetcher)\.new\b/) }
    expect(offenders).to be_empty, "取得のサービスは Job から呼べ（失敗の記録と再試行は Job が持つ）。直接 new しているのは:\n#{offenders.join("\n")}"
  end
end
