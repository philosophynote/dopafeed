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
   3. 追加したアイコンから開き直し、下のボタンで通知を許可
4. ボタン「通知を許可する」（standalone で開いたときだけ有効。Push の購読を作り、サーバーに保存）
5. 注記「Safari のタブのままでは通知もバッジも使えません。ホーム画面から開いた時だけ有効になるのが iOS の仕様です」（固定）
6. 「届く通知（1 日最大 2 件）」の例 3 枚（固定文。時刻は未決 1）
   - 7:30「今日の掘り出し物 3 本が届きました」→ タップで「あなた向け」
   - reset_hour の H 時間前（H = 提案鍵 `push.streak_warning_hours_before`。reset_hour 4 で H = 3 なら 01:00）「3 日連続が H 時間後に消えます」→ あと 1 本読めば継続（ストリークは `daily_goal.reset_hour` で切り替わるので、警告時刻はそこから導く。モックの 21:00 は reset_hour 4 と矛盾する。未決 7。ストリークの定義は daily_goal.md の未決 6）
   - たまに「激レアが出現しました（+50 XP）」

## 遷移
- Learning（第一の陣では Unit 5 の最小版: サインアウト + ここへの導線）→ Install
- Install → Learning（戻る）
- 通知をタップ → Main（または ForYou。第一の陣では Main）

## 受け入れ条件（Given-When-Then）
- Given Safari のタブで開いている（display-mode: browser）When Install を開く Then 手順 3 段が出て「通知を許可する」は無効で、注記が出る（判定は Stimulus が `matchMedia('(display-mode: standalone)')` と `navigator.standalone` を見る。システムテストでは execute_script で両方をスタブ。未決 6）
- Given ホーム画面から開いている（display-mode: standalone）When Install を開く Then 「通知を許可する」が有効
- Given standalone で「通知を許可する」When 許可した Then PushSubscription（endpoint, p256dh, auth）がサーバーに保存され、ボタンが「通知は有効」に変わる
- Given 許可済み When Install を再度開く Then 「通知は有効」のまま、再購読しない（冪等）
- Given 拒否した When Install を開く Then 「iOS の設定から通知を許可してください」が出る
- Given 未読が 48 When standalone で開く Then navigator.setAppBadge(48) が呼ばれる（システムテストでは execute_script で setAppBadge を呼び出し記録用のスタブに置き換えて検証。service worker 側でも再設定。未決 2）
- Given 未読が 0 When standalone で開く Then clearAppBadge が呼ばれる（同じスタブで検証）
- Given manifest When /manifest を開く Then name, icons（180 / 512）, display: standalone, start_url: / が返る
- Given service worker When /service-worker を開く Then 本文に push と notificationclick のイベント登録が含まれる（コントローラテストで文字列検査。実行はしない）
- Given VAPID 鍵 When サーバーが Push を送る Then web-push gem で送り、410 が返った購読は削除する

## 使う設定の鍵
dopamine.yml: 通知の時刻・上限は鍵が無い（未決 1）
personas.yml: なし

## 外部 API
あり。Web Push（web-push gem は Unit 0 で Gemfile に入れた。VAPID 鍵の管理と送信 Job の設計は Unit 10 で ADR を足す）。Job 名: `Push::MorningDigestJob`, `Push::StreakWarningJob`（仮）。
テストは WebMock で endpoint への POST をスタブ（200 と 410 の 2 通り。カセットは使わない）。

## 未決
1. 通知の時刻（7:30）、1 日最大 2 件、ストリーク警告「3 時間前」。dopamine.yml に鍵が無い。提案: `push.digest_at: "07:30"`, `push.streak_warning_hours_before: 3`, `push.daily_max: 2`。通知は 3 種あるので上限 2 件のときどれを落とすか（案: 激レア通知を優先し、ダイジェストと警告のうち後の方を落とす）
2. バッジは OS が永続化しない（再起動で消える）ので、service worker の push / activate で setAppBadge を再実行する。pwa-ios Skill に従う
3. VAPID 鍵の置き場所（Rails credentials。runbook に追記）
4. 第一の陣では「朝のダイジェスト」の 3 本選定（Claude の Sonnet）が無い。新着 3 本で代替するか、Push 自体を第二の陣に回すか
5. アプリアイコンの画像（180×180 / 512×512）を誰が作るか
6. standalone 判定のテスト方法。iOS Safari の `navigator.standalone` と標準の `matchMedia('(display-mode: standalone)')` の両方を見る。Selenium では CDP の `Emulation.setEmulatedMedia` が使えなければ execute_script でスタブ
7. ストリーク警告の時刻。reset_hour（4 時）の 3 時間前は 01:00 で、深夜に通知が鳴る。モックの 21:00 を採るなら文言を「今日中に 1 本読めば継続」に変え、「H 時間後に消えます」は出さない。どちらにするかは nao が決める
