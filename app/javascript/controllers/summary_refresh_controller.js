import { Controller } from "@hotwired/stimulus"

// 要約の出来上がりを待つ購読（中の turbo-cable-stream-source）。購読がつながるたびに、作成中なら要約欄の frame を取り直す。
// つながる前や、iPhone でアプリを裏に回して切れている間に Job が書き終えると、その差し替えは届かず「作成中」のまま残るため。
// 取り直しで出来上がり（要約・失敗）が返ったら購読ごと外す。取り直しは frame だけを入れ替えるので、外さないと購読が残り、継ぎ足すたびに溜まる。
// Stimulus を stream source 自身に付けないのは、その data-* が購読のパラメータに混ざるから
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
