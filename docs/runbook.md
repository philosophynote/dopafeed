# Dopafeed 運用手帳（runbook）

対象: 本番（Lightsail 1 台、Kamal、SQLite + Litestream）。コマンドは nao が Mac から打つ。エージェントは打たない。

## 0. 初回デプロイの前に（一度だけ）
1. S3 バケットを作る（例: `dopafeed-litestream`、東京）。パブリックアクセスは全部ブロック（新規バケットの既定のまま）。
   バージョニングは必須ではないが、Litestream 公式はベストプラクティスとしている。有効にすると漏えいキーによる削除・上書きから
   古い版を戻せる（手順 2 のポリシーに `DeleteObjectVersion` は無い）。
   有効にするなら**ライフサイクル規則を同時に作る**。Litestream は `retention`（72h）を過ぎた WAL を `DeleteObject` で消すが、
   バージョニング下では削除マーカーが付くだけで非現行版は残り、ポリシーに `DeleteObjectVersion` が無いので Litestream 自身も
   物理削除できない。規則が無いと WAL の全履歴が永久に溜まる。規則は「非現行版を 30 日で失効」＋「期限切れ削除マーカーを削除」。
   30 日は 2-g で漏えいに気づくまでの猶予。付けないならバージョニングは切る側に倒し、その理由をここに書き残す
2. そのバケットだけに権限を持つ IAM ユーザーを作り、アクセスキーを発行する。ポリシーはリソースを 2 段に分ける（Litestream 公式 S3 ガイドの形）:
   - `arn:aws:s3:::<バケット>` に `s3:ListBucket` と `s3:GetBucketLocation`
   - `arn:aws:s3:::<バケット>/*` に `s3:GetObject` / `s3:PutObject` / `s3:DeleteObject`
   このユーザーにコンソールパスワードは作らない（CLI 専用）。2-g の `aws iam ...` はこのユーザーでは打てないので、
   Mac の AWS CLI は管理用の身元（IAM Identity Center か管理用 IAM ユーザー）で動かす
2-a. CloudTrail でこのバケットの S3 データイベントを記録しておく（2-g で「漏えいした鍵が何をしたか」を見るため）。
   トレイルを作り、イベントタイプで「データイベント」→ S3 を選び、対象を `dopafeed-litestream` だけに絞る。
   トレイルは既定で管理イベントしか記録せず、S3 の Get/Put/Delete は「イベント履歴」にも出ない。後から有効にしても過去は見えない。
   費用は 10 万イベントあたり $0.10 で、Litestream の PUT 頻度なら月 $0.1 前後 + ログ保存の S3 代
3. 実値は Rails の暗号化 credentials に入れる。平文を永続保存せず、git にも入れない。
   鍵は既にある `config/master.key`（git 外）だけで、`config/credentials.yml.enc` は暗号化されたまま git に入る。
   `credentials:edit` は復号した内容を一時ファイルに書いてエディタで開き、閉じると消す。Zed で開くときは
   `--wait` を付ける（無いと Zed が即座に戻り、編集前に Rails が一時ファイルを読んで閉じる）。
   ```sh
   EDITOR="zed --wait" bin/rails credentials:edit
   ```
   バックアップやクラウド同期をするエディタでは一時ファイルが残りうる。Zed はしないので、そのまま使ってよい。
   開いたエディタに足す:
   ```yaml
   dopafeed:
     user_email: nao@example.com
     user_password: "..."
   litestream:
     access_key_id: "AKIA..."
     secret_access_key: "..."
   ```
   `.kamal/secrets` に 4 行足す（このファイルは git に入っているが、値は `kamal` 実行時に Mac 上で復号して取る）:
   ```sh
   DOPAFEED_USER_EMAIL=$(bin/rails credentials:fetch dopafeed.user_email)
   DOPAFEED_USER_PASSWORD=$(bin/rails credentials:fetch dopafeed.user_password)
   LITESTREAM_ACCESS_KEY_ID=$(bin/rails credentials:fetch litestream.access_key_id)
   LITESTREAM_SECRET_ACCESS_KEY=$(bin/rails credentials:fetch litestream.secret_access_key)
   ```
   `bin/rails credentials:fetch` は mise の Ruby が要るので、`kamal` は mise が効いているシェルで打つ。
   確認は値を端末に出さずに行う（`kamal secrets print` 単体は値をそのまま表示するので使わない）:
   ```sh
   kamal secrets print | sed -E 's/=.+/=(set)/; s/=$/=(EMPTY!)/'
   ```
   `DOPAFEED_*` / `LITESTREAM_*` の 4 行が `(set)` なら OK（`RAILS_MASTER_KEY` と、4-a-5 で足す `KAMAL_REGISTRY_PASSWORD` も並ぶ）。
   `(EMPTY!)` は credentials のキー名の打ち間違い。
   別案: macOS のキーチェーン（`security add-generic-password -a dopafeed -s LITESTREAM_SECRET_ACCESS_KEY -w` で入れ、
   `.kamal/secrets` で `$(security find-generic-password -a dopafeed -s LITESTREAM_SECRET_ACCESS_KEY -w)`）。どちらも平文ファイル無し。
   DOPAFEED_USER_* は初回起動の `db:prepare` が seed でログインユーザーを 1 件作るときに読む。
   production では既定値が無いので、未設定だと `KeyError` でコンテナが上がらない（意図どおり）。
   2 回目以降の起動では seed は走らない（ユーザーが居れば触らない）
