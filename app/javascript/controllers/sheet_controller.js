import { Controller } from "@hotwired/stimulus"

// iPhone は押した瞬間に blur → focus が来るため、blur を「出た」合図にすると戻りを誤判定する。
// 元記事を開く前に完了ボタンを見せると、開かずに XP を取れてしまう。
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

  finishTargetConnected(form) {
    form.hidden = !this.opened
  }

  disconnect() {
    document.removeEventListener("visibilitychange", this.visibility)
    window.removeEventListener("focus", this.returned)
  }

  // iOS は別窓を開いた直後にページを凍らせるため keepalive で送り切る。
  // 送信失敗で読書を止めない。滞在が行の作成時刻からとなり、長めに出るだけ。
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
    if ("handed" in form.dataset) return

    // 預けた後の押し直しは捨てる（列で待つ間に二重に送らない）
    event.preventDefault()
    if ("pending" in form.dataset) return

    form.dataset.pending = ""
    this.opened = false
    this.away = false
    const submitter = event.submitter
    Promise.resolve(this.starting).then(() => this.handOver(form, submitter))
  }

  sent(event) {
    delete event.target.dataset.pending
  }

  // 送信は finish の出来事で周りに預ける。一覧では行の送信の列（swipe）が受け取り、他の送信と応答を捨て合わないよう 1 本ずつ送る。受け取り手が無ければ自分で送る
  // 預けた送信の印は送る瞬間だけ立てる（submit は requestSubmit の中で同期に来る）。列で待つ間の手押しを、預けた送信と取り違えないため
  handOver(form, submitter) {
    form.dataset.pending = ""
    const send = () => {
      form.dataset.handed = ""
      try {
        form.requestSubmit(submitter)
      } finally {
        delete form.dataset.handed
      }
    }
    const handed = this.dispatch("finish", { detail: { form, submitter, send }, cancelable: true })
    if (!handed.defaultPrevented) send()
  }
}
