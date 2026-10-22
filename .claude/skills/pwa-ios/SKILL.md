---
name: pwa-ios
description: Install / Push / バッジ / service worker を触る Unit で読む。iOS Safari の PWA 制約と代替策。
---
- Rails 8 の app/views/pwa/manifest.json.erb と service-worker.js を育てる。display: standalone、start_url は /
- iOS の Web Push はホーム画面に追加したときのみ。許可ダイアログは明示的なユーザー操作（ボタン）から出す
- 振動（navigator.vibrate）は iOS 不可 → CSS アニメーションと音で代替（docs/SPEC.md の表）
- バッジ（navigator.setAppBadge）はホーム追加後のみ。未読数に使う
- Push 送信: `web-push` gem + VAPID 鍵（credentials）。購読は PushSubscription モデル
- システムテストでは service worker は無効化。Push はユニットテストで送信ペイロードだけ検証
- 制約は変わる。実装前に Apple / MDN を WebFetch で確認
