# Dopafeed 運用手帳（runbook）

対象: 本番（Lightsail 1 台、Kamal、SQLite + Litestream）。コマンドは nao が Mac から打つ。エージェントは打たない。

## 0. 初回デプロイの前に（一度だけ）
1. S3 バケットを作る（例: `dopafeed-litestream`、東京）。バージョニングは不要、パブリックアクセスは全部ブロック
2. そのバケットだけに `s3:GetObject / PutObject / DeleteObject / ListBucket` を持つ IAM ユーザーを作り、アクセスキーを発行
3. `.kamal/secrets` に 4 行足す（このファイルは git に入っているが値は ENV から取る）:
   ```sh
   DOPAFEED_USER_EMAIL=$DOPAFEED_USER_EMAIL
   DOPAFEED_USER_PASSWORD=$DOPAFEED_USER_PASSWORD
   LITESTREAM_ACCESS_KEY_ID=$LITESTREAM_ACCESS_KEY_ID
   LITESTREAM_SECRET_ACCESS_KEY=$LITESTREAM_SECRET_ACCESS_KEY
   ```
   そして Mac の環境変数に実値を置く（1Password CLI 経由でもよい）。
   DOPAFEED_USER_* は初回起動の `db:prepare` が seed でログインユーザーを 1 件作るときに読む。
   production では既定値が無いので、未設定だと `KeyError` でコンテナが上がらない（意図どおり）。
   2 回目以降の起動では seed は走らない（ユーザーが居れば触らない）
4. `config/deploy.yml` の `LITESTREAM_BUCKET` / `LITESTREAM_REGION` を実際の値にする
5. `kamal config` で env が解決されることを確認し、`kamal build push` で Dockerfile（Litestream の COPY を含む）が通ることを確認
6. `kamal deploy`。起動ログに `litestream` の `replicating to: name="s3"` が出れば複製が動いている

`LITESTREAM_BUCKET` / `LITESTREAM_REGION` が無いと server は起動しない（bin/docker-entrypoint）。バックアップ無しで静かに動くより止まるほうを選んでいる（ADR 0004）。

## 1. 復元

### 1-a. サーバーを作り直す（自動復元）
新しいサーバーに `kamal setup` → `kamal deploy` するだけ。volume が空なので entrypoint の
`litestream restore -if-db-not-exists -if-replica-exists` が S3 から `storage/production.sqlite3` を戻してから Puma が上がる。
cache / queue / cable の DB は複製していない。`db:prepare` が空で作り直す（キャッシュは消え、実行待ちジョブは失われる。recurring.yml の定期ジョブは次回また積まれる）。

### 1-b. 動いているサーバーの DB を最新の複製に戻す（手動）
```sh
kamal app stop
kamal app exec --reuse "litestream restore -config config/litestream.yml -o /rails/storage/restored.sqlite3 /rails/storage/production.sqlite3"
kamal app exec --reuse "mv /rails/storage/production.sqlite3 /rails/storage/production.broken.sqlite3 && mv /rails/storage/restored.sqlite3 /rails/storage/production.sqlite3"
kamal app start
```
`-o` を付けないと「既にファイルがある」で止まる。壊れた DB は消さず `.broken` で残す。

### 1-c. 特定の時刻に戻す（誤操作の取り消し）
```sh
kamal app exec --reuse "litestream restore -config config/litestream.yml -timestamp 2026-10-23T03:00:00Z -o /rails/storage/restored.sqlite3 /rails/storage/production.sqlite3"
```
戻せる範囲は `config/litestream.yml` の `retention`（72h）。UTC で指定する。

### 1-d. 復元後の確認
```sh
kamal console
```
```ruby
[Feed.count, Article.count, User.count]   # seed 直後なら [5, 30, 1]
Article.maximum(:created_at)              # 直近まで入っているか
```

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

## 3. よく使う
```sh
kamal logs            # tail
kamal console         # rails console（alias）
kamal shell           # bash
kamal dbc             # sqlite3 の対話
```
