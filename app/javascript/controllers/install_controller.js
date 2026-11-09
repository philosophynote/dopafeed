import { Controller } from "@hotwired/stimulus"

// iOS の版で standalone の返り方が揺れるため、標準と Safari 独自の両方を調べる。
// iOS の許可ダイアログはタップからしか出せず、拒否後は再表示できないため、接続時には要求しない。
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
      // DB 復元後は端末の購読だけが残る場合があるため、再購読せず保存し直す。
      const subscription = await this.currentSubscription()
      if (subscription && await this.save(subscription)) return this.markEnabled()
    }

    this.permitTarget.disabled = false
  }

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

  // 鍵を替える前の購読には送れないため、端末に残った古い鍵の購読は解除する。
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

  applicationServerKey() {
    const base64 = this.vapidPublicKeyValue.replace(/-/g, "+").replace(/_/g, "/")
    const padded = base64 + "=".repeat((4 - (base64.length % 4)) % 4)
    return Uint8Array.from(atob(padded), (char) => char.charCodeAt(0))
  }
}
