---
name: claude-api
description: Claude API を呼ぶ Unit（要約・選定・コメント・クエスト）で読む。SDK の使い方、モデルの使い分け、上限、VCR の作法。
---
- gem: 公式 `anthropic`。`Anthropic::Client.new`（API キーは ENV["ANTHROPIC_API_KEY"]、credentials 経由）
- モデル ID と用途は config/dopamine.yml の claude.* から読む。コードにモデル名を書くな
- 呼び出しは app/services/claude/<purpose>.rb（例: Claude::Summarizer）。入出力は PORO。Job（app/jobs/claude/）が呼ぶ
- 日次上限: Claude::Budget が claude.daily_call_limit を数え、超えたら Job を discard してログ
- テスト: VCR カセットは spec/vcr_cassettes/claude/<purpose>/（設定は spec/support/vcr.rb。CI は record: :none）。API キーは filter_sensitive_data で伏せる。実キーで録り直すのは nao の Mac（`VCR_RECORD=all ANTHROPIC_API_KEY=… bin/rspec <spec>`）。エラー系は WebMock の stub_request（ヘッダ `x-should-retry: false` で SDK の再試行を止める）
- SDK の例外（Anthropic::Errors::Error 以下）はサービスの中で自前の例外に畳む（例: Claude::Summarizer::Error / TransientError）。Job・モデルは Anthropic:: を知らない（spec/structure が落とす）。API キー欠落（Client.build の KeyError）は設定の誤りなので畳まず、Solid Queue の失敗に残す
- プロンプトは app/services/claude/prompts/（system は .txt、user は .erb）に置き、テストでスナップショット比較（spec/fixtures/files/claude/）
- 詳しい API 仕様は Anthropic 公式ドキュメントを WebFetch で確認。記憶で書くな
