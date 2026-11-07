# ADR 0013: Web Push は VAPID 鍵を ENV に置き、購読は端末ごとに 1 行、送信は 1 日 1 回の印で守る
日付: 2026-11-07 状態: 採用（#63）

nao の決定（2026-11-06、#63 の計画を推奨どおり承認）。docs/SPEC.md「外部トリガー」と install.md の未決 1・3・4・7 の答え。

- **アプリは VAPID 鍵を ENV から読む**（`VAPID_PUBLIC_KEY` / `VAPID_PRIVATE_KEY` / `VAPID_SUBJECT`）。実値の置き場は credentials の `vapid:`（runbook 0-3 の DOPAFEED_USER_* / LITESTREAM_* と同じ）で、`.kamal/secrets` が deploy 時に `credentials:fetch` して env.secret で渡す。コードが credentials を直接読まないのは、既存の秘密と経路を揃え、master.key に触れないエージェントでもテストと開発で鍵の有無を切り替えられるため。3 つ揃っていなければ「無い」と扱い（`Push::Vapid`）、Install は「サーバーに通知の鍵がありません」を出し、購読の POST は 503 で受けない。鍵の生成と交換は docs/runbook.md 2-h。鍵を変えると既存の購読は全部無効になるので、行を消して Install で許可し直してもらう（Install は鍵の違う購読を見つけると解除する）
- **購読は `push_subscriptions` に 1 端末 1 行**（endpoint 一意、p256dh、auth、user_agent）。一人用なので user_id は持たない（ADR 0006）。同じ endpoint が来たら鍵を上書きする（ブラウザが鍵を作り直したとき）。拒否・失効した購読（送信で 404 / 410）は送る側が消す
- **許可のダイアログはボタンのタップからだけ出す。** iOS はユーザー操作の無い `Notification.requestPermission()` を無視し、一度拒否すると二度と出ない。開いたときは状態を見るだけ（granted かつ購読があれば「通知は有効」、denied なら設定へ誘導）で、勝手に購読し直さない
- **通知は 2 種、各 1 日 1 回。** 朝のダイジェスト（第一の陣は新着の未読 3 本の見出し。Claude の選定は ForYou で差し替える）とストリークの警告（21:00 固定。reset_hour の 3 時間前は深夜になるので採らない。文言は「N 日連続が切れます。{reset_hour} 時までに 1 本」）。時刻は dopamine.yml の `push.digest_at` / `push.streak_warning_at`（nao が足す。無い間は送らず、画面にも時刻を出さない）。**値は `"07:30"` と引用符付きで書く**: 裸の `07:30` は YAML 1.1 の六十進数として 27000 に読まれる（`Dopamine.clock_time` はその形も「07:30」に戻すが、頼らない）。`push.daily_max` は持たない: 2 種 × 1 回で上限 2 は構造で守られる。激レア通知は tier が yml に入ってから
- **送信は 10 分おきの 1 つの Job（`Push::DispatchJob`）と、購読ごとの `digest_sent_on` / `streak_warning_sent_on`。** 時刻を過ぎていて今日の印が無い購読に送って読書日を書く。遅れても同じ読書日なら送る（止まっていた朝の分が昼に届くのは許す）。印は送れたときだけ書き、失敗した端末には次の回に送り直す。通知が「今日は出さない」と決めた回（新着の無い朝、今日すでに読んだ夜）は送らずに印だけ書いてその日を閉じる（後から新着が入っても深夜に鳴らさない）。recurring.yml に時刻を二重に書かないための形。ダイジェストの本文に載せる見出しの本数は `push.digest_articles`（無い間は題だけ）
- **endpoint は送る直前に `HttpGet` と同じ内部ネットワークの判定を通す**（`HttpGet.verify_external!`）。endpoint は端末が申告した URL で、POST の宛先として信用しない（#68 の Codex 指摘）。内側を指す購読は送らずに消す。消すのは購読そのものが使えないと分かったとき（410 / 404 / 401 / 403 / 内部アドレス / 暗号化に使えない鍵）だけで、サーバー側の VAPID 鍵が読めないときは 1 行も消さずに止める。web-push が名前を引き直すので DNS rebinding までは防げないが、Push サービスは固定の大手ホストで、申告の時点で弾くのが役目。Push サービスへの接続と読み取りの待ち時間は `fetch.timeout_seconds` に揃える（web-push の既定 60 秒で Job を止めない）
- **バッジは通知の許可の後でしか出ない（iOS）。** Install はその順で案内する。service worker は push の受信時に `setAppBadge(未読数)` を書き直す（OS が再起動で消すため）
