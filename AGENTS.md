# Dopafeed
一人用の「ドーパミンが出る」RSS リーダー。iPhone の PWA。Rails 8.1 + Hotwire + Tailwind + SQLite。
主な読者は nao 一人。SNS の中毒性を技術記事読みに向ける。

## まず読む
- docs/SPEC.md            製品の芯。7 つの報酬要素と画面の対応表、iOS PWA の制約と代替策
- docs/screens/<name>.md  作る画面の仕様と受け入れ条件（Given-When-Then）。無い画面は作るな
- docs/decisions/         ADR。ここに無い技術選定は勝手にせず、提案して止まれ
- docs/plans/             Unit ごとの実行計画。承認印の無い計画で実装に入るな

## 完了の定義
- `bin/ci` が緑。通らぬ PR は開くな
- テストは実装前に書き、失敗を確認してから実装する
- 画面を触った Unit は spec/system/ に 390×844 のシステムテストを足し、`bin/screens` で tmp/screenshots/ に撮る
- PR 本文は .github/pull_request_template.md の欄を全部埋める

## 規約
- テストは RSpec + FactoryBot（spec/。ADR 0007）。fixtures は使わない。`bin/rspec` で回す
- Ruby のコメントは YARD（クラス・モジュール冒頭の 1 行要約、`@param` / `@return` / `@raise`）。日本語で書く
- Hotwire（Turbo Frames / Streams + Stimulus）。SPA 化・React・外部 JS フレームワーク持ち込み禁止
- Claude API は app/services/claude/ に集約し、必ず ActiveJob（Solid Queue）経由。コントローラ・モデルから直接呼ぶな
- XP 量・確率・閾値・秒数・本数は config/dopamine.yml。コードに数字を埋めるな（spec/structure/ が落とす）
- 外部通信（Claude API、RSS）はテストで VCR / WebMock。CI は実通信ゼロ
- DB 変更は migration のみ。設計変更は docs/decisions/ に ADR を足す
- 一 Unit = 一ブランチ `unit-<n>-<name>` = 一 PR = 差分 300 行前後。超えるなら割って提案せよ

## 禁止
- `kamal deploy`、本番 DB、secrets（config/master.key, .env*）に触るな。人が打つ
- config/dopamine.yml の値を変えるな。変えたいなら PR 本文で提案せよ
- 同じ修正に二度失敗したら止まって報告せよ
