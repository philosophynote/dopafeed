import { Controller } from "@hotwired/stimulus"

// location で遷移すると Turbo を通らないため、サーバーが決めたリンクを click する。
export default class extends Controller {
  static targets = ["link"]
  static values = { duration: Number }

  connect() {
    this.onPageShow = (event) => { if (event.persisted) this.element.remove() }
    window.addEventListener("pageshow", this.onPageShow)
    this.timer = setTimeout(() => this.linkTarget.click(), this.durationValue)
  }

  disconnect() {
    clearTimeout(this.timer)
    window.removeEventListener("pageshow", this.onPageShow)
  }
}
