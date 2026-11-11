import { Controller } from "@hotwired/stimulus"

// 接続前や切断中の broadcast は届かないため、再接続時に作成中の欄を取り直す。
// frame の取り直しだけでは購読が残って溜まるため、完成後は購読も外す。
// stream source に Stimulus を付けると data-* が購読パラメータに混ざる。
export default class extends Controller {
  static values = { url: String, frame: String }

  connect() {
    this.frameLoaded = (event) => {
      if (event.target.id !== this.frameValue) return
      if (event.target.querySelector("[data-state='ready'], [data-state='failed']")) this.element.remove()
    }
    document.addEventListener("turbo:frame-load", this.frameLoaded)
    this.observer = new MutationObserver(() => this.refreshIfConnected())
    this.observer.observe(this.element, { attributes: true, attributeFilter: ["connected"], subtree: true })
    this.refreshIfConnected()
  }

  disconnect() {
    document.removeEventListener("turbo:frame-load", this.frameLoaded)
    this.observer.disconnect()
  }

  refreshIfConnected() {
    if (!this.element.querySelector("turbo-cable-stream-source[connected]")) return

    const frame = document.getElementById(this.frameValue)
    if (!frame || !frame.querySelector("[data-state='pending']")) return

    if (frame.getAttribute("src") === this.urlValue) {
      frame.reload()
    } else {
      frame.src = this.urlValue
    }
  }
}
