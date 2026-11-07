# Login（Unit 15）

## 目的
自分専用だが公開 URL なのでログインが要る。ユーザーは 1 人。ログイン状態は長く保持し、普段この画面は出ない。

## 要素
1. 「DopaFeed」ロゴ、「自分専用。公開 URL なのでログインが要ります」（固定）
2. ボタン「パスキーでログイン（Face ID）」（未決 1。ADR 0005 はパスワード優先）
3. 「または」区切り
4. 「パスワード」入力（type=password）。メールアドレス欄はモックに無い（未決 2）
5. ボタン「ログイン」（→ Main）
6. 注記「ユーザーは 1 人だけ。… ログイン状態は 1 年保持するので、普段この画面は出ません」（固定。期間は未決 3）

## 遷移
- 未認証で任意の画面 → /session/new（Authentication concern の require_authentication）
- Login → 元の画面（after_authentication_url。無ければ root = Main）
- Main の設定（Learning の最小版。Unit 5）→ サインアウト → Login
- 「パスワードを忘れた」→ /passwords/new（Unit 0 の生成物。メール配信は本番設定が要る。runbook 2-f）

## 受け入れ条件（Given-When-Then）
- Given 未ログイン When / を開く Then /session/new が 390 幅で出る（Unit 0 の smoke_test で済み）
- Given 正しい email と password When ログイン Then Main に進み、Session レコードが 1 件できる（`User.authenticate_by` は両方を要る）
- Given 誤ったパスワード When ログイン Then /session/new に戻り「Try another email address or password.」相当の日本語が出る（文言は未決 4）
- Given ログイン済み When ブラウザを閉じて再訪 Then Login を経ずに Main が出る（生成物は `cookies.signed.permanent`。1 年に縮めるなら未決 3）
- Given ログイン済み When サインアウト Then Session が消え、/ は /session/new へ
- Given 3 分以内に POST /session を 10 回（成否を問わない）When 11 回目 Then rate_limit（Unit 0 生成の `rate_limit to: 10, within: 3.minutes`）で /session/new に alert「Try again later.」付きで戻る（test 環境は cache_store が null_store で rate_limit が効かない。未決 5）
- Given 390 幅 When Login を開く Then 入力とボタンが 44px 以上で、自動大文字化・自動修正が切れている

## 使う設定の鍵
dopamine.yml: なし
personas.yml: なし

## 外部 API
なし

## 未決
1. パスキー（WebAuthn）。ADR 0005 は「パスワード優先」。入れるなら ADR を足してから。第一の陣ではパスワードだけ
2. メールアドレス欄。生成された Sessions#new は email + password。1 人用なので email を省いて固定にするか（seed の DOPAFEED_USER_EMAIL）
3. ログイン保持期間「1 年」。生成物は permanent cookie（20 年）。短くするなら ADR 0005 に追記
4. エラー文言と、パスワードリセットのメール配信（SMTP 設定が無い。runbook 2-f の手順で代替）
5. rate_limit のテスト。config/environments/test.rb は `cache_store = :null_store` なので効かない。Unit 15 でそのテストだけ memory_store に切り替える
