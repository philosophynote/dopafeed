# Unit 0 の開始手順（nao が読む）

## 0. 手でやること（15 分）
1. mise を入れ、Ruby 4.0.7 を入れる: `curl https://mise.run | sh && mise use -g ruby@4.0.7`
2. `gem install rails -v 8.1.4`、`brew install lefthook gh jq`、Chrome があることを確認
3. GitHub に空のリポジトリ `dopafeed` を作る。Codex の GitHub App をそのリポジトリに入れる（`@codex review` 用）
4. Claude Code CLI と Codex CLI を入れ、両方ログイン

## 1. rails new（手で打つ。選択肢はこれだけ）
```sh
cd ~/develop/dopafeed                                  # 既に作ったディレクトリの中で
rails new . --database=sqlite3 --css=tailwind          # "." で現在のディレクトリに生成。既存ファイルと衝突したら y/n を聞かれる（README は n で残す）
cp -R <このフォルダ unit0 の中身> .     # AGENTS.md, CLAUDE.md, .claude/, bin/hooks/, lefthook.yml, config/ci.rb, config/dopamine.yml, docs/, test/structure/, .github/pull_request_template.md
mkdir -p .agents && ln -s ../.claude/skills .agents/skills   # Codex 用 Skills（Codex の版で場所が違えば codex --help で確認）
git init && git add -A && git commit -m "rails new + harness skeleton"
git remote add origin git@github.com:philosophynote/dopafeed.git && git push -u origin main
```

## 2. Claude Code に渡す最初の命令（そのまま貼る）
```
Unit 0「縄張り」を仕上げよ。AGENTS.md と docs/plans/milestone-1.md を読んでから始めること。
まず Plan モードで計画を docs/plans/unit-0.md に書き、私の承認を待て。計画に含めるもの:
1. bin/rails generate authentication を実行し、User を seed で 1 件（ENV から email/password）
2. Gemfile に追加: feedjira, ruby-readability, anthropic, web-push, octokit, vcr, webmock, erb_lint, lefthook, bundler-audit（development/test の振り分けを正しく）
3. lefthook install。bin/hooks/rubocop-file が動くことを確認
4. config/ci.rb の各段が bin/ci で通るようにする（erb_lint の設定、bundler-audit の bin を用意）
5. test/structure/conventions_test.rb が緑で通る
6. test/application_system_test_case.rb を 390×844 の headless Chrome にし、スクショを tmp/screenshots/<test名>.png に保存するヘルパーを足す。bin/screens を書き、全システムテストを回して絵を集める
7. db/seeds.rb に 5 フィード・30 記事（要約つき・固定文）を入れる。bin/setup 一発で db:prepare と db:seed まで通す
8. app/services/claude/ と app/jobs/claude/ の空の骨と Claude::Budget（daily_call_limit を数える）を置き、単体テストを書く
9. .github/workflows/ci.yml が bin/ci と同じ段を回すよう整える
10. Litestream を ADR 0004 に従って Dockerfile と config/deploy.yml に組み込む（デプロイはしない）
11. docs/runbook.md に「復元」「ジョブ失敗の見方」を書く
完了の定義: bin/ci が緑、GitHub Actions が緑、PR を unit-0-harness ブランチで開く。
PR を開く前に reviewer サブエージェントに差分を見せよ。kamal deploy と config/dopamine.yml には触るな。
```

## 3. Unit 0 の後
- Claude Code on the web を一度試す: リポジトリを繋ぎ、起動スクリプトで `bin/setup` を呼ぶ。bin/ci が回れば並列用の第二戦場にする
- Unit 1（モック写経）へ: モック 22 枚は Claude Code からは見えない。Dopafeed プロジェクトのスレッドで「docs/screens/*.md を書け」と頼めば、こちらで Artifact を読んで書ける
