import { Controller } from "@hotwired/stimulus"

// Reader の 1 枚のカード。「記事を開く」で元サイトを別窓（iPhone のホーム画面アプリではシート）に開き、
// アプリに戻ってきたら「読み終えた」を 1 回だけ送る。
// 出たと見なすのは画面が隠れた（visibilitychange で hidden）ときだけ。blur は使わない。
// iPhone では押した瞬間に blur → focus が続けて来て、シートが開く前に戻ったと取り違えるため。
// 戻りは hidden の後の visible か focus。合図が来ない端末のために、「読み終えた」は開いた後に出して手でも押せるようにする。
// 開く前は隠す。開かずに押して XP を取れないように（JS が無いときは隠さないので、ボタンで送れる）
export default class extends Controller {
  static targets = ["finish"]
  static values = { startUrl: String }

  connect() {
    this.opened = false
    this.away = false
    this.finishTargets.forEach((form) => { form.hidden = true })
    this.returned = this.returned.bind(this)
    this.visibility = () => {
      if (document.visibilityState === "hidden") {
        if (this.opened) this.away = true
      } else {
        this.returned()
      }
    }
    document.addEventListener("visibilitychange", this.visibility)
    window.addEventListener("focus", this.returned)
  }

  disconnect() {
    document.removeEventListener("visibilitychange", this.visibility)
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
