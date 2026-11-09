# Dopafeed
一人用の「ドーパミンが出る」RSS リーダー。iPhone の PWA。Rails 8.1 + Hotwire + Tailwind + SQLite。
主な読者は nao 一人。SNS の中毒性を技術記事読みに向ける。

## まず読む
- docs/SPEC.md            製品の芯。7 つの報酬要素と画面の対応表、iOS PWA の制約と代替策
- docs/screens/<name>.md  作る画面の仕様と受け入れ条件（Given-When-Then）。無い画面は作るな
- docs/decisions/         ADR。ここに無い技術選定は勝手にせず、提案して止まれ
- docs/plans/             陣（Milestone）の範囲と完了条件。Unit の計画と進捗は GitHub Issue（ラベル unit）。nao の「承認」コメントが無い計画で実装に入るな（ADR 0008）

## 完了の定義
- `bin/ci` が緑。通らぬ PR は開くな
- テストは実装前に書き、失敗を確認してから実装する
- 画面を触った Unit は spec/system/ に 390×844 のシステムテストを足し、`bin/screens` で tmp/screenshots/ に撮る
- PR 本文は .github/pull_request_template.md の欄を全部埋める

## 規約
- テストは RSpec + FactoryBot（spec/。ADR 0007）。fixtures は使わない。`bin/rspec` で回す
- コードには How（どう実現するか）、テストコードには What（何を保証するか）、コミットログには Why（なぜ変更するか）、コードコメントには Why not（なぜ別の方法を採らないか）を書く（ADR 0009）
- コメントはコード・テストから読み取れない制約や、素朴な実装では困る理由があるときだけ書く。処理の逐語訳、名前・型の言い換え、ファイル冒頭の要約、セクション見出し、変更履歴は書かない。クラス・モジュール・メソッドへのコメントは必須にしない。Ruby・JavaScript・ビュー・設定・テスト補助コードに同じ基準を適用し、テストの期待動作は例の名前とアサーションで示す。Ruby のコメントを書く場合は日本語・YARD 書式とし、`@param` / `@return` / `@raise` / `@yield` も自明なら省く。ライセンス表記・shebang・マジックコメント・lint 等のツール指示・自動生成ファイルはこの整理の対象外
- Ruby のコメントに書かないもの: 工程（Unit 番号・陣・「別 PR で」。Issue と PR に書く）、画面名（モデル・サービス・ジョブは画面を知らない。app/views と docs/screens に書く）、呼び出し元の列挙（守らせたいなら spec/structure/ のテストで落とす）、呼ぶ側と呼ばれる側への同じ説明（定義側に残す）
- Hotwire（Turbo Frames / Streams + Stimulus）。SPA 化・React・外部 JS フレームワーク持ち込み禁止
- Claude API は app/services/claude/ に集約し、必ず ActiveJob（Solid Queue）経由。コントローラ・モデルから直接呼ぶな
- XP 量・確率・閾値・秒数・本数は config/dopamine.yml。コードに数字を埋めるな（spec/structure/ が落とす）
- 外部通信（Claude API、RSS）はテストで VCR / WebMock。CI は実通信ゼロ
- DB 変更は migration のみ。設計変更は docs/decisions/ に ADR を足す
- 一 Unit = 一 Issue = 一ブランチ `unit-<n>-<name>` = 一 PR（`Closes #N`）= 差分 300 行前後。超えるなら割って提案せよ

## 禁止
- `kamal deploy`、本番 DB、secrets（config/master.key, .env*）に触るな。人が打つ
- config/dopamine.yml の値を変えるな。変えたいなら PR 本文で提案せよ
- 同じ修正に二度失敗したら止まって報告せよ
