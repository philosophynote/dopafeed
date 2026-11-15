import { Controller } from "@hotwired/stimulus"

// 戻ってきたときは読むつもりのことが多いので、モードを写し・bfcache・ブラウザのフォーム復元に持ち越さない
export default class extends Controller {
  static targets = ["list"]
  static outlets = ["swipe"]

  connect() {
    this.reset()
  }

  toggle(event) {
    const deleting = event.target.value === "delete"
    this.listTarget.toggleAttribute("data-delete-mode", deleting)
    if (deleting) this.swipeOutlets.forEach((row) => row.collapse())
    this.syncReadable(deleting)
  }

  reset() {
    const read = this.element.querySelector("input[name=mode][value=read]")
    if (read) read.checked = true
    if (!this.hasListTarget) return

    this.listTarget.removeAttribute("data-delete-mode")
    this.syncReadable(false)
  }

  // pointer-events を止めるだけでは、Tab と VoiceOver に押しても何も起きない「読む」が行の数だけ残る。
  // 後から差し込まれた行（取り消しで戻った行）は swipe が繋がったときに合わせる
  syncReadable(deleting) {
    this.listTarget.querySelectorAll("[data-swipe-target~='read']").forEach((button) => { button.inert = deleting })
  }
}