4. `config/deploy.yml` の `LITESTREAM_BUCKET` / `LITESTREAM_REGION` を実際の値にする
4-a. Lightsail を作る（ADR 0003: $7 Micro 1 台）
   1. インスタンス: リージョンは東京（S3 と同じリージョンで遅延が小さい。Lightsail の転送枠は S3 向けも、IN も OUT も消費するので
      安くはならない）、Linux、ネットワークタイプは「デュアルスタック」（IPv6 専用だと静的 IPv4 が付かず、4-b の A レコードも
      Mac からの SSH も成立しない。IPv6 専用の価格表示は $2 安く出るので見間違えない）、ブループリントは「OS のみ」の Ubuntu 24.04 LTS、
      プランは $7 の Micro（1 GB / 2 vCPU / 40 GB / 転送 2 TB）。$5 は Nano で 0.5 GB / 20 GB しか無いので選ばない。
      Lightsail 独自の初月無料トライアルは廃止済み。2025 年 7 月 15 日以降に作った AWS アカウントならクレジット方式の
      Free Tier が充当されうるが、無料になる前提で予算を組まない。
      インスタンス名は作成後に変えられないので決めて付ける（例: `dopafeed-tokyo-1`）。
      x86 なので `builder.arch: amd64` のまま（公式に明記は無い。初回 SSH 時に `uname -m` が `x86_64` を返すのを見る）。
      SSH キーは自分の公開鍵（`~/.ssh/id_ed25519.pub` など）を「Upload key」で登録する。Kamal が Mac の ssh と同じ鍵探索で繋がり、
      AWS 生成の秘密鍵を保管しなくて済む
   2. 静的 IP を作ってアタッチし、`config/deploy.yml` の `servers.web` に書く（再起動で IP が変わらないように）。
      アタッチ中は無料、外して 1 時間を超えると $0.005/時。1-a でサーバーを作り直すときは古い方から外してすぐ新しい方に付ける
   3. ファイアウォール（インスタンスの「ネットワーキング」タブ）:
      - 80 / 443 は「任意の IPv4 アドレス」で公開（443 は既定に無いので足す）。80 は Let's Encrypt の発行と
        HTTP → HTTPS 転送に要るので閉じない
      - 22 は既定の「任意の IPv4 アドレス」ルールを削除し、管理用 Mac の接続元 IP だけを許可するルールを作る
        （「IP アドレスに制限」にチェック、`curl -4 https://checkip.amazonaws.com` で出た IP を入れる）。
        追加だけでは絞れない。同じポートに複数ルールがあると最も緩いものが勝つので、既定ルールは必ず消す。
        作り直すとき「Lightsail ブラウザ SSH を許可」のチェックは付けたままにする（下の退路に使う）。
        `kamal` も Mac から SSH するので、この IP 以外からはデプロイもできない。外出先から打つなら先にルールの IP を変える
      - IPv6 は既定で有効（2021 年 1 月 12 日以降に作ったインスタンスは全部）。IPv6 ファイアウォールにも 22 / 80 が
        「任意の IPv6 アドレス」で生えているので、IPv4 と同じく 22 の既定ルールを消す。残すなら Mac の IPv6 だけに絞る。
        checkip.amazonaws.com は IPv6 非対応（AAAA 無し。`curl -6` でも IPv4 が返る）なので `curl -6 https://ifconfig.co` で取る。
        IPv6 を使わないなら「ネットワーキング」タブで IPv6 自体を無効にしてもよい。80 / 443 は IPv6 も公開でよい
      - 回線が変わって 22 に入れなくなったら、Lightsail コンソールの「ブラウザベースの SSH」から入ってルールの IP を直す。
        ブラウザ SSH は SSH ルールの「Lightsail ブラウザ SSH を許可」で通していて、送信元 IP の制限は受けない。
        ただしチェックを外すか 22 のルールを全部消すと入れなくなる。その場合はコンソールでルールを作り直す
   4. SSH ユーザーは `ubuntu`（root ではない）。`config/deploy.yml` の `ssh.user: ubuntu` を有効にしておく。
      Kamal は root 以外では Docker を自動インストールしないので、先に入れる:
      ```sh
      ssh ubuntu@<静的IP>
      curl -fsSL https://get.docker.com | sudo sh && sudo usermod -aG docker ubuntu
      sudo fallocate -l 1G /swapfile && sudo chmod 600 /swapfile && sudo mkswap /swapfile && sudo swapon /swapfile
      echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
      ```
      swap は Puma + Solid Queue + Litestream + kamal-proxy が 1 GB に同居するための保険。一度ログアウトして docker グループを効かせる
   5. レジストリ: `config/deploy.yml` の `registry.server` を決める（例: `ghcr.io`、`username` は GitHub ユーザー名）。
      Kamal は push 先を `<registry.server>/<image>` で組むので、`image: dopafeed` のままだと `ghcr.io/dopafeed` になり
      ghcr に拒否される（ghcr は `ghcr.io/<owner>/<name>` を要求する）。`image:` を `<GitHubユーザー名>/dopafeed` に変える。
      `write:packages` の PAT を credentials に `registry.password` として入れ、`.kamal/secrets` に
      `KAMAL_REGISTRY_PASSWORD=$(bin/rails credentials:fetch registry.password)` を足し、`registry.password` の
      コメントを外す
