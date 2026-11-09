import { Controller } from "@hotwired/stimulus"

// キャッシュ済みの 404 など、接続前に失敗した画像では error イベントを拾えない。
export default class extends Controller {
  static targets = ["image"]

  connect() {
    if (this.imageTarget.complete && this.imageTarget.naturalWidth === 0) this.remove()
  }

  remove() {
    this.element.remove()
  }
}
