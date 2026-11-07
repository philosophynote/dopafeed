import { Controller } from "@hotwired/stimulus"
import { EDGE_PX, LOCK_PX } from "controllers/swipe_thresholds"

// 興味なしと違い取り消せないため、指を離してから通常の削除ボタンの確認を通す。
export default class extends Controller {
  static targets = ["delete"]
  static values = { ratio: Number }

  disconnect() { this.cancel() }

  start(event) {
    if (!event.isPrimary || event.button !== 0 || event.clientX < EDGE_PX || event.target.closest("button, a, input")) return
    this.origin = { id: event.pointerId, x: event.clientX, y: event.clientY }
  }

  move(event) {
    if (event.pointerId !== this.origin?.id) return
    const dx = event.clientX - this.origin.x, dy = event.clientY - this.origin.y
    if (Math.max(Math.abs(dx), Math.abs(dy)) < LOCK_PX) return
    if (Math.abs(dy) >= Math.abs(dx)) return this.cancel()
    this.element.style.transform = `translateX(${Math.min(0, dx)}px)`
  }

  end(event) {
    if (event.pointerId !== this.origin?.id) return
    const distance = this.origin.x - event.clientX
    this.cancel()
    if (distance >= this.element.offsetWidth * this.ratioValue) this.deleteTarget.click()
  }

  cancel() {
    this.origin = null
    this.element.style.transform = ""
  }
}