4-b. ドメインを Cloudflare Registrar で取り、DNS は Cloudflare に置く（Lightsail の DNS ゾーンは使わない）
   1. 取得: Cloudflare ダッシュボード → Domain Registration → Register Domains で `dopafeed.net` を検索して購入する。
      Cloudflare は原価販売（レジストリ + ICANN 料金に上乗せ無し）で、.net は年 $12 前後、更新も同額。
      メール認証とカードが要る。無料プランでよい。自動更新は既定でオンなので切らない（切れるとオリジンが変わり、
      ホーム画面の PWA と Push の購読が全部無効になる）。WHOIS の個人情報は無料で非公開になる。
      新規登録から 60 日は他社へ移管できない。ネームサーバーは Cloudflare 固定で、登録中は他社 DNS に変えられない
   2. A レコード: Cloudflare の DNS → Records → Add record。Type `A`、Name `@`、IPv4 address は 4-a-2 の静的 IP、
      **Proxy status は「DNS only」（灰色の雲）**、TTL は Auto。
      Proxied（橙色の雲）にしない。kamal-proxy が Let's Encrypt の発行（80 番の HTTP-01）と HTTP → HTTPS 転送を
      自分で行う設計（ADR 0003）で、Cloudflare が TLS を終端すると発行経路も下の確認も Cloudflare の挙動に左右される。
      CDN / WAF が欲しくなったら SSL/TLS を Full (strict) にしてから切り替える別作業（ADR を足す）。
      4-a で IPv6 を残しているなら `AAAA` も同じく DNS only で足す。消したなら足さない。IPv6 アドレスは静的 IP のように
      固定できず、インスタンスを削除すると解放される。1-a で作り直したら AAAA を書き換える。
      AAAA を足したら `curl -6 -I https://dopafeed.net/up` が 200 を返すのを見る。Docker の公開ポートが IPv6 で待ち受けるかは
      daemon の ip6tables 設定に依存し、届かないと IPv6 優先の iPhone 回線で遅延や失敗が起きる。返らなければ AAAA を消す
   3. 反映確認: `dig +short dopafeed.net` が静的 IP を返す（数分で反映）。Cloudflare の IP が返るなら Proxied になっている
   4. `config/deploy.yml` の `proxy:` が `ssl: true` / `host: dopafeed.net` になっていることを確認する（既に書いてある）
   **TLS が有効で HTTP → HTTPS に転送されることを確認するまで、ログイン画面にパスワードを入力しない。**
   production.rb の `assume_ssl` は通信を暗号化しない。proxy が HTTP を通していると Rails は「HTTPS で届いた」と
   扱うため転送も起きず、送ったパスワードは平文で流れる（secure Cookie が落ちてログインが成立しないのは結果であって防御ではない）。
   確認: `curl -I http://<ドメイン>/up` が 301/308 で https へ、`curl -I https://<ドメイン>/up` が 200
