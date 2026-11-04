import { Controller } from "@hotwired/stimulus"

// Reader の 1 枚のカード。「記事を開く」で元サイトを別窓（iPhone のホーム画面アプリではシート）に開き、
// アプリに戻ってきたら「読み終えた」を 1 回だけ送る。
// 戻りの合図（visibilitychange / focus）が来るかは端末次第なので、「読み終えた」は開いた後に出して手でも押せるようにする。
// 開く前は隠す。開かずに押して XP を取れないように（JS が無いときは隠さないので、ボタンで送れる）
export default class extends Controller {
  static targets = ["finish"]
  static values = { startUrl: String }

  connect() {
    this.opened = false
    this.away = false
    this.finishTargets.forEach((form) => { form.hidden = true })
    this.returned = this.returned.bind(this)
    this.left = () => { if (this.opened) this.away = true }
    this.visibility = () => document.visibilityState === "hidden" ? this.left() : this.returned()
    document.addEventListener("visibilitychange", this.visibility)
    window.addEventListener("blur", this.left)
    window.addEventListener("focus", this.returned)
  }

  disconnect() {
    document.removeEventListener("visibilitychange", this.visibility)
    window.removeEventListener("blur", this.left)
    window.removeEventListener("focus", this.returned)
  }

  // 既定の遷移（target=_blank）は止めない。滞在は開いた時刻から数えるので、サーバーに知らせる。
  // keepalive: 開いた直後にページが凍っても（iOS）送り切らせる。
  // 届かなくても読むのは止めない（滞在が行を作った時刻から数えられ、長めに出るだけ）
  open() {
    fetch(this.startUrlValue, {
      method: "POST",
      keepalive: true,
      headers: { "X-CSRF-Token": document.querySelector("meta[name=csrf-token]")?.content }
    }).catch(() => {})
    this.opened = true
    this.away = false
    this.finishTargets.forEach((form) => { form.hidden = false })
  }

  returned() {
    if (!this.opened || !this.away || !this.hasFinishTarget) return

    this.opened = false
    // ボタンを submitter にすると、Turbo が応答まで無効にする（自動送信の直後の手押しで二重に送らない）
    this.finishTarget.requestSubmit(this.finishTarget.querySelector("button[type=submit]"))
  }
}
