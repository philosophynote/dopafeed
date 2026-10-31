# Unit 2a「テスト基盤を RSpec + FactoryBot に移す」実行計画

状態: **承認済み 2026-11-01（nao）**

ブランチ: `unit-2a-rspec`（main から。1 PR。test/ 752 行を spec/ に移す）
Unit 2（`unit-2-domain`、Minitest で実装済み・reviewer 反映済み）はこの上に乗せ、spec と YARD に書き直して別 PR で出す。

## Context
nao の指示（2026-11-01）: テストは RSpec + FactoryBot、コメントは全て YARD。
Unit 0 の縄張りは Minitest + fixtures で張ってあり、`config/ci.rb` の段・Stop hook・lefthook・`bin/screens`・AGENTS.md の完了の定義が `bin/rails test` を前提にしている。
Unit 2 だけを RSpec で書くと test/ と spec/ の二本立てになるので、先に基盤を一括で移し（この Unit）、以後の Unit は spec/ だけを書く。
ADR に無い技術選定なので ADR 0007 を足す。

## 決めること（ADR 0007）
1. **RSpec（rspec-rails 8.0）+ FactoryBot（factory_bot_rails 6.5）**。fixtures は廃止し factories に置き換える。Minitest のテストは全て spec に変換して test/ を消す（二本立てにしない）
2. **spec の置き場は Rails 既定**: `spec/models` / `spec/requests`（controller test は request spec に）/ `spec/services` / `spec/jobs` / `spec/system` / `spec/structure`（規約テスト）/ `spec/seeds_spec.rb` / `spec/lib`
3. **システムテストは `spec/system`、390×844 の driver と `screenshot!` は `spec/support/system.rb` に移す**。スクショ名は `<spec ファイル名>_<example 名>[_suffix].png`（今の `<クラス名>_<テスト名>` と同じ粒度）。`bin/screens` は `bin/rspec spec/system` を呼ぶ
4. **並列実行は入れない**（Minitest の `parallelize` 相当の parallel_tests gem は足さない。今は 41 本・数秒。要るときに ADR）
   補足（理解度チェックで食い違った点）: rspec-rails には `parallelize` に相当する設定が**無い**。rails_helper に書いて同等にはできない。
   並列にするなら parallel_tests gem を足す新しい技術選定になるので、遅くなってから ADR で入れる。今は直列で回る（数秒）
5. **YARD**: Ruby のコメントは YARD（`# @param` / `# @return` / `# @raise`、クラス・モジュールの冒頭に 1 行の要約）。日本語のまま。この Unit で書く support / factories / spec の補助メソッドから適用し、AGENTS.md の規約に 1 行足す。既存の app/ のコメント（Unit 0）は Unit 2 以降、触ったファイルから順に直す（一括変換は差分を膨らませるのでしない）。yard gem は入れない（書式だけ採る。生成が要るなら別途）
6. `.claude/settings.json` の Stop hook と allow リストは **nao が承認した上でこの PR で書き換える**（`bin/rails test` → `bin/rspec --exclude-pattern "spec/system/**/*_spec.rb"`。allow に `Bash(bin/rspec*)`, `Bash(bundle exec rspec*)`）。エージェントが自分の権限設定を触る形になるので、ここに明記して承認を取る

## 変更

### Gemfile
- `group :development, :test` に `rspec-rails`, `factory_bot_rails`
- `group :test` は `capybara`, `selenium-webdriver`, `vcr`, `webmock` のまま
- `bundle install` → `bin/rails generate rspec:install`（`.rspec`, `spec/spec_helper.rb`, `spec/rails_helper.rb`）→ `bundle binstubs rspec-core`（`bin/rspec`）

### spec/rails_helper.rb, spec/spec_helper.rb, .rspec
- `.rspec`: `--require rails_helper`（spec 側の `require "rails_helper"` を省く）、`--format documentation`
- rails_helper: `use_transactional_fixtures = true`、`infer_spec_type_from_file_location!`、`spec/support/**/*.rb` を読む、`config.include FactoryBot::Syntax::Methods`、`ActiveJob::TestHelper`（type: :job / :request）、`ActiveSupport::Testing::TimeHelpers`（travel_to）
- `filter_rails_from_backtrace!`