5. `kamal config` で env が解決されることを確認し、`kamal build push` で Dockerfile（Litestream の COPY を含む）が通ることを確認
6. 初回は `kamal setup`（kamal-proxy の導入とデプロイをまとめて行う）、2 回目以降は `kamal deploy`。起動ログに `litestream` の `replicating to: name="s3"` が出れば複製が動いている

`LITESTREAM_BUCKET` / `LITESTREAM_REGION` が無いと server は起動しない（bin/docker-entrypoint）。バックアップ無しで静かに動くより止まるほうを選んでいる（ADR 0004）。

## 1. 復元

### 1-a. サーバーを作り直す（自動復元）
新しいインスタンスで §0 4-a の 1〜4 をやり直す（静的 IP は古い方から外して付け替える。`ssh.user: ubuntu` なので Kamal は
Docker を入れてくれない。swap とファイアウォールも手で入れる）。そのうえで `kamal setup`（デプロイを含む。`kamal deploy` を
別に打つ必要は無い）。volume が空なので entrypoint の
`litestream restore -if-db-not-exists -if-replica-exists` が S3 から `storage/production.sqlite3` を戻してから Puma が上がる。
cache / queue / cable の DB は複製していない。`db:prepare` が空で作り直す（キャッシュは消え、実行待ちジョブは失われる。recurring.yml の定期ジョブは次回また積まれる）。

### 1-b. 動いているサーバーの DB を最新の複製に戻す（手動）
```sh
kamal app stop
kamal app exec "litestream restore -config config/litestream.yml -o /rails/storage/restored.sqlite3 /rails/storage/production.sqlite3"
kamal app exec "mv /rails/storage/production.sqlite3 /rails/storage/production.broken.sqlite3 && mv /rails/storage/restored.sqlite3 /rails/storage/production.sqlite3"
kamal app start
```
`kamal app stop` の後は稼働コンテナが無いので `--reuse` は使えない。`--reuse` 無しの `kamal app exec` は
同じ image・env・volume で一時コンテナを起こして実行する（entrypoint は server 以外のコマンドを素通しする）。
`-o` を付けないと「既にファイルがある」で止まる。壊れた DB は消さず `.broken` で残す。

### 1-c. 特定の時刻に戻す（誤操作の取り消し）
```sh
kamal app stop
kamal app exec "litestream restore -config config/litestream.yml -timestamp 2026-10-23T03:00:00Z -o /rails/storage/restored.sqlite3 /rails/storage/production.sqlite3"
```
続きは 1-b と同じ（mv して `kamal app start`）。戻せる範囲は `config/litestream.yml` の `retention`（72h）。UTC で指定する。

### 1-d. 復元後の確認
```sh
kamal console
```
```ruby
[Feed.count, Article.count, User.count]   # 本番の初回起動直後は [0, 0, 1]（seed は User だけ。フィード・記事は dev/test 専用）
Article.maximum(:created_at)              # 復元後は「障害前に見えていた最新記事の時刻」と突き合わせる
```
復元の合否は件数の固定値ではなく、障害前の記憶（最新記事・XP）と比べて判断する。[0, 0, 1] は「空のバックアップから復元した」のではなく「まだ何も取り込んでいない」正常な状態でもありうる。

### 1-e. 複製が生きているかの確認
```sh
kamal app exec --reuse "litestream snapshots -config config/litestream.yml /rails/storage/production.sqlite3"
kamal app exec --reuse "litestream wal -config config/litestream.yml /rails/storage/production.sqlite3 | tail"
```
snapshots が一つも無い、wal の最新が何時間も前、なら複製が止まっている。`kamal logs | grep litestream` でエラーを見る。

