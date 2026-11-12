import { Controller } from "@hotwired/stimulus"
import { play } from "controllers/sfx"

// 鳴らすのは現れた瞬間の 1 回だけ。鳴らしたら印を外し、Turbo のスナップショットから戻った画面では鳴り直さない（めくりの card-deck と同じ考え）。
// delay: CSS の動き（出目の帯が止まる）に合わせて遅らせる。画面を離れたら鳴らさない
export default class extends Controller {
  static values = { cue: String, delay: Number }

  connect() {
    if (!this.cueValue || document.documentElement.hasAttribute("data-turbo-preview")) return

    const cue = this.cueValue
    this.element.removeAttribute(`data-${this.identifier}-cue-value`)
    this.timer = setTimeout(() => play(cue), this.delayValue)
  }

  disconnect() {
    clearTimeout(this.timer)
  }
}
