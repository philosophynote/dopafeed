# DopaFeed (Rails)

SNS の中毒性を技術記事読みに向けた自分用 RSS リーダー。Rails 8 + Hotwire の PWA 版。
画面モック: https://claude.ai/artifact/UF3JSQDBeEUGhESB3JvWyx
Swift 版（参考・後で削除予定）: ../dopafeed-swift

## 決定事項
- Ruby 4.0.7 / Rails 8.1.4 / Kamal 2.12（2026-10-11 時点の最新）
- SQLite + Solid Queue + Solid Cache（Rails 8 標準構成）
- デプロイ: AWS Lightsail $5 プラン（1GB）に Kamal + Docker
- Claude API: 3 行要約（Haiku）、朝の 3 本選定・ネタのクエスト生成（Sonnet）、週次コメント
- アウトプット側は article-vault（GitHub）へサーバーからコミット

## 開発方針（2026-10-22 決定）
- 進め方: ../notes/dopafeed-dev-approach.md（Unit 分割、第一の陣、ハーネス）
- Claude Code 主、Codex 副（`@codex review` で第二レビュー、テスト先行作成、ドリフト返済）
- 第一の陣: Unit 0〜7 + Install + Login。出力段 6 画面は本丸を使ってから判断
- 認証はパスワード、CSS は Tailwind、Litestream で SQLite バックアップ
- Unit 0 の雛形と開始命令: unit0/KICKOFF.md

## 状態
Unit 0（縄張り）: `bin/ci`・GitHub Actions・390×844 システムテスト・認証・seed・Claude の骨・Litestream 設定。運用は docs/runbook.md。
