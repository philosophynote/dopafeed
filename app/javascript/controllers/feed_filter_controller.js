import { Controller } from "@hotwired/stimulus"

// before-render の時点の新しい段は DOM に付いておらず、scrollLeft を直に置いても 0 に戻される
export default class extends Controller {
  static values = { scrollLeft: Number }

  connect() {
    if (this.hasScrollLeftValue) {
      this.element.scrollLeft = this.scrollLeftValue
      // 残すと、Turbo の写しから戻ったときに古い位置を置き直してしまう
      this.element.removeAttribute(`data-${this.identifier}-scroll-left-value`)
    }
    this.revealCurrent()
  }

  carry(event) {
    const next = event.detail.newBody?.querySelector(`[data-controller~="${this.identifier}"]`)
    if (next) next.setAttribute(`data-${this.identifier}-scroll-left-value`, this.element.scrollLeft)
  }

  // scrollIntoView は段の外の縦も動かし、戻ったときに読んでいた位置からページの頭へ引き上げてしまう
  revealCurrent() {
    const current = this.element.querySelector("[aria-current='page']")
    if (!current) return

    const style = getComputedStyle(this.element)
    const frame = this.element.getBoundingClientRect()
    const left = frame.left + parseFloat(style.paddingLeft)
    const right = frame.right - parseFloat(style.paddingRight)
    const chip = current.getBoundingClientRect()
    if (chip.left < left) this.element.scrollLeft -= left - chip.left
    else if (chip.right > right) this.element.scrollLeft += chip.right - right
  }
}
