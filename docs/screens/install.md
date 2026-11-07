# Install（Unit 10）

## 目的
外部トリガーの入口。ホーム画面に追加した PWA からだけ Web Push とアイコンのバッジが使える（iOS 16.4+）。
ウィジェットは作れないので、開かなくても数字が目に入る仕組みをバッジで再現する。

## 要素
1. ヘッダ: 「設定に戻る」（→ Learning）、「ホーム画面に追加」
2. アイコンのプレビューにバッジ「48」（DB: 未読数）。「アイコンに未読数が出ます」「ウィジェットの代わり。… Badging API で再現します」（固定）
3. 「手順（iOS 16.4 以降）」3 段（固定）
   1. Safari の共有ボタンをタップ
   2. 「ホーム画面に追加」を選ぶ
   3. 追加したアイコンから開き直し（ホーム画面のアプリは Safari と Cookie を共有しないのでログインをもう一度）、下のボタンで通知を許可
4. ボタン「通知を許可する」（standalone で開いたときだけ有効。Push の購読を作り、サーバーに保存。Unit 10a では無効のまま置き、10b で動かした）
5. 注記「Safari のタブのままでは通知もバッジも使えません。ホーム画面から開いた時だけ有効になるのが iOS の仕様です」（固定）
6. 「届く通知（1 日最大 2 件）」の例 3 枚（固定文。時刻は未決 1）
   - `push.digest_at`（提案 07:30）「今日の掘り出し物 3 本が届きました」→ タップで「あなた向け」（第一の陣は「今日の新着 3 本」→ Main。未決 4）
   - `push.streak_warning_at`（提案 21:00）「N 日連続が切れます。{reset_hour} 時までに 1 本」→ あと 1 本読めば継続（未決 7 で決定。モックの「H 時間後に消えます」は出さない。ストリークの定義は daily_goal.md の未決 6）
   - たまに「激レアが出現しました（+N XP）」（N = その tier の `xp.base` × multiplier。激レアの tier が yml に無い間はこの通知自体を出さず、画面の例も 2 枚。jackpot.md の未決 4）

## 遷移
- Learning（第一の陣では Unit 5 の最小版: サインアウト + ここへの導線）→ Install
- Install → Learning（戻る）
- 通知をタップ → Main（または ForYou。第一の陣では Main）

## 受け入れ条件（Given-When-Then）
- Given Safari のタブで開いている（display-mode: browser）When Install を開く Then 手順 3 段が出て「通知を許可する」は無効で、注記が出る（判定は Stimulus が `matchMedia('(display-mode: standalone)')` と `navigator.standalone` を見る。システムテストでは CDP で両方をスタブ。未決 6）
- Given ホーム画面から開いている（display-mode: standalone）When Install を開く Then 「通知を許可する」が有効
- Given standalone で「通知を許可する」When 許可した Then PushSubscription（endpoint, p256dh, auth）がサーバーに保存され、ボタンが「通知は有効」に変わる
- Given 許可済み When Install を再度開く Then 「通知は有効」のまま、再購読しない（冪等。端末の購読をサーバーに保存し直すだけ。同じ endpoint なので行は増えない。サーバーの鍵と違う鍵の購読は解除してボタンを有効に戻す）
- Given 拒否した When Install を開く Then 「iPhone の設定から通知を許可してください」が出て、ボタンは無効（Notification.permission が denied。許可のダイアログは一度拒否すると二度と出ないので、設定へ誘導するしかない）
- Given 未読が 48 When standalone で開く Then navigator.setAppBadge(48) が呼ばれる（システムテストでは CDP で setAppBadge を呼び出し記録用のスタブに置き換えて検証。service worker 側でも再設定。未決 2）
- Given 未読が 0 When standalone で開く Then clearAppBadge が呼ばれる（同じスタブで検証）
- Given manifest When /manifest を開く Then name, icons（180 / 512）, display: standalone, start_url: / が返る
- Given service worker When /service-worker を開く Then 本文に push と notificationclick のイベント登録が含まれる（コントローラテストで文字列検査。実行はしない）
- Given VAPID 鍵 When サーバーが Push を送る Then web-push gem で送り、410（失効）か 404（無効）が返った購読は削除する。endpoint が内部ネットワークを指す購読は送らずに削除する（HttpGet と同じ判定。#68 の Codex 指摘）。5xx・429・接続エラーは行を残して次の回に送り直す
- Given push.digest_at を過ぎた読書日 When Push::DispatchJob が回る Then 24 時間以内に届いた未読があれば、その本数を題に、新しい順に push.digest_articles 本の見出しを本文にしたダイジェストを印の無い購読に送り、digest_sent_on にその読書日を書く。同じ読書日に二度は送らない。新着が無い回は送らず印も書かない（後で届けばその日のうちに送る）
- Given push.streak_warning_at を過ぎた読書日 When Push::DispatchJob が回る Then 昨日まで連続が続いていて今日がまだ 0 本なら「N 日連続が切れます。{reset_hour} 時までに 1 本」を送り、streak_warning_sent_on に書く。今日 1 本でも読んでいれば送らない。昨日も 0 本（切れた後）なら送らない
- Given 通知 When タップする Then 開いているアプリがあれば前に出して Main へ、無ければ開く。受信のたびに setAppBadge(未読数)（0 なら clearAppBadge）で書き直す

