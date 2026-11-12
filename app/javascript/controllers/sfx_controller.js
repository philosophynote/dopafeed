import { Controller } from "@hotwired/stimulus"
import { play } from "controllers/sfx"

// 鳴らすのは現れた瞬間の 1 回だけ。鳴らしたら印を外し、Turbo のスナップショットから戻った画面では鳴り直さない（めくりの card-deck と同じ考え）。
// delay: CSS の動き（出目の帯が止まる）に合わせて遅らせる。動きを減らす設定では CSS がすぐ止めるので待たない。画面を離れたら鳴らさない。
// 鳴らす時点で隠れている欄（応答を待つ間に別の行を広げられた）では鳴らさない。隠すのは同じ差し込みの中で swipe が決めるので、接続した時点では判らない
export default class extends Controller {
  static values = { cue: String, delay: Number }

  connect() {
    if (!this.cueValue || document.documentElement.hasAttribute("data-turbo-preview")) return

    const cue = this.cueValue
    const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches
    this.element.removeAttribute(`data-${this.identifier}-cue-value`)
    this.timer = setTimeout(() => {
      if (!this.element.parentElement?.closest("[hidden]")) play(cue)
    }, reduced ? 0 : this.delayValue)
  }

  disconnect() {
    clearTimeout(this.timer)
  }
}
