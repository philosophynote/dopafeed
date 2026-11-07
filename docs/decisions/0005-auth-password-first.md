# ADR 0005: 認証は Rails 8 標準のパスワード。パスキーは後で
日付: 2026-10-22 状態: 採用
`bin/rails generate authentication`。User は seed で 1 件。パスキー（webauthn gem）は本丸が動いてから別 ADR で検討。

## 追記 2026-11-07: ログイン画面・保持期間・パスワードリセット（Unit 15、#67）
- **画面はパスワードだけ**。ユーザーは 1 人なので、サーバーが `User.sole` のメールで `User.authenticate_by` を呼ぶ（照合と時間差の扱いは生成物のまま）。0 人・2 人以上は入れないだけで 500 にしない。iCloud キーチェーンのため `autocomplete="username"` の隠し欄に固定の「dopafeed」を置く（メールを公開ページの HTML に出さない）
- **ログインは最後に使ってから 1 年保つ**（`Session::REMEMBER_FOR` と scope `unexpired`。コントローラと ActionCable の接続が同じ基準で通す）。生成物の permanent cookie（20 年）と期限の無い Session 行では、盗まれた cookie がいつまでも効く。cookie を 1 年の期限で出し、Session の `updated_at` が 1 日（`Authentication::REMEMBER_REFRESH_INTERVAL`）より前なら触って cookie を出し直す。`updated_at` が 1 年より前の Session は通さない。認証の数字なので dopamine.yml には置かない（rate_limit の 10 回 / 3 分と同じ）
- **メールでのパスワードリセットは消す**（/passwords の controller・mailer・views・route）。本番に SMTP が無く届かないうえ、認証の外に「メールを送らせる口」が残る。忘れたら docs/runbook.md 2-f の console 手順。SMTP を入れる日が来たら戻す
- 期限切れや二重ログインで残った Session 行は消さずに残す（通さないので穴にはならない。一人用で溜まっても数十行）。掃除の Job は要るようになったら足す
- test 環境の cache_store は memory_store（rate_limit を数えさせるため。null_store では効かない）。例ごとに `Rails.cache.clear`
- パスキーは引き続き後で（別 ADR）
