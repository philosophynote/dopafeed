# ADR 0007: テストは RSpec + FactoryBot、Ruby のコメントは YARD
日付: 2026-11-01 状態: 採用（Unit 2a で実装）

nao の指示。Unit 0 の Minitest + fixtures を全て spec/ に移し、以後の Unit は spec/ だけを書く（test/ と spec/ の二本立てにしない）。

- RSpec（rspec-rails）+ FactoryBot（factory_bot_rails）。fixtures は使わず、レコードは spec/factories で作る
- 置き場は Rails 既定: spec/models, spec/requests（controller test は request spec）, spec/services, spec/jobs, spec/system, spec/structure（規約テスト）, spec/seeds_spec.rb
- システムテストは spec/system。390×844 の headless Chrome と例ごとのスクショは spec/support/system.rb。スクショ名は `<spec 名>_<例の説明>[_suffix].png`。
  成功時のスクショは rspec-rails の after（失敗時スクショ → Capybara.reset_sessions!）より先に撮る必要があるので、config.after ではなく include 時に group の after として登録する
- 並列実行は入れない。rspec-rails に Minitest の parallelize 相当は無く、入れるなら parallel_tests gem という別の選定になる。今は 40 本・1 秒。遅くなったら ADR を足す
- rubocop-rspec は入れない（rubocop-rails-omakase の方針のまま）。yard gem も入れない（書式だけ採る）
- Ruby のコメントは YARD 書式（クラス・モジュール冒頭の 1 行要約、`@param` / `@return` / `@raise` / `@yield`）。日本語のまま。既存 app/ のコメントは触ったファイルから順に直す
- 走らせる側: config/ci.rb の 3 段（Structure / Tests: Rails / Tests: System）、bin/screens、lefthook の pre-push、.claude/settings.json の Stop hook を `bin/rspec` に揃えた