## 使う設定の鍵
dopamine.yml: `push.digest_at` / `push.streak_warning_at`（未決 1 の決定。nao が足すまで無く、無い間は画面に時刻を出さず、送らない）、`push.digest_articles`（ダイジェストの本文に載せる見出しの本数。10c で提案。無い間は題だけ）、`daily_goal.reset_hour`（警告の文言）、`fetch.timeout_seconds`（Push サービスへの接続と読み取りの待ち時間）
personas.yml: なし

## 外部 API
あり。Web Push（web-push gem。VAPID 鍵の管理と送信の設計は ADR 0013）。Job は `Push::DispatchJob` 1 つ（config/recurring.yml で 10 分おき）で、通知の文面は `Push::Digest` / `Push::StreakWarning`、送信は `Push::Sender`。
テストは WebMock で endpoint への POST をスタブ（201・410・404・503・429・タイムアウト。暗号化と署名は本物の鍵で通す。カセットは使わない）。

## 未決
1. 通知の時刻（7:30）、1 日最大 2 件、ストリーク警告「3 時間前」。dopamine.yml に鍵が無い。提案: `push.digest_at: "07:30"`, `push.streak_warning_hours_before: 3`, `push.daily_max: 2`。通知は最大 3 種（激レア通知は tier が入ったときだけ）なので上限 2 件のときどれを落とすか（案: 激レア通知を優先し、ダイジェストと警告のうち後の方を落とす）
    → **決定（#63、nao 承認、ADR 0013）**: 鍵は `push.digest_at: "07:30"` と `push.streak_warning_at: "21:00"` の 2 つ（引用符付き。裸の 07:30 は YAML で六十進数の 27000 になる）。`streak_warning_hours_before` と `daily_max` は採らない（2 種 × 1 日 1 回で上限 2 は構造で守られる）
2. バッジは OS が永続化しない（再起動で消える）ので、service worker の push / activate で setAppBadge を再実行する。pwa-ios Skill に従う
    → **決定（Unit 10a、#63）**: ページを描くたびに Stimulus `badge`（layout の見えない `#app-badge`）が `setAppBadge(未読数)`、0 なら `clearAppBadge` を呼ぶ。未読が変わる Turbo Stream（興味なし・読了）は `#app-badge` も差し替えて追随させる。iOS では通知を許可したホーム画面のアプリでしか反映されないので、実機では 10b の「通知を許可する」の後に初めて出る（システムテストの検証は「呼んだ」ことまで）。service worker 側の再設定は Push の受信（10c）で入れた: サーバーが payload に `unread`（未読の総数）を載せ、service worker が push のたびに setAppBadge / clearAppBadge を呼ぶ
3. VAPID 鍵の置き場所（Rails credentials。runbook に追記）
    → **決定（#63、nao 承認、ADR 0013）**: ENV（`VAPID_PUBLIC_KEY` / `VAPID_PRIVATE_KEY` / `VAPID_SUBJECT`）。ANTHROPIC_API_KEY と同じく config/deploy.yml の env.secret → .kamal/secrets。作り方と交換は docs/runbook.md 2-h。鍵が無いサーバーでは Install が「鍵が無い」を出し、購読は 503 で受けない
4. 第一の陣では「朝のダイジェスト」の 3 本選定（Claude の Sonnet）が無い。新着 3 本で代替するか、Push 自体を第二の陣に回すか
    → **決定（#63、nao 承認）**: 新着の未読 3 本の見出しで代替し、タップ先は Main。Claude の選定は ForYou の Unit で差し替える
5. アプリアイコンの画像（180×180 / 512×512）を誰が作るか
    → **決定（Unit 10a、#63）**: 橙（#f97316）に白の「D」の仮アイコンを置いた（public/icon.png 512、public/icon-180.png、public/icon.svg）。本物は nao が同じファイル名で差し替える
6. standalone 判定のテスト方法。iOS Safari の `navigator.standalone` と標準の `matchMedia('(display-mode: standalone)')` の両方を見る。Selenium では CDP の `Emulation.setEmulatedMedia` が使えなければ execute_script でスタブ
    → **決定（Unit 10a、#63）**: CDP の `Page.addScriptToEvaluateOnNewDocument` で、文書ごとに `navigator.standalone = true` と `setAppBadge` / `clearAppBadge` の記録用スタブを先回りで入れる（spec/system/install_spec.rb）。ページの JS より先に走るので execute_script の後追いより確実。例の後に外す
7. ストリーク警告の時刻。reset_hour（4 時）の 3 時間前は 01:00 で、深夜に通知が鳴る。モックの 21:00 を採るなら文言を「今日中に 1 本読めば継続」に変え、「H 時間後に消えます」は出さない。どちらにするかは nao が決める
    → **決定（#63、nao 承認）**: 21:00 固定（鍵 `push.streak_warning_at` を提案）。文言は「N 日連続が切れます。{reset_hour} 時までに 1 本」。「H 時間後に消えます」は出さない
