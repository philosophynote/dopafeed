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
  }

  reset() {
    const read = this.element.querySelector("input[name=mode][value=read]")
    if (read) read.checked = true
    if (this.hasListTarget) this.listTarget.removeAttribute("data-delete-mode")
  }
}
