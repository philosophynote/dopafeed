import { Controller } from "@hotwired/stimulus"

// ホーム画面から開いているか（standalone）と通知の許可の状態で、「通知を許可する」と注記を切り替え、押されたら Push を購読してサーバーに預ける。
// standalone の判定は標準の display-mode と、iOS Safari だけが持つ navigator.standalone の両方（iOS の版で返り方が揺れる）。
// サーバーは standalone も許可の状態も知らないので JS で決める。JS が無ければ Safari のタブ向けの注記とボタン無効のまま。
// 許可のダイアログは iOS ではボタンのタップからしか出ず、一度拒否すると二度と出ないので、開いたときは状態を見るだけで requestPermission は呼ばない
export default class extends Controller {
  static targets = ["browser", "standalone", "denied", "permit"]
  static values = { vapidPublicKey: String, subscribeUrl: String }

  async connect() {
    const standalone = window.matchMedia("(display-mode: standalone)").matches || navigator.standalone === true
    this.browserTargets.forEach((element) => { element.hidden = standalone })
    this.standaloneTargets.forEach((element) => { element.hidden = !standalone })
    if (!standalone || !this.vapidPublicKeyValue || !this.pushSupported()) return

    if (Notification.permission === "denied") return this.showDenied()
    if (Notification.permission === "granted") {
      // 購読が既にあれば保存し直して「有効」にする。再購読はしない。保存し直すのは、DB を復元した後に行だけ無いことがあるため（同じ endpoint なら行は増えない）
      const subscription = await this.currentSubscription()
      if (subscription && await this.save(subscription)) return this.markEnabled()
    }

    this.permitTarget.disabled = false
  }

  // 許可 → 購読 → 保存。許可を貰えなければ設定へ誘導、途中で失敗したら押し直せるように戻す
  async permit() {
    this.permitTarget.disabled = true
    try {
      const permission = await Notification.requestPermission()
      if (permission === "denied") return this.showDenied()
      // "default" はダイアログを閉じただけ（デスクトップで起こる）。拒否ではないので、もう一度押せるように戻す
      if (permission !== "granted") return (this.permitTarget.disabled = false)

      const registration = await navigator.serviceWorker.ready
      const subscription = (await this.currentSubscription()) ||
        (await registration.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: this.applicationServerKey() }))
      if (!await this.save(subscription)) throw new Error("subscription not saved")

      this.markEnabled()
    } catch (error) {
      console.error(error)
      this.permitTarget.disabled = false
    }
  }

  pushSupported() {
    return "Notification" in window && "serviceWorker" in navigator && "PushManager" in window
  }

  // 端末にある購読。サーバーの鍵と違う鍵で作った購読（鍵を替えた後）は解除して「無し」と扱う。古い鍵の購読には送れない
  async currentSubscription() {
    const registration = await navigator.serviceWorker.ready
    const subscription = await registration.pushManager.getSubscription()
    if (subscription && !this.sameKey(subscription)) {
      await subscription.unsubscribe()
      return null
    }
    return subscription
  }

  sameKey(subscription) {
    const key = subscription.options?.applicationServerKey
    if (!key) return true

    const given = new Uint8Array(key)
    const current = this.applicationServerKey()
    return given.length === current.length && given.every((byte, index) => byte === current[index])
  }

  // 購読をサーバーに預ける。届かなくても例外にせず偽を返す（呼ぶ側がボタンを戻す）
  async save(subscription) {
    try {
      const response = await fetch(this.subscribeUrlValue, {
        method: "POST",
        headers: { "Content-Type": "application/json", "X-CSRF-Token": document.querySelector("meta[name=csrf-token]")?.content },
        body: JSON.stringify(subscription.toJSON())
      })
      return response.ok
    } catch (error) {
      console.error(error)
      return false
    }
  }

  // 押せない（無効）のと「もう有効」は見た目で分ける（data-enabled で色が変わる）
  markEnabled() {
    this.permitTarget.textContent = "通知は有効"
    this.permitTarget.disabled = true
    this.permitTarget.dataset.enabled = ""
    this.deniedTargets.forEach((element) => { element.hidden = true })
  }

  showDenied() {
    this.permitTarget.disabled = true
    this.deniedTargets.forEach((element) => { element.hidden = false })
  }

  // VAPID の公開鍵は base64url の文字列で届く。pushManager.subscribe は生のバイト列を要求する
  applicationServerKey() {
    const base64 = this.vapidPublicKeyValue.replace(/-/g, "+").replace(/_/g, "/")
    const padded = base64 + "=".repeat((4 - (base64.length % 4)) % 4)
    return Uint8Array.from(atob(padded), (char) => char.charCodeAt(0))
  }
}
