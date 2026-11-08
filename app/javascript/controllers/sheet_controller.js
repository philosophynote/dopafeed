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

  // 未完の区切りの後ろに置き直された「読み終えた」も、開くまでは隠す（JS が無いときの置き直しは無い）
  finishTargetConnected(form) {
    form.hidden = !this.opened
  }

  disconnect() {
    document.removeEventListener("visibilitychange", this.visibility)
    window.removeEventListener("focus", this.returned)
  }

  // 既定の遷移（target=_blank）は止めない。滞在は開いた時刻から数えるので、サーバーに知らせる。
  // keepalive: 開いた直後にページが凍っても（iOS）送り切らせる。
  // 届かなくても読むのは止めない（滞在が行を作った時刻から数えられ、長めに出るだけ）
  open() {
    this.starting = fetch(this.startUrlValue, {
      method: "POST",
      keepalive: true,
      headers: { "X-CSRF-Token": document.querySelector("meta[name=csrf-token]")?.content }
    }).catch(() => {})
    this.opened = true
    this.away = false
    this.finishTargets.forEach((form) => { form.hidden = false })
  }

  // 畳まれて見えない欄では送らない。開いたまま合図が来なかった欄が、別の欄の戻りの合図で判定されてしまうため（読んでいない記事に XP が付く）。
  // 開いた知らせの応答を待ってから送る。iOS で凍って知らせが戻りの後に届くと、一覧では開き直しが判定を消してしまうため
  async returned() {
    if (!this.opened || !this.away || !this.hasFinishTarget) return

    this.opened = false
    this.away = false
    await this.starting
    if (!this.element.isConnected || this.element.closest("[hidden]") || !this.hasFinishTarget) return

    // ボタンを submitter にすると、Turbo が応答まで無効にする（自動送信の直後の手押しで二重に送らない）
    const form = this.finishTarget
    this.handOver(form, form.querySelector("button[type=submit]"))
  }

  // 「読み終えた」の手押しも戻りの合図と同じ道で送る。開いた知らせの後に、一覧では行の送信の列に並べる（送信中の興味なし・保存の応答を捨てさせない）。
  // 開いた印も下ろす。未完の応答で置き直された「読み終えた」を、開き直すまで隠すため（押しても同じ未完が返るだけ）
  submit(event) {
    const form = event.target
    if ("handed" in form.dataset) {
      delete form.dataset.handed
      return
    }

    // 預けた後の押し直しは捨てる（列で待つ間に二重に送らない）
    event.preventDefault()
    if ("pending" in form.dataset) return

    form.dataset.pending = ""
    this.opened = false
    this.away = false
    const submitter = event.submitter
    Promise.resolve(this.starting).then(() => this.handOver(form, submitter))
  }

  // 応答が来て置き換わらなかった（通信の失敗など）ときに、もう一度押せるようにする
  sent(event) {
    delete event.target.dataset.pending
  }

  // 送信は finish の出来事で周りに預ける。一覧では行の送信の列（swipe）が受け取り、他の送信と応答を捨て合わないよう 1 本ずつ送る。受け取り手が無ければ自分で送る
  handOver(form, submitter) {
    form.dataset.pending = ""
    form.dataset.handed = ""
    const handed = this.dispatch("finish", { detail: { form, submitter }, cancelable: true })
    if (!handed.defaultPrevented) form.requestSubmit(submitter)
  }
}