### spec/support/
- `system.rb`: `before(:each, type: :system)` で `driven_by :selenium, using: :headless_chrome, screen_size: [390, 844]` + `add_emulation`（test/application_system_test_case.rb の中身をそのまま）。`screenshot!(suffix = nil)` と、例が終わるごとの 1 枚（rspec-rails の `after`（失敗時スクショ → `Capybara.reset_sessions!`）より**先に**走るよう、include 順で後に登録する。動かなければ `prepend_after`。実装時に確認し、計画からの変更に書く）
- `session_helper.rb`: `sign_in_as(user)` / `sign_out`（test/test_helpers/session_test_helper.rb から。request spec の cookies に合わせる）
- `env_helper.rb`: `with_env(values) { }`（seeds_test と client_test が別々に持っている同じコードを 1 つに）
- `logger_helper.rb`: `with_rails_logger(logger) { }`（base_job_test から）
- `production_helper.rb`: `pretending_production { }`（seeds_test から）

### spec/factories/
- `users.rb`: `email_address { "nao@example.com" }` 系は sequence、`password { "password" }`
- `feeds.rb`: sequence の url、title、site_url
- `articles.rb`: `association :feed`、sequence の url、title、`summary`、`published_at`。trait `:unsummarized`
- （readings / daily_goals の factory は Unit 2 の PR で足す）

### 変換（test/ → spec/。1 対 1。アサーションの意図を変えない）
| test/ | spec/ | 型 |
|---|---|---|
| models/{article,feed,user}_test.rb | models/*_spec.rb | model |
| controllers/{home,sessions,passwords}_controller_test.rb | requests/*_spec.rb | request |
| services/claude/{budget,client}_test.rb | services/claude/*_spec.rb | - |
| jobs/claude/base_job_test.rb | jobs/claude/base_job_spec.rb | job（`ExhaustingJob` / `CountingJob` は spec 内で定義） |
| seeds_test.rb | seeds_spec.rb | - |
| structure/conventions_test.rb | structure/conventions_spec.rb | -（失敗文に直し方を書く、は維持） |
| system/smoke_test.rb | system/smoke_spec.rb | system |
| mailers/previews/passwords_mailer_preview.rb | spec/mailers/previews/（`config.action_mailer.preview_paths` を spec 側へ。rspec:install が設定する） | - |
- fixtures で参照していたレコード（`users(:one)`, `feeds(:rails_blog)`, `articles(:rails_81)` …）は `let!` + factory に
- `assert_difference` → `expect { }.to change { }`、`assert_enqueued_email_with` → `have_enqueued_mail`、`assert_select "div", /text/` → `expect(response.body).to match(...)`（passwords の `assert_notice`）
- test/ ディレクトリと `test/fixtures` は削除。`test/structure` の参照（AGENTS.md、app/services/claude/client.rb のコメント）を `spec/structure` に

### 走らせる側
- `config/ci.rb`: `Structure: 規約テスト` → `bin/rspec spec/structure`、`Tests: Rails` → `bin/rspec --exclude-pattern "spec/system/**/*_spec.rb"`、`Tests: System (390x844)` → `bin/rspec spec/system`。段の名前と順は変えない
- `bin/screens`: `bin/rspec spec/system "$@"`
- `lefthook.yml` pre-push: `bin/rspec --exclude-pattern "spec/system/**/*_spec.rb"`
- `.claude/settings.json`: 上の 6
- `.github/workflows/ci.yml`: 変更なし（bin/ci を呼ぶだけ）

### 文書
- `docs/decisions/0007-rspec-factory-bot-yard.md`
- `AGENTS.md`: 完了の定義「test/system/」→「spec/system/」、「テストは実装前に書き」はそのまま。規約に「テストは RSpec + FactoryBot（spec/）。fixtures は使わない」「Ruby のコメントは YARD」を足す。「test/structure/ が落とす」→「spec/structure/」
- `CLAUDE.md`: 「停止前に `bin/rails test`」→「`bin/rspec`」
- `.claude/agents/reviewer.md`: 手順 3 に「spec が無い受け入れ条件」の表現で spec/ を指す 1 語を直す（中身は変えない）
- `docs/plans/unit-2a.md`: この文書
- `docs/plans/unit-2.md`: 「テスト・fixtures」節を「spec/ + factories」に書き直す（Unit 2 の PR で）

