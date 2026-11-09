import { Controller } from "@hotwired/stimulus"

// 金のカードの開封の全画面。めくり自体は CSS が動かし、ここは閉じることだけ受け持つ。
// どこを押しても閉じるのは、閉じ方を探させないため（Jackpot の予告と違い、カードはもう手に入っている）。
// 開いたら「閉じる」に焦点を移し（Turbo Stream で差し込まれるので、移さないと読み上げに何も起きない）、閉じたら区切りへ戻す。
// 押せるのは「閉じる」だけなので、Tab は後ろの Reader へ抜けさせずにそこへ留める（aria-modal だけでは焦点は閉じ込められない）。
// bfcache で戻ってきた文書に残った全画面は片付ける（もう一度開封したことにしない）
export default class extends Controller {
  static targets = ["close"]

  connect() {
    this.onPageShow = (event) => { if (event.persisted) this.close() }
    window.addEventListener("pageshow", this.onPageShow)
    if (this.hasCloseTarget) this.closeTarget.focus({ preventScroll: true })
  }

  disconnect() {
    window.removeEventListener("pageshow", this.onPageShow)
  }

  trap(event) {
    event.preventDefault()
    if (this.hasCloseTarget) this.closeTarget.focus({ preventScroll: true })
  }

  close() {
    const divider = this.element.closest("section")
    this.element.remove()
    if (divider) {
      divider.setAttribute("tabindex", "-1")
      divider.focus({ preventScroll: true })
    }
  }
}
