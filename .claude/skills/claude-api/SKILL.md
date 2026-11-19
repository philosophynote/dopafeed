---
name: claude-api
description: Claude API を呼ぶ Unit（要約・選定・コメント・クエスト）で読む。RubyLLM での呼び方、モデルの使い分け、上限、VCR の作法。
---
- gem: `ruby_llm`（ADR 0028）。`Claude::Client.build` が呼ぶたびに `RubyLLM.context` を作る（鍵は ENV["ANTHROPIC_API_KEY"]、credentials 経由。`request_timeout` は claude.timeout_seconds、`max_retries = 0`）。RubyLLM 全体の設定（初期化子）には鍵を入れない
- 呼び方: `context.chat(model:, provider: Claude::Client::PROVIDER, assume_model_exists: true)` に `with_instructions`・`with_max_output_tokens`・`with_thinking(false)` を付け、`ask_later(...).generate` で 1 回だけ生成する。`ask` はツールを求める応答で呼び直し続ける。thinking は切らないとモデルの既定で有効になり max_tokens を食う
- 応答: `message.content`（文字列）と `message.finish_reason`（`:stop` / `:max_tokens` / `:tool_calls` / `:content_filter`）。`:max_tokens` は切れた応答として失敗にする
- モデル ID と用途は config/dopamine.yml の claude.* から読む。コードにモデル名を書くな
- 呼び出しは app/services/claude/<purpose>.rb（例: Claude::Summarizer）。入出力は PORO。Job（app/jobs/claude/）が呼ぶ
- 日次上限: Claude::Budget が claude.daily_call_limit を数え、超えたら Job を discard してログ。呼ぶ前に記録する（失敗も 1 回）
- 例外: `RubyLLM::Error` は `response&.status` で分ける。状態なし（接続・タイムアウト）と 408・429・5xx は TransientError（Job が再試行）、他の 4xx は Error。RubyLLM::Error 以外の例外も Error に畳む。失敗の理由には状態だけを残す（応答の文面は要求を引用しうる）。Job・モデルは RubyLLM を知らない（spec/structure が落とす）。API キー欠落（Client.build の KeyError）は設定の誤りなので畳まず、Solid Queue の失敗に残す
- テスト: VCR カセットは spec/vcr_cassettes/claude/<purpose>/（設定は spec/support/vcr.rb。CI は record: :none、照合は method と URI）。API キーは filter_sensitive_data で伏せる。実キーで録り直すのは nao の Mac（`VCR_RECORD=all ANTHROPIC_API_KEY=… bin/rspec <spec>`）。エラー系は WebMock の stub_request（gem は再試行しないのでヘッダの細工は要らない）
- プロンプトは app/services/claude/prompts/（system は .txt、user は .erb）に置き、テストでスナップショット比較（spec/fixtures/files/claude/）
- 詳しい API 仕様は Anthropic 公式ドキュメントと ruby_llm のソースで確認。記憶で書くな