## 手順
1. `git checkout -b unit-2a-rspec`、docs/plans/unit-2a.md
2. Gemfile → `bundle install` → `rspec:install` → binstub。`bin/rspec` が 0 例で緑
3. support と factories。`spec/models/user_spec.rb` から 1 本ずつ変換し、各ファイルで `bin/rspec <file>` 緑を見る（変換はテスト先行ではなく「同じ assertion が緑」で等価を確認）
4. 全部変換したら test/ を削除 → `bin/rspec` 全緑 → `bin/rspec spec/system`（1 本 25 分かかる環境なので 1 回だけ。スクショ 2 枚が tmp/screenshots に出ることを確認）
5. ci.rb / bin/screens / lefthook / settings.json / AGENTS.md / CLAUDE.md / reviewer.md / ADR 0007
6. `bin/ci` 緑 → reviewer → PR（テンプレート全欄。画面欄は smoke のスクショ 1 枚を貼る: 枠が変わっていない証拠）
7. 続けて Unit 2: `unit-2-domain` を `unit-2a-rspec` に rebase、test/ 側の追加分を spec/ + factories（readings, daily_goals）に書き直し、app/models と lib の Unit 2 ファイルのコメントを YARD に。PR の base は `unit-2a-rspec`（2a が main に入ったら base を main に変える）

## 差分の見込み
test/ 752 行の削除と spec/ ほぼ同量の追加 + 設定・文書 100 行前後 ≈ 削除 750 / 追加 850。
「一 PR 300 行前後」を超えるが、移行は半分に割ると test/ と spec/ が同居する期間ができるので 1 PR で出す（計画で明記して承認を取る）。
補足（理解度チェックで食い違った点）: 1 PR にする理由は「削除が軽いから」ではない。半分だけ移すと bin/ci が Minitest と RSpec の二つのランナーを回す中間状態が main に入り、
その間に書く Unit がどちらに書くか迷う。この中間状態を作らないことが理由。削除 750 行がレビューの負荷にならないのは結果にすぎない。

## 触らないもの
`config/dopamine.yml`、`app/` の実装（コメントの YARD 化は Unit 2 以降）、`db/`、`.kamal/secrets`、`config/master.key`、`.env*`、`unit-2-domain` ブランチ（この Unit の後で rebase）

## 検証
- `bin/rspec` 全緑（system 除く）、例数が Minitest の 41 runs（main 時点、system 除く）と同じか理由が説明できる
- `bin/rspec spec/system` 緑、`tmp/screenshots/smoke_*.png` 2 枚以上、`window.innerWidth == 390`
- `bin/rspec spec/structure` 緑（規約テストが app/ の違反を今までどおり落とす: 一時的に app/ に `xp = 1` を書いて赤を確認してから戻す）
- `bin/ci` 「Signoff: 緑」
- `grep -r "bin/rails test\|test/system\|test/structure\|fixtures" --include="*.md" --include="*.yml" --include="*.json" --include="*.rb" .`（docs/plans/unit-0*, unit-1 の履歴を除く）が 0 件

## 持ち越し
- 並列実行（parallel_tests）。要るときに ADR
- app/ の既存コメントの YARD 化（Unit 2 以降、触ったファイルから）
- VCR の共通設定（spec/support/vcr.rb）は Claude を呼ぶ最初の Unit（4）で足す。今は呼び出しが無い
- rubocop-rspec は入れない（rubocop-rails-omakase の方針に合わせる。要るなら ADR）

## 計画からの変更（実装中に決めたこと）
- `bin/screens` は常に spec/system を回し、引数は `bin/rspec` のオプションとして足す（例: `bin/screens --seed 123`）
- メーラープレビューの置き場は rspec-rails の railtie が `spec/mailers/previews` を preview_paths に足すので設定不要（development で確認済み）
- 成功時スクショの after は `SystemScreen.included` で group の after として登録したら、rspec-rails の after より先に走った（3 枚とも中身あり）。`prepend_after` は要らなかった
- system spec 2 本が 11 秒で終わる。Minitest 版は同じ 2 本で 25 分（`parallelize` のワーカーが Chrome を抱えて待っていたと見える）。bin/ci の System 段が 60 分だった件はこれで消えるはず
- 例数は Minitest の非 system 41 + system 2 = 43 と一致

## レビューで直したこと
- `filter_run_when_matching :focus` を消した（`fit` を 1 つ commit すると bin/ci がその 1 例だけで緑になる）
- 成功時スクショの順序は「support の include が `require "rspec/rails"` より後」が前提と system.rb に明記。例ごとの 1 枚は smoke_spec の after(:context) で存在を確認
- passwords_spec の notice は body 全体ではなく div の文言で見る（Minitest 版の `assert_select "div"` と同じ強さ）
- bin/screens は常に spec/system を回し、引数はオプションとして足す
- 文書の例数を 41（system 込み 43）に統一、AGENTS.md の YARD タグに `@yield`
