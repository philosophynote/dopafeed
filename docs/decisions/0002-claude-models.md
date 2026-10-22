# ADR 0002: Claude API の使い分け
日付: 2026-10-22 状態: 採用
3 行要約は Haiku、朝の 3 本選定・クエスト生成・週次コメントは Sonnet。呼び出しは app/services/claude/ に集約し ActiveJob 経由。日次上限は config/dopamine.yml の claude.daily_call_limit。テストは VCR。
