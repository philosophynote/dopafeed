import { Controller } from "@hotwired/stimulus"

// iOS はバッジを永続化せず、Safari のタブには API 自体が無い。
export default class extends Controller {
  static values = { count: Number }

  // 値の変化の callback は接続時にも 1 回呼ばれるので、connect では呼ばない（二度書かない）
  countValueChanged() {
    if (typeof navigator.setAppBadge !== "function") return

    const promise = this.countValue > 0 ? navigator.setAppBadge(this.countValue) : navigator.clearAppBadge()
    promise?.catch?.(() => {})
  }
}
