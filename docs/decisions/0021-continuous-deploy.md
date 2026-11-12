# ADR 0021: main へのマージで GitHub Actions が本番へデプロイする
日付: 2026-11-12 状態: 採用（#88。nao の実装指示書を正とし、計画を承認）。0003 の「`kamal deploy` は nao が Mac から打つ」「22 は Mac の IP だけ」「レジストリは localhost:5555」「`servers.web` は dopafeed.dev」を改める

## なぜ
本番に出す手段が Mac の `kamal deploy` だけで、Mac と OrbStack が手元に無いと出せなかった。PR を iPhone でマージしても本番は古いまま。
22 番を Mac の IP だけに絞っていたので、モバイルルーターを替えるたびにファイアウォールを直す必要があった（2026-11-08 に一度止まった）。

## 決めたこと
- **流れ**: main への push で `deploy.yml` が `ci.yml` を `workflow_call` で呼び、通ったら同じ run の deploy ジョブが `bin/kamal deploy` を打つ。CI が検証した commit をそのまま配る。`ci.yml` の `push: main` は外し、main で CI が二度走らないようにする
- **入口**: runner はジョブの間だけ Tailscale の使い捨てノード（`tag:ci`）として tailnet に入り、サーバー（`tag:prod`）の OpenSSH に繋ぐ。policy は `autogroup:member` と `tag:ci` から `tag:prod` の 22 番だけ。Tailscale SSH・Serve・Funnel は使わない（2026 年の脆弱性公告がこの機能に集中した）。サーバーの Tailscale は 1.104.4 以上、自動更新
- **Tailscale の認証**: workload identity federation（GitHub の OIDC）。subject は `repo:philosophynote/dopafeed:environment:production`。Tailscale の秘密を GitHub に置かない
- **レジストリ**: GHCR（`ghcr.io/philosophynote/dopafeed`）。CI は `GITHUB_TOKEN`、Mac は `write:packages` の PAT。パッケージは public（private は無料枠の転送が月 1 GB で、サーバーの pull で数回のうちに尽きる。中身は public なリポジトリのコードと gem で、master.key は `.dockerignore` で外れる）
- **宛先**: `servers.web` は `DEPLOY_HOST`（サーバーの Tailscale IP）を ERB で読む。IP をリポジトリに載せない（nao の希望）。CI は Environment の変数、Mac は `~/.zshrc` で渡す。DNS と `proxy.host` は dopafeed.dev のまま
- **秘密**: Environment `production`（main のみ）に `RAILS_MASTER_KEY`・`SSH_PRIVATE_KEY`（デプロイ専用の ed25519）・`TS_OAUTH_CLIENT_ID`、変数に `TS_AUDIENCE`・`DEPLOY_HOST`。Repository secrets には置かない。`.kamal/secrets` は既存の行を残して `KAMAL_REGISTRY_PASSWORD` を 1 行足すだけ。CI は `config/master.key` を書き、既存の `credentials:fetch` をそのまま動かす
- **二重実行**: deploy と rollback で concurrency `production-deploy` を共有し、途中で取り消さない。Mac から同時に打った時は Kamal のロックで片方が止まる。失敗時の `kamal lock release` は workflow に置かない（指示書から変えた）。Kamal は例外で抜ける時に自分のロックを外す。外から release すると、Mac が持つロックで弾かれた時にそれを奪ってしまう
- **戻し方**: `rollback.yml`（`workflow_dispatch`、戻す版はサーバーに残るコンテナのもの）。Mac の `kamal rollback` も使える
- **22 番**: 自動デプロイと Mac からの Tailscale 経由の両方が通ってから、公開側の 22 番を閉じる。Lightsail ブラウザ SSH の分だけ残せるなら残す（Tailscale が落ちた時の退路）
- **承認ボタンは付けない**: マージが承認。Environment の Required reviewers を足すと、同じ判断を二度押すことになる
- **エージェントは起こさない**: エージェントが本番を動かせるのは nao のマージを通してだけ。Deploy / Rollback の手動実行もしない（AGENTS.md の禁止）

## 採らなかった案
- **22 番を全世界に開ける**: 鍵だけでも守れるが、総当たりが常に来る。Tailscale の手間が小さかった
- **ジョブの間だけ Lightsail の 22 番を runner の IP に開ける（AWS CLI ＋ OIDC）**: 新しい常駐は要らないが、`put-instance-public-ports` は規則の全置換、閉じる時に Mac の規則まで消す恐れ、runner が落ちると開きっぱなし
- **ECR**: AWS の権限を Mac にも要る。GHCR は GitHub の権限で閉じる
- **localhost:5555 の続投**: 秘密は増えないが、イメージが tailnet 越しの SSH トンネルを流れ、Mac から打つ時は OrbStack の registry が要るまま

## 費え
tailscaled は RSS 37 MB（2026-11-12 実測、available 391 MB、vmstat の si・so はほぼ 0）。手順は docs/runbook.md §4
