import { Controller } from "@hotwired/stimulus"

// ルーレットのモーダル。出目の帯は CSS が回す（長さは yml の ms を CSS 変数で受ける）。
// ここがするのは、止まった瞬間に結果のリンク（リーダーか Jackpot）を踏むことと、
// bfcache で戻ってきた文書に残ったモーダルを片付けることだけ。
// 遷移を JS の location ではなくリンクの click にするのは、サーバーが決めた行き先をそのまま Turbo で踏むため
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
