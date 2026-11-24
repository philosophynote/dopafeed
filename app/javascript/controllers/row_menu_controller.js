import { Controller } from "@hotwired/stimulus"

// <details> は自前では外の触り・フォーカスの離脱・Esc・項目の押下で閉じない。
// 外の触りを click でなく pointerdown で拾うのは、iOS Safari が押せない要素の click を document まで届けないため。
export default class extends Controller {
  static targets = ["summary"]

  closeOutside(event) {
    if (!this.element.contains(event.target)) this.close()
  }

  closeOnBlur(event) {
    if (event.relatedTarget && !this.element.contains(event.relatedTarget)) this.close()
  }

  escape() {
    if (this.element.open) this.choose()
  }

  // 項目を押すと中身が描画されなくなり、フォーカスが body に落ちる。削除の確認をやめたあと行を見失わないよう ⋯ に戻す
  choose() {
    this.close()
    this.summaryTarget.focus()
  }

  close() {
    this.element.open = false
  }
}
