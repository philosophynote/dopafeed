import { Controller } from "@hotwired/stimulus"

// <details> は自前では外の触り・Esc・項目の押下で閉じない。
// 外の触りを click でなく pointerdown で拾うのは、iOS Safari が押せない要素の click を document まで届けないため。
export default class extends Controller {
  static targets = ["summary"]

  closeOutside(event) {
    if (!this.element.contains(event.target)) this.close()
  }

  escape() {
    if (!this.element.open) return
    this.close()
    this.summaryTarget.focus()
  }

  close() {
    this.element.open = false
  }
}
