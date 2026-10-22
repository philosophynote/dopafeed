---
name: kamal-deploy
description: config/deploy.yml、Dockerfile、Litestream、Solid Queue の本番設定を触るときに読む。デプロイ自体は人が打つ。
---
- `kamal deploy` はエージェントが打たない（settings.json で deny）。設定の変更は PR で提案する
- Lightsail 1 GB: WEB_CONCURRENCY=1、Solid Queue は Puma 内（SOLID_QUEUE_IN_PUMA=true）で 1 プロセス
- SQLite は Kamal の volume に置く（storage/）。Litestream は ADR 0004 に従いサイドプロセスで複製
- secrets は .kamal/secrets（読むな）。鍵の名前だけ config/deploy.yml の env.secret に列挙
- 変更後は `kamal config` と `bin/ci` が緑であることを確認し、nao にデプロイを頼む
