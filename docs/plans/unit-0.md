# Unit 0「縄張り」実行計画

状態: **承認済み 2026-10-23（nao）**
ブランチ: `unit-0-harness`（1 PR。差分は 1,500 行前後だが、手書きロジックは Claude::Budget・seeds・スクショヘルパー・entrypoint だけ。残りは生成物・データ・設定。PR 本文に内訳を書く）

## Context
rails new 直後の骨組みに、以後の Unit が乗る「縄張り」を張る。狙いは 3 つ。
1. `bin/ci` と GitHub Actions が同じ段を回し、緑で始まること（以後の Unit の完了条件の土台）
2. 390×844 のシステムテストと `bin/screens` で、画面を触る Unit が絵を残せること
3. 認証・seed・Claude の骨・Litestream を置き、Unit 1〜7 が設計判断ではなく実装に集中できること

決定済み（nao）:
- feeds/articles の最小テーブルを Unit 0 で作る（seed を本物にするため。列の拡張は Unit 2）
- PR は 1 本
- Claude は Bedrock ではなく Claude API 直叩き（`ANTHROPIC_API_KEY`、ADR 0002 のまま。Bedrock にするなら `Anthropic::BedrockClient` + AWS 資格情報 + モデル ID 変更が要るので、その時は別 ADR）

## 現状（読んだ結果）
- Ruby 4.0.7 は mise 経由
- bundler-audit gem と `bin/bundler-audit`、`config/bundler-audit.yml` は既にある
- `bin/rails generate authentication` は User/Session/Current、Sessions/Passwords コントローラ、Authentication concern、`ApplicationController` への `include Authentication`、bcrypt、controller test 2 本、users.yml、`test/test_helpers/session_test_helper.rb` を生成する
- `config/ci.rb` の段: Setup → RuboCop → erb_lint → bundler-audit → importmap audit → Brakeman → 構造テスト → test → test:system → seed:replant

## 手順（この順で。テストは先に書いて赤を見る）

### 0. ブランチと計画
- `git checkout -b unit-0-harness`、この文書を置く

### 1. Gemfile
- 本体: `feedjira`, `ruby-readability`, `anthropic`, `web-push`, `octokit`
- `group :development`: `erb_lint`, `lefthook`（`require: false`）
- `group :test`: `vcr`, `webmock`
- `bundler-audit` は既に `development, test` にある

### 2. 認証（ADR 0005）
- `bin/rails generate authentication`、migration 実行、生成テストを緑に
- `include Authentication` で全画面が要ログイン。`/up` は対象外。意図どおり（一人用）

### 3. 最小ドメイン（seed のため）
- `feeds`(title, url:uniq, site_url) / `articles`(feed:references, title, url:uniq, summary:text, published_at:datetime)
- presence/uniqueness のみ。XP・既読・fetch 状態は Unit 2

### 4. db/seeds.rb と bin/setup
- 冪等（url キーで `find_or_create_by!`）。`db:seed:replant` でも通る
- User 1 件: `DOPAFEED_USER_EMAIL` / `DOPAFEED_USER_PASSWORD`
  - development / test では既定値（`nao@example.com` / `password`）にフォールバック、production では未設定なら `KeyError` で止める
  - 理由: (a) CI の `Tests: Seeds` 段と `bin/setup` を secrets なしで通す (b) 本番に既定パスワードのユーザーを作らない。環境分岐はこの 2 つの両立のため
  - 既存ユーザーのパスワードは上書きしない
- 5 フィード・30 記事（各 6 本）。固定文・固定日時。乱数・`Time.current` は使わない
- `bin/setup`: `db:prepare` の次に `db:seed`（db:prepare は新規作成時しか seed しない）
- `test/seeds_test.rb`: 2 回 load しても 5/30/1 のまま

### 5. Claude の骨と Budget（ADR 0002）
- `claude_api_calls`(purpose, model, timestamps) を台帳にする。Solid Cache のカウンタは追い出されうるので DB
- `Claude::Budget.new(limit:)`（既定は dopamine.yml の `claude.daily_call_limit`）: `used_today` / `remaining` / `exhausted?` / `record!(purpose:, model:)`
  - 上限ちょうどなら行を作らず `Claude::Budget::Exhausted`
  - 日の境は `Time.zone` の暦日。`daily_goal.reset_hour` は使わない（あれは読書、これは費用）
- `Claude::Client`: `Anthropic::Client.new(api_key: ENV.fetch("ANTHROPIC_API_KEY"))` を返すだけ
- `Claude::BaseJob`: `queue_as :claude`、`discard_on Claude::Budget::Exhausted`
- テスト先行: budget_test（上限・境界・日替わり）、base_job_test（Exhausted で discard）

### 6. 390×844 システムテストと bin/screens
- headless Chrome、`screen_size: [390, 844]` + mobileEmulation（pixelRatio 3, touch）
- `screenshot!(suffix = nil)` → `tmp/screenshots/<test名>.png`。teardown で成功時も毎回 1 枚
- `bin/screens`: tmp/screenshots を空にして `test:system` を回し一覧を出す
- `test/system/smoke_test.rb`: 未ログインで `/session/new` が 390 幅で出る。root は Unit 5 で決める

### 7. lint / hook
- `.erb_lint.yml`（既定リンタ + RuboCop 継承、ERB で誤検知する Layout 系 off）
- `bundle exec lefthook install`、`bin/hooks/rubocop-file` の疎通

### 8. CI
- `config/ci.rb` は触らない
- `.github/workflows/ci.yml` を 1 job（`bin/ci`）に。`tmp/screenshots` を `if: always()` で artifact 化

### 9. Litestream（ADR 0004）
- 同一コンテナで `litestream replicate -exec` が Thruster/Puma を子に持つ。accessory 方式は volume 共有と起動順が増えるので採らない
- Dockerfile に litestream バイナリ、`config/litestream.yml`（primary のみ複製。cache/queue/cable は再生成できる）
- entrypoint: `LITESTREAM_BUCKET` 未設定なら起動しない（静かに無バックアップで動く方が致命的）→ restore if-db-not-exists → db:prepare → replicate -exec
- deploy.yml: `env.secret` に `LITESTREAM_ACCESS_KEY_ID` / `LITESTREAM_SECRET_ACCESS_KEY`、`env.clear` に `LITESTREAM_BUCKET` / `LITESTREAM_REGION`
- `.kamal/secrets` は触らない。nao がやること: バケット・IAM キー・secrets 2 行・bucket/region

### 10. docs/runbook.md
- 復元（自動・手動・時刻指定）、ジョブ失敗の見方（FailedExecution、Budget 切れ）、Litestream の健全性確認

### 11. 仕上げ
- `bin/ci` 緑 → `bin/screens` → reviewer → PR（テンプレート全欄）→ Actions 緑

## 触らないもの
`config/dopamine.yml`、`.kamal/secrets`、`config/master.key`、`.env*`、`kamal deploy`

## 検証
- `bin/ci` が「Signoff: 緑」
- `tmp/screenshots/smoke_test_*.png` がある
- `bin/setup --skip-server` を 2 回流しても Feed 5 / Article 30 / User 1
- `bin/hooks/rubocop-file` が 0 で返る、`.git/hooks/pre-commit` が lefthook 製
- GitHub Actions `ci` 緑、artifact に screenshots

## 持ち越し
- `config.time_zone` は Unit 7 で。Budget の「今日」は今は UTC 暦日
- Docker image のビルド検証は nao の初回 `kamal build`
- Login の見た目（Unit 15）、root（Unit 5）
