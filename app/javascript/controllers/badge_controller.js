import { Controller } from "@hotwired/stimulus"

// アプリのアイコンに未読数を出す（Badging API）。ウィジェットが作れない iOS で、開かなくても数字が目に入る代わり。
// iOS はバッジを永続化せず、Safari のタブでは API 自体が無いので、ページを描くたびに書き直し、無ければ何もしない。
// iOS では通知を許可したホーム画面のアプリでしか反映されない（許可前は呼んでも何も起きない）。
// 0 は clearAppBadge で消す（「消す」を setAppBadge(0) の解釈に頼らず、呼び先で読めるように）
export default class extends Controller {
  static values = { count: Number }

  // 値の変化の callback は接続時にも 1 回呼ばれるので、connect では呼ばない（二度書かない）
  countValueChanged() {
    if (typeof navigator.setAppBadge !== "function") return

    const promise = this.countValue > 0 ? navigator.setAppBadge(this.countValue) : navigator.clearAppBadge()
    promise?.catch?.(() => {})
  }
}
