import { Controller } from "@hotwired/stimulus"

// カードの開封の後始末。めくり自体は CSS が動かす。
// 全画面（金）では閉じることを受け持つ: どこを押しても閉じるのは、閉じ方を探させないため（Jackpot の予告と違い、カードはもう手に入っている）。
// 開いたら「閉じる」に焦点を移し（Turbo Stream で差し込まれるので、移さないと読み上げに何も起きない）、閉じたら区切りへ戻す。
// bfcache で戻ってきた文書に残った全画面は片付ける（もう一度開封したことにしない）。
// 束（card-deck）では settle を受け持つ: Turbo がスナップショットを取る前にめくりの印を落とし、戻ってきたときにめくり直さない
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

  close() {
    const divider = this.element.closest("section")
    this.element.remove()
    if (divider) {
      divider.setAttribute("tabindex", "-1")
      divider.focus({ preventScroll: true })
    }
  }

  settle() {
    this.element.querySelectorAll(".card-reveal").forEach((card) => {
      card.classList.remove("card-reveal")
      card.removeAttribute("style")
      card.querySelector(".card-back")?.remove()
    })
  }
}
