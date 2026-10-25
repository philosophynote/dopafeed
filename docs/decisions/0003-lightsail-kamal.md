# ADR 0003: AWS Lightsail $7（Micro、1 GB）に Kamal でデプロイ
日付: 2026-10-22 状態: 採用
Puma 1 worker + Solid Queue 1 プロセス + SQLite を一コンテナで。`kamal deploy` は nao が Mac から打つ。自動デプロイは Unit 10 を超えてから再検討。
