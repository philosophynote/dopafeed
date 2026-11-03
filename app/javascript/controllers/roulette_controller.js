import { Controller } from "@hotwired/stimulus"

// ルーレットのモーダル。出目の帯は CSS が回す（長さは yml の ms を CSS 変数で受ける）。
// ここがするのは、止まった瞬間に結果のリンク（記事か Jackpot）を踏むことと、
// 記事から bfcache で戻ってきた文書に残ったモーダルを片付けることだけ。
// 遷移を JS の location ではなくリンクの click にするのは、記事へ出る印（reading-return#opened）と
// 遷移先を 1 つの要素に集め、サーバーが決めた行き先をそのまま使うため
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
