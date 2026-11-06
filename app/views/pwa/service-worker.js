// ホーム画面のアプリが動くための最小の service worker。
// 取得（fetch）には触らない: 記事の一覧は毎回サーバーから出すので、キャッシュで古い未読を見せない。
// 新しい版が来たら待たずに入れ替える（一人用なので、開いているタブの不整合より更新の速さを取る）
self.addEventListener("install", () => {
  self.skipWaiting()
})

self.addEventListener("activate", (event) => {
  event.waitUntil(self.clients.claim())
})
