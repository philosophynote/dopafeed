// ホーム画面のアプリが動くための最小の service worker。
// 取得（fetch）には触らない: 記事の一覧は毎回サーバーから出すので、キャッシュで古い未読を見せない。
// 新しい版が来たら待たずに入れ替える（一人用なので、開いているタブの不整合より更新の速さを取る）
self.addEventListener("install", () => {
  self.skipWaiting()
})

self.addEventListener("activate", (event) => {
  event.waitUntil(self.clients.claim())
})

// Push の受信。サーバーが送る JSON（title / body / path / unread / tag）をそのまま通知にする。
// iOS は受信のたびに通知を見せないと（黙って捨てると）許可を取り消すので、本文が読めなくても必ず 1 枚出す。
// アイコンのバッジは OS が再起動で消すので、受信のたびに unread で書き直す
self.addEventListener("push", (event) => {
  let data = {}
  try {
    data = event.data ? event.data.json() : {}
  } catch {
    data = {}
  }
  const tasks = [
    self.registration.showNotification(data.title || "Dopafeed", {
      body: data.body || undefined,
      tag: data.tag || undefined,
      icon: "/icon-180.png",
      data: { path: data.path || "/" }
    })
  ]
  if (typeof data.unread === "number" && navigator.setAppBadge) {
    tasks.push((data.unread > 0 ? navigator.setAppBadge(data.unread) : navigator.clearAppBadge()).catch(() => {}))
  }
  event.waitUntil(Promise.all(tasks))
})

// 通知のタップ。開いているウィンドウがあればそれを前に出して移動し、無ければ開く（同じアプリを二つ開かない）
self.addEventListener("notificationclick", (event) => {
  event.notification.close()
  const path = (event.notification.data && event.notification.data.path) || "/"
  event.waitUntil(
    self.clients.matchAll({ type: "window", includeUncontrolled: true }).then((clients) => {
      const client = clients[0]
      if (!client) return self.clients.openWindow(path)
      return client.focus().then((focused) => (focused && focused.navigate ? focused.navigate(path) : focused))
    })
  )
})
