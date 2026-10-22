# ADR 0004: Litestream で SQLite を継続バックアップ
日付: 2026-10-22 状態: 採用（Unit 0 の直後に実装）
記事と XP 履歴が消えるのはこのアプリに最も致命的。Litestream を同コンテナのサイドプロセスとして Kamal accessory か Procfile で起動し、S3 互換ストレージへ複製。復元手順を docs/runbook.md に書く。
