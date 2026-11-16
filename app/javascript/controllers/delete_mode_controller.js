import { Controller } from "@hotwired/stimulus"

// 戻ってきたときは読むつもりのことが多いので、モードを写し・bfcache・ブラウザのフォーム復元に持ち越さない
export default class extends Controller {
  static targets = ["list", "switch"]
  static outlets = ["swipe"]

  connect() {
    this.reset()
    // 行は Turbo Stream が隠したり戻したりする。:has() は入れ子にできないので、ヘッダの切り替えは CSS では隠せない
    if (this.hasListTarget) {
      this.observer = new MutationObserver(() => this.syncSwitch())
      this.observer.observe(this.listTarget, { childList: true, subtree: true, attributeFilter: ["hidden"] })
    }
  }

  disconnect() {
    this.observer?.disconnect()
  }

  toggle(event) {
    const deleting = event.target.value === "delete"
    this.listTarget.toggleAttribute("data-delete-mode", deleting)
    if (deleting) this.swipeOutlets.forEach((row) => row.collapse())
    this.syncReadable(deleting)
    this.syncSwitch()
  }

  reset() {
    const read = this.element.querySelector("input[name=mode][value=read]")
    if (read) read.checked = true
    if (!this.hasListTarget) return

    this.listTarget.removeAttribute("data-delete-mode")
    this.syncReadable(false)
    this.syncSwitch()
  }

  // 削除モードの間は 0 本になっても残す。消すと「読む」に戻せない
  syncSwitch() {
    if (!this.hasSwitchTarget) return

    const empty = !this.listTarget.querySelector(":scope > li:not([hidden])")
    this.switchTarget.hidden = empty && !this.listTarget.hasAttribute("data-delete-mode")
  }

  // pointer-events を止めるだけでは、Tab と VoiceOver に押しても何も起きない「読む」が行の数だけ残る。
  // 後から差し込まれた行（取り消しで戻った行）は swipe が繋がったときに合わせる
  syncReadable(deleting) {
    this.listTarget.querySelectorAll("[data-swipe-target~='read']").forEach((button) => { button.inert = deleting })
  }
}
