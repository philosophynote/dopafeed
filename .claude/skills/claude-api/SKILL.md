---
name: claude-api
description: Claude API を呼ぶ Unit（要約・選定・コメント・クエスト）で読む。SDK の使い方、モデルの使い分け、上限、VCR の作法。
---
- gem: 公式 `anthropic`。`Anthropic::Client.new`（API キーは ENV["ANTHROPIC_API_KEY"]、credentials 経由）
- モデル ID と用途は config/dopamine.yml の claude.* から読む。コードにモデル名を書くな
- 呼び出しは app/services/claude/<purpose>.rb（例: Claude::Summarizer）。入出力は PORO。Job（app/jobs/claude/）が呼ぶ
- 日次上限: Claude::Budget が claude.daily_call_limit を数え、超えたら Job を discard してログ
- テスト: VCR カセットは test/vcr_cassettes/claude/<purpose>/。API キーは filter_sensitive_data で伏せる
- 要約プロンプトは app/services/claude/prompts/*.erb に置き、テストでスナップショット比較
- 詳しい API 仕様は Anthropic 公式ドキュメントを WebFetch で確認。記憶で書くな
