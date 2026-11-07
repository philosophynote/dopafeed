import { Controller } from "@hotwired/stimulus"

// 要約の作成中に付く購読（turbo-cable-stream-source）。購読がつながったら、要約欄の frame を一度だけ取り直す。
// Job がつながる前に書き終えると、その差し替えは届かず「作成中」のまま残るため。
// iPhone でアプリを裏に回して戻ると購読が切れてつながり直すので、そのたびに作成中なら取り直す（切れている間の差し替えも届かない）
export default class extends Controller {
  static values = { url: String, frame: String }

  connect() {
    this.observer = new MutationObserver(() => this.refreshIfConnected())
    this.observer.observe(this.element, { attributes: true, attributeFilter: ["connected"] })
    this.refreshIfConnected()
  }

  disconnect() {
    this.observer.disconnect()
  }

  refreshIfConnected() {
    if (!this.element.hasAttribute("connected")) return

    const frame = document.getElementById(this.frameValue)
    if (!frame || !frame.querySelector("[data-state='pending']")) return

    if (frame.getAttribute("src") === this.urlValue) {
      frame.reload()
    } else {
      frame.src = this.urlValue
    }
  }
}
