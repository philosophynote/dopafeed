# 本番のコンテナに届く環境変数は config/deploy.yml の env にあるものだけ。
# アプリが読む鍵を足したのに deploy.yml へ足し忘れると、テストは緑のまま本番でだけ KeyError か機能停止になる。
RSpec.describe "config/deploy.yml の env" do
  let(:deploy) { YAML.load_file(Rails.root.join("config/deploy.yml")) }
  let(:declared) { Array(deploy.dig("env", "secret")) + deploy.dig("env", "clear").to_h.keys }

  it "app/ と lib/ が読む環境変数を全部渡している" do
    read = Dir[Rails.root.join("{app,lib}/**/*.rb")].flat_map do |f|
      File.read(f).scan(/ENV(?:\.fetch\(|\[)\s*["']([A-Z0-9_]+)["']/).flatten
    end.uniq

    missing = read - declared
    expect(missing).to be_empty,
      "config/deploy.yml の env.secret（秘密）か env.clear（平文）に足せ。秘密なら .kamal/secrets にも 1 行要る（docs/runbook.md §0）: #{missing.join(", ")}"
  end
end
