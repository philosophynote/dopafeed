import { Controller } from "@hotwired/stimulus"

// 配信元が画像を消した・直リンクを断ったときに、壊れた画像の印を残さず枠ごと外す。
// 接続より先に読み込みが失敗していることがある（キャッシュ済みの 404）ので、接続時にも確かめる。
// lazy でまだ読みに行っていない画像は complete が false なので、ここでは外れない
export default class extends Controller {
  static targets = ["image"]

  connect() {
    if (this.imageTarget.complete && this.imageTarget.naturalWidth === 0) this.remove()
  }

  remove() {
    this.element.remove()
  }
}
