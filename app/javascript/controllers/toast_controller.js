import { Controller } from "@hotwired/stimulus"

// 画面下の取り消しのトースト。秒数（dopamine.yml の toast.visible_seconds を view が渡す）が経ったら自分を外す。
// 0（鍵が無い）なら外さず、次のトーストに置き換わるか画面を移るまで残す
export default class extends Controller {
  static values = { seconds: Number }

  connect() {
    if (this.secondsValue > 0) this.timer = setTimeout(() => this.element.remove(), this.secondsValue * 1000)
  }

  disconnect() {
    clearTimeout(this.timer)
  }
}
