import { Controller } from "@hotwired/stimulus"

// 金のカードの開封の全画面。めくり自体は CSS が動かし、ここは閉じることだけ受け持つ。
// どこを押しても閉じるのは、閉じ方を探させないため（Jackpot の予告と違い、カードはもう手に入っている）。
// bfcache で戻ってきた文書に残った全画面は片付ける（もう一度開封したことにしない）
export default class extends Controller {
  connect() {
    this.onPageShow = (event) => { if (event.persisted) this.close() }
    window.addEventListener("pageshow", this.onPageShow)
  }

  disconnect() {
    window.removeEventListener("pageshow", this.onPageShow)
  }

  close() {
    this.element.remove()
  }
}
