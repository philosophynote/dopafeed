import { Controller } from "@hotwired/stimulus"

// 接続前や切断中の broadcast は届かないため、再接続時に待っている欄を取り直す。
// frame の取り直しだけでは購読が残って溜まるため、届いた後は購読も外す。
// stream source に Stimulus を付けると data-* が購読パラメータに混ざる。
export default class extends Controller {
  // 上限でも翌日の差し替えを待つ欄があるため、購読を外す状態は欄ごとに決める。
  // unfinished は届くたびに欄の中で待っているものが残るかを見る欄だけが持つ（別のタブには別の組が出ていて、送る側には分からない）
  static values = {
    url: String, frame: String, pending: { type: String, default: "pending" }, settled: { type: String, default: "ready failed" },
    unfinished: { type: String, default: "" }
  }

  connect() {
    this.missed = []
    this.frameLoaded = (event) => {
      if (event.target.id !== this.frameValue) return
      this.replayMissed()
      const settled = this.states(this.settledValue)
      if (event.target.querySelector(settled)) this.element.remove()
    }
    // 取り直しの応答はその後に届いた知らせより古いことがあるので、取り直す間に届いた分を描いた後に当て直す
    this.streamRendered = (event) => {
      if (!this.refreshing) return
      const target = event.target.getAttribute("target")
      const frame = document.getElementById(this.frameValue)
      if (target && frame?.querySelector(`#${CSS.escape(target)}`)) this.missed.push(event.target.cloneNode(true))
    }
    document.addEventListener("turbo:frame-load", this.frameLoaded)
    document.addEventListener("turbo:before-stream-render", this.streamRendered)
    this.observer = new MutationObserver(() => this.refreshIfConnected())
    this.observer.observe(this.element, { attributes: true, attributeFilter: ["connected"], subtree: true })
    this.observeUnfinished()
    this.refreshIfConnected()
  }

  disconnect() {
    document.removeEventListener("turbo:frame-load", this.frameLoaded)
    document.removeEventListener("turbo:before-stream-render", this.streamRendered)
    this.observer.disconnect()
    this.frameObserver?.disconnect()
  }

  states(value) {
    return value.split(/\s+/).map((state) => `[data-state='${state}']`).join(", ")
  }

  replayMissed() {
    if (!this.refreshing) return
    this.refreshing = false
    this.missed.splice(0).forEach((stream) => document.body.append(stream))
  }

  observeUnfinished() {
    const frame = document.getElementById(this.frameValue)
    if (!this.unfinishedValue || !frame) return

    this.frameObserver = new MutationObserver(() => this.removeIfFinished(frame))
    this.frameObserver.observe(frame, { childList: true, subtree: true })
  }

  removeIfFinished(frame) {
    if (this.refreshing || frame.querySelector(this.unfinishedValue)) return

    frame.querySelector(":scope > [data-state]")?.setAttribute("data-state", this.settledValue.split(/\s+/)[0])
    this.element.remove()
  }

  refreshIfConnected() {
    if (!this.element.querySelector("turbo-cable-stream-source[connected]")) return

    const frame = document.getElementById(this.frameValue)
    if (!frame || !frame.querySelector(this.states(this.pendingValue))) return

    this.refreshing = true
    if (frame.getAttribute("src") === this.urlValue) {
      frame.reload()
    } else {
      frame.src = this.urlValue
    }
  }
}
