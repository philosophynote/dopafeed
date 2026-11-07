# Login（Unit 15）

## 目的
自分専用だが公開 URL なのでログインが要る。ユーザーは 1 人。ログイン状態は長く保持し、普段この画面は出ない。

## 要素
1. 「DopaFeed」ロゴ、「自分専用。公開 URL なのでログインが要ります」（固定）
2. 「パスワード」入力（type=password、高さ 44px 以上、自動大文字化・自動修正・スペルチェックを切る）。メール欄は無い（決まったこと 2）
3. ボタン「ログイン」（→ 元の画面か Main）
4. 注記「ユーザーは 1 人だけ。ログイン状態は最後に開いてから 1 年保つので、普段この画面は出ません」（年数は `Authentication::REMEMBER_FOR` から）

## 遷移
- 未認証で任意の画面 → /session/new（Authentication concern の require_authentication）
- Login → 元の画面（after_authentication_url。無ければ root = Main）
- Main の設定（Learning の最小版）→ サインアウト → Login
- 「パスワードを忘れた」は無い。docs/runbook.md 2-f の console 手順で直す（決まったこと 4）

## 受け入れ条件（Given-When-Then）
- Given 未ログイン When / を開く Then /session/new が 390 幅で出る
- Given 正しい password When ログイン Then Main に進み、Session レコードが 1 件できる
- Given ログイン前に開こうとした画面 When ログイン Then その画面に戻る
- Given 誤ったパスワード When ログイン Then /session/new に戻り「パスワードが違います」が出る
- Given User が 0 件 When ログイン Then 500 にならず、誤りと同じに戻る
- Given ログイン済み When ブラウザを閉じて再訪 Then Login を経ずに Main が出る（cookie の期限は最後に使ってから 1 年）
- Given 最後に使ってから 1 年を過ぎた Session When 再訪 Then cookie が残っていても /session/new へ
- Given 最後に使ってから 1 日を過ぎた Session When 再訪 Then Session の updated_at を触り、cookie を 1 年の期限で出し直す（1 日以内なら書き込まない）
- Given ログイン済み When サインアウト Then Session が消え、/ は /session/new へ
- Given 3 分以内に POST /session を 10 回（成否を問わない）When 11 回目 Then /session/new に「試行が多すぎます。少し待ってからもう一度」付きで戻る
- Given 390 幅 When Login を開く Then 入力とボタンが 44px 以上で、自動大文字化・自動修正が切れている
- Given 誰でも When /passwords/new を開く Then 404

## 使う設定の鍵
dopamine.yml: なし（保持期間は認証の数字なので Authentication concern の定数。ADR 0005 追記）
personas.yml: なし

## 外部 API
なし

## 決まったこと（2026-11-07 nao 承認、#67。ADR 0005 に追記）
1. パスキー（WebAuthn）は第一の陣では入れない。ボタンも置かない
2. メール欄は出さない。サーバーが `User.sole` のメールで照合する。キーチェーン用に `autocomplete="username"` の隠し欄（固定の「dopafeed」）
3. 保持は「最後に使ってから 1 年」。生成物の permanent cookie（20 年）と期限の無い Session 行をやめる
4. 文言は日本語。メールでのパスワードリセットは消す（本番に SMTP が無い）
5. rate_limit のテストのため、test 環境の cache_store を memory_store にし、例ごとに Rails.cache を空にする
