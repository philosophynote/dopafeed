# ADR 0003: AWS Lightsail に Kamal でデプロイ（2026-11-07 追記: $5 Nano 512 MB で試し、同日 $7 Micro 1 GB へ）
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

追記 2026-11-07（初回デプロイ。上の「Nano は載らない」を改める）:
- まず $5 Nano（512 MB / 2 vCPU / 20 GB）で試す。費用を抑えたいのと、1 GB への移行がスナップショットで後から一日で済むため。
  実測（Ubuntu 24.04 ＋ Docker、アプリ無し）は使える総量 412 MB、空き 151 MB。要らない常駐（multipathd・networkd-dispatcher・udisks2・packagekit）を止めて 218 MB。
  snapd と amazon-ssm-agent は残す（ブラウザ SSH の退路が SSM に頼るか確かめていない）。unattended-upgrades も残す（公開サーバーのセキュリティ更新）
- 512 MB の間は二つ切り替える。どちらも config/deploy.yml の env で、1 GB に上げたら行を消して既定に戻す:
  - Solid Queue を async（`SOLID_QUEUE_MODE=async`）。fork だと Puma の他に supervisor・dispatcher・worker・scheduler の 4 プロセスが立ち、
    手元の production 起動で RSS がそれぞれ約 155 MB、async は 1 プロセス約 180 MB。RSS は fork 元と共有するページも数えるので fork 側は多めに出る。
    本番イメージ（Ruby 4.0.7、jemalloc）での値は runbook §0-8 で測り直す。
    Solid Queue の README は fork を勧めるが、理由は隔離と性能で、一人用のジョブ量では効かない。
    async ではジョブのスレッドも Puma のプロセスに入るので、DB の接続数を primary 8・queue 12 に足した（内訳は config/database.yml）
  - YJIT を切る（`YJIT_ENABLED=false`）。速さよりメモリ
- 1 GB（$7 Micro）に上げる基準: ① `dmesg` に OOM kill、② deploy 中でない平常時に swap 使用が 300 MB を超え続ける、③ 表示が体感で遅い。
  どれか一つで上げる。上げ方は docs/runbook.md §0 4-c（スナップショットから作り直し、静的 IP を付け替え。volume ごと移るので Litestream の復元は要らない）
- ドメインは `dopafeed.dev`（Cloudflare Registrar、DNS も Cloudflare）。.dev は HSTS preload 済みでブラウザが最初から https しか使わず、force_ssl と食い違わない
- 訂正: kamal-proxy の Let's Encrypt の認証は 443 番で受ける（Kamal 2.12 の configuration/docs/proxy.yml「port 443 must be open for the Let's Encrypt challenge」）。
  上の「HTTP-01 の経路」という書き方は不正確（80 番で受けるかまでは確かめていない）。80 と 443 はどちらも開ける。
  DNS only にする理由は、Cloudflare が 443 を受けると認証がサーバーに届かないから
- レジストリは `localhost:5555`（Kamal の手元レジストリ）。Mac の Docker にレジストリを立て、SSH のポート転送でサーバーに pull させる。外部レジストリと PAT が要らない。
  代わりに `kamal deploy` の間、Mac で Docker（OrbStack）が動いている必要がある

追記 2026-11-07（同日、$7 Micro 1 GB へ上げた。上の「1 GB に上げたら行を消して既定に戻す」を改める）:
- Nano でデプロイ 13 分後に available 154 MB・swap 335 MB（基準②の 300 MB 超え）。`vmstat` で so は 0 だが si が 130〜420 KB/s 続き、
  web コンテナの大半が swap に追い出されたまま読み戻していた。平常時も swap 頼みになると見て、runbook §0 4-c で Micro（`dopafeed-tokyo-2`）へ移した
- Micro での実測（deploy 直後、async・YJIT 無しのまま）: 使える総量 909 MB、available 400 MB、swap 21 MB、si は 14 KB/s ほど・so 0。
  web コンテナ 222 MB（Nano で 75 MB に見えたのは swap に出ていたぶんを数えていなかったため）、kamal-proxy 6 MB
- async と YJIT 無しは 1 GB でも当面残す。fork（Ruby プロセスが 4 本増える）と YJIT を戻すかは、しばらく使って `free -m` と体感を見てから別に決める
- `servers.web` は IP でなく `dopafeed.dev` を書く。サーバーを作り直して IP が変わっても A レコードを直すだけでコミットが要らず、
  プレースホルダの IP を置き換え忘れることもない（DNS only なので IP を隠す効果は無い）。AAAA を置くなら、作り直しで IPv6 が変わるたびに書き換え、
  ファイアウォールの IPv6 の 22 番も IPv4 と同じく絞る（ssh が IPv6 を先に試す）
