# ADR 0031: system spec は PR とデプロイの CI から外し、毎晩 main で回す
日付: 2026-11-21 状態: 採用（#167）。ADR 0021 の「CI が検証した commit をそのまま配る」の CI から system spec を外す。#166 で急ぎ外した規約テスト・Rails のテスト・Seeds は CI に戻す

nao の依頼（2026-11-21「SystemSpec が flaky で時間がかかってしまうので通常の CI では実行せずに毎日日本時間午前 2 時に実行して CI が失敗したらメールで通知」）。

## なぜ
system spec は CI の Chrome が固まる（#38）、応答待ちの競合（PR #165）で main でも不規則に落ち、そのたびにデプロイが止まった。#166 で急ぎのリリースのため CI からテストを丸ごと外し、テスト無しで本番に出る状態になった。

## 決めたこと
- **通常の CI（PR、main への push → Deploy）**: Setup・Style・Security に、規約テスト・Rails のテスト（system 以外）・Seeds を戻す。system 以外の 771 例は 20 秒ほどで安定している
- **毎晩**: `.github/workflows/system-nightly.yml` が UTC 17:00（JST 2:00）に main で `bin/system-nightly` を回す。手動実行（workflow_dispatch）もできる。スクショは artifact に残す
- **flaky の扱い**: `bin/system-nightly` は `bin/screens` が赤なら落ちた例だけ `--only-failures` で 1 回再実行する。再実行で緑なら成功とし、通った例をジョブの Summary に「flaky」として残す。再実行でも赤なら失敗。例を走らせる前に止まった（Tailwind のビルドや読み込みの失敗）ときは再実行せず失敗にする
- **知らせ方**: GitHub の既定の通知メール。定時ワークフローの失敗は、ワークフローの cron を最後に書き換えた人に届く。workflow ファイルは nao が入れるので宛先は nao。秘密もアドレスもリポジトリに置かない。受け取りには nao の通知設定（Actions を Email）が要る
- **デプロイのゲート**: 夜間の失敗は配った後に分かる。止める仕組みは入れない。戻すときは Rollback（ADR 0021）か修正 PR
- **画面の Unit**: PR の前に手元で `bin/screens` を緑にする（AGENTS.md の完了の定義、PR テンプレート）

## 採らなかった案
- **system を通常 CI に残し continue-on-error**: 遅さは残り、赤が既定になって誰も見なくなる
- **PR ラベルで system を任意に回す**: 忘れると回らず、main の状態が分からない
- **失敗時に Issue を自動で立てる**: 履歴は残るが `issues: write` の権限が要り、flaky が続くと Issue が溜まる。既定メールが届かないと分かったら次の手にする
- **SMTP でメールを送る action**: 確実だが SMTP の秘密を Actions に置くことになる
- **再実行しない**: flaky のたびに夜中のメールが来て、本当の退行と見分けられなくなる

## 持ち越し
- GitHub は 60 日コミットの無いリポジトリの定時ワークフローを止める（止まる前に知らせが来る）。定時実行は混雑時に遅れることがある
- system spec の flaky そのもの（#38 ほか）は別に直す
