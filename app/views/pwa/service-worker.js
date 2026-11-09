// fetch をキャッシュすると古い未読を見せるため、取得には介入しない。
// 一人用なので、開いたタブの不整合より更新の速さを優先して即時に入れ替える。
self.addEventListener("install", () => {
  self.skipWaiting()
})

self.addEventListener("activate", (event) => {
  event.waitUntil(self.clients.claim())
})

// iOS は黙って Push を捨てると許可を取り消すため、本文が読めなくても通知を出す。
// OS の再起動でバッジが消えるため、受信のたびに書き直す。
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
