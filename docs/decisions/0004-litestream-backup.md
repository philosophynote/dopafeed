# ADR 0004: Litestream で SQLite を継続バックアップ
日付: 2026-10-22 状態: 採用（Unit 0 の直後に実装）
記事と XP 履歴が消えるのはこのアプリに最も致命的。Litestream を同コンテナのサイドプロセスとして Kamal accessory か Procfile で起動し、S3 互換ストレージへ複製。復元手順を docs/runbook.md に書く。

追記 2026-10-23（Unit 0 で実装）: 方式は「同一コンテナで `litestream replicate -exec` が Thruster/Puma を子プロセスに持つ」に決めた。
accessory は volume の共有と起動順の管理が増え、Procfile は 1 コンテナ 1 プロセスの Kamal と相性が悪い。
複製対象は primary（storage/production.sqlite3）だけ。cache / queue / cable は再生成できる。
`LITESTREAM_BUCKET` / `LITESTREAM_REGION` が無いときは server を起動しない（バックアップ無しで静かに動くほうが致命的）。
設定: Dockerfile、config/litestream.yml、bin/docker-entrypoint、config/deploy.yml。

追記 2026-10-25（runbook §0 / §2-g を書くときに決めた）:
- Litestream 用 IAM ユーザーはバケット 1 つに Get / Put / Delete / List だけ。鍵は Rails の暗号化 credentials に置き、`.kamal/secrets` は参照だけ
- 複製バケットの S3 データイベントを CloudTrail で記録する。既定ではイベント履歴に S3 操作が出ず、鍵が漏えいしたとき「何をされたか」が
  後から分からない。費用は月 $0.1 前後
- バージョニングを有効にするなら非現行版のライフサイクル規則を必ず付ける。無いと `retention` を過ぎた WAL が永久に溜まる（runbook §0 手順 1）