## 2. ジョブ失敗の見方（Solid Queue）
ジョブは Puma の中で動く（`SOLID_QUEUE_IN_PUMA=true`）。別プロセスは無い。

### 2-a. まずログ
```sh
kamal logs -f | grep -E "SolidQueue|Error|\[claude\]"
```

### 2-b. 失敗したジョブの一覧
```sh
kamal console
```
```ruby
SolidQueue::FailedExecution.includes(:job).order(created_at: :desc).limit(20).map { |f|
  [f.job.class_name, f.job.arguments, f.error["exception_class"], f.error["message"]]
}
```

### 2-c. 直して再実行 / 捨てる
```ruby
SolidQueue::FailedExecution.find(ID).retry      # もう一度積む
SolidQueue::FailedExecution.find(ID).discard    # 諦める
SolidQueue::FailedExecution.find_each(&:retry)  # 全部やり直す（原因を直してから）
```

### 2-d. 「失敗」に見えて失敗でないもの
- **Claude の予算切れ**: `Claude::BaseJob` は `Claude::Budget::Exhausted` を `discard_on` している。FailedExecution には残らず、ログに `[claude] <Job> discarded: Claude daily call limit reached (200/200)` と出る。翌日（Time.zone の暦日）に自然に戻る。上限は config/dopamine.yml の `claude.daily_call_limit`。
  ```ruby
  Claude::Budget.new.used_today   # 今日の呼び出し数
  Claude::Budget.new.remaining
  ClaudeApiCall.where(created_at: Time.current.all_day).group(:purpose).count
  ```
- **recurring.yml の定期ジョブが二重に積まれていない**: `SolidQueue::RecurringTask.all` と `SolidQueue::RecurringExecution.count` で確認

### 2-e. 積まれたまま動かない
```ruby
SolidQueue::ReadyExecution.count      # 待ち
SolidQueue::ClaimedExecution.count    # 実行中（これが減らないならワーカーが死んでいる）
SolidQueue::Process.all               # 生きているワーカー。無ければ Puma を再起動: kamal app boot
```

## 2-f. パスワードを忘れたとき
パスワードリセットのメール（PasswordsMailer）は本番の配信設定（SMTP、`default_url_options` の host）が無く、Unit 15（Login）まで動かない。
一人用なので console で直す:
```sh
kamal console
```
```ruby
user = User.sole
user.update!(password: "新しいパスワード")
user.sessions.destroy_all   # 既存の Cookie を全部無効にする（Rails 標準のリセットも同じことをする）
```
パスワードを変えただけでは、盗まれた Cookie のセッションは生き残る。必ず `sessions.destroy_all` まで。

## 2-g. AWS アクセスキーの交換・漏えい対応
対象は Litestream 用 IAM ユーザー（§0 手順 2）の鍵。IAM ユーザーは鍵を同時に 2 本持てるので、通常の交換は複製を止めずにできる。
漏えい時は順番が逆で、止めるのが先、復旧が後。

### 通常の交換（年に一度程度）
1. 新キーを発行する。IAM コンソールの「セキュリティ認証情報」→「アクセスキーを作成」。旧キーは Active のまま
   ```sh
   aws iam create-access-key --user-name <IAMユーザー>    # CLI なら
   ```
2. credentials を新キーに書き換えてデプロイする。環境変数はコンテナ起動時に渡るので、コンテナを作り直さないと効かない。
   `kamal deploy` を使うのは、通常のデプロイと同じ経路（ビルド・push・起動）で動作確認を兼ねるため
   ```sh
   EDITOR="zed --wait" bin/rails credentials:edit         # litestream.access_key_id / secret_access_key
   kamal secrets print | sed -E 's/=.+/=(set)/; s/=$/=(EMPTY!)/'
   git add config/credentials.yml.enc && git commit -m "credentials: Litestream の鍵を交換"   # 暗号化済み。コミットしてよい
   kamal deploy
   ```
3. S3 複製が新キーで動いていることを確認する（1-e）。起動ログに `replicating to: name="s3"` が出て、
   `litestream snapshots` の最新時刻が今になっていればよい。記事を 1 件読むなど書き込みを起こし、`wal` が増えるのも見る
