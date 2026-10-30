# ADR 0003: AWS Lightsail $7（Micro、1 GB）に Kamal でデプロイ
日付: 2026-10-22 状態: 採用
Puma 1 worker + Solid Queue 1 プロセス + SQLite を一コンテナで。`kamal deploy` は nao が Mac から打つ。自動デプロイは Unit 10 を超えてから再検討。

追記 2026-10-25（runbook §0 を書くときに決めた）:
- プランは $7 Micro（1 GB / 2 vCPU / 40 GB）。$5 Nano は 0.5 GB で Puma + Solid Queue + Litestream + kamal-proxy が載らない。保険に swap 1 GB
- TLS は kamal-proxy が Let's Encrypt で終端し、HTTP → HTTPS 転送も担う。production.rb の `force_ssl` / `assume_ssl` と対になる
- ドメインは Cloudflare Registrar で取り、DNS も Cloudflare に置く。A レコードは DNS only（Proxied にしない）。
  理由: Registrar は原価販売で更新も同額、WHOIS 非公開が無料。DNS only にするのは Let's Encrypt の HTTP-01 と転送の確認経路を
  kamal-proxy の挙動だけで閉じるため。Lightsail DNS / Route 53 は取得と DNS が別事業者になり管理が増える。
  CDN / WAF が欲しくなったら SSL/TLS を Full (strict) にして Proxied へ切り替える別 ADR
- SSH は `ubuntu` ユーザー（Lightsail の Ubuntu は root で入れない）。22 番は管理用 Mac の IP だけに絞る
