---
name: pwa-ios
description: Install / Push / バッジ / service worker を触る Unit で読む。iOS Safari の PWA 制約と代替策。
---
- Rails 8 の app/views/pwa/manifest.json.erb と service-worker.js を育てる。display: standalone、start_url は /
- iOS の Web Push はホーム画面に追加したときのみ。許可ダイアログは明示的なユーザー操作（ボタン）から出す
- 振動（navigator.vibrate）は iOS 不可 → CSS アニメーションと音で代替（docs/SPEC.md の表）
- バッジ（navigator.setAppBadge）はホーム追加後のみ。未読数に使う
- Push 送信: `web-push` gem + VAPID 鍵（credentials の `vapid:` に置き、.kamal/secrets 経由で ENV の VAPID_PUBLIC_KEY / VAPID_PRIVATE_KEY / VAPID_SUBJECT として読む。ADR 0013、作り方は docs/runbook.md 2-h）。購読は PushSubscription モデル（1 端末 1 行、user_id 無し）
- Push 送信は `Push::DispatchJob`（recurring.yml で 10 分おき）→ `Push::Digest` / `Push::StreakWarning` が文面 → `Push::Sender` が送る。endpoint は送る前に `HttpGet.verify_external!`。payload の `unread` を service worker がバッジに書き直す
- システムテストでは service worker は無効化。Push はユニットテストで送信ペイロードだけ検証（WebMock、本物の鍵で暗号化）
- 制約は変わる。実装前に Apple / MDN を WebFetch で確認