4. 旧キーを無効化し、数日置いてから削除する。無効化の前に旧キーの最終使用が切替前で止まっているのを見れば、複製を止めずに判定できる
   （最終使用の反映には遅れがあるので、切替直後の値は信用しない）。無効化で 1-e が赤くなったら旧キーがまだどこかで使われている。Active に戻して調べる
   ```sh
   aws iam get-access-key-last-used --access-key-id <旧AKIA>
   aws iam update-access-key --user-name <IAMユーザー> --access-key-id <旧AKIA> --status Inactive
   aws iam delete-access-key --user-name <IAMユーザー> --access-key-id <旧AKIA>   # 数日後
   ```

### 漏えいしたとき（疑いだけでも）
1. **旧キーを即 Inactive にする**（上の `update-access-key`、またはコンソール）。削除ではなく無効化。削除は不可逆で誤報だったときに
   戻せない（監査の面では差が無い。削除しても CloudTrail の記録には鍵 ID が残る）。この時点で S3 複製は止まるので、以降は急ぐ。
   AWS が先に検知していると IAM ユーザーに `AWSCompromisedKeyQuarantineV3` が付き、メールとサポートケースが来る。このポリシーは外さず
   ケースの指示に従う。同じユーザーでの鍵の作成・更新も拒否されるので、復旧は下の手順 2 で作り直す新ユーザーで行う
2. **一時認証情報を封じる**。`sts:GetSessionToken` は権限不要で呼べ、漏えいキーから最大 36 時間有効な一時認証情報を同じ権限で
   取られている可能性がある。鍵を Inactive にしても削除しても、発行済みの一時認証情報は無効にならない。
   利用者が Litestream だけなので、最短は **IAM ユーザーごと削除して作り直す**（ユーザーが消えれば一時認証情報の認証も失敗する）。
   新ユーザーに §0 手順 2 のポリシーを付けて新キーを発行する。ユーザーを残すなら `Deny *` のインラインポリシーを 36 時間付けておく
3. 被害を見る。IAM コンソールの「最終使用」（反映に遅れあり）と、§0 2-a で記録している S3 データイベントを Athena で（2-a はトレイルだけで CloudTrail Lake のイベントデータストアは作っていない）
   旧 AKIA について検索する。CloudTrail の「イベント履歴」には S3 の読み書きは出ない。出るのは管理イベントだけなので、そこでは
   旧 AKIA で `GetSessionToken` が成功していないか、許可外の API で AccessDenied が出ていないかを見る。
   権限はバケット 1 つの Get/Put/Delete/List なので、起きうるのは複製の読み出し・削除・**上書き（改ざん）** まで。
   `aws s3 ls s3://<バケット>/production.sqlite3/ --recursive --region ap-northeast-1`（管理用の身元で打つ。旧キーは Inactive）で、
   スナップショットと WAL が残っているか、LastModified が疑い時刻以降に不自然に動いていないか、サイズが異常でないかを見る。
   消されていたか書き換えの疑いがあるなら **S3 からは復元しない**。サーバー上の `storage/production.sqlite3` が唯一の正。
   `kamal app exec --reuse "sqlite3 /rails/storage/production.sqlite3 '.backup /rails/storage/emergency.sqlite3'"` で退避してから先へ進む。
   あわせて IAM のユーザー一覧に不審なユーザーや鍵が増えていないか、`aws iam list-access-keys --user-name <IAMユーザー>` で
   鍵が 2 本になっていないかも見る
4. 新ユーザーの鍵で通常の交換の 2〜3 を行い複製を復旧する。複製が止まっている間の書き込みは S3 に無い。
   改ざんの疑いがあったなら、復旧前に S3 の `production.sqlite3/` 配下を消して空から複製し直す（1-a の自動復元が汚染データを拾わないように）
5. 旧キーを削除する（旧ユーザーごと消したなら不要）。Inactive のまま残さない
6. 漏えい経路を塞ぐ。git の履歴に入っていたら `git log -p -S <AKIA>` で場所を特定し、履歴からも消して force push する
   （ローカルは `credentials:edit` の一時ファイルか `.kamal/secrets` の書き間違いが典型）。読まれたのが S3 の中身なら、
   そこには記事と読書ログしか無いが、`production.sqlite3` には `users.password_digest` と `sessions` が入っている。
   2-f の手順でパスワードを変え、セッションを全部破棄する

## 3. よく使う
```sh
kamal logs            # tail
kamal console         # rails console（alias）
kamal shell           # bash
kamal dbc             # sqlite3 の対話
```
