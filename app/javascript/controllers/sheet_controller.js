import { Controller } from "@hotwired/stimulus"

// iPhone は押した瞬間に blur → focus が来るため、blur を「出た」合図にすると戻りを誤判定する。
// 元記事を開く前に完了ボタンを見せると、開かずにカードを取れてしまう。
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

  // 別の欄の戻りの合図で、畳んだ記事を完読にしてしまわないようにする。
  // iOS で開いた知らせが遅れると、判定後の開き直しとして結果を消すため、応答を待つ。
  async returned() {
    if (!this.opened || !this.away || !this.hasFinishTarget) return

    this.opened = false
    this.away = false
    await this.starting
    if (!this.element.isConnected || this.element.closest("[hidden]") || !this.hasFinishTarget) return

    // submitter を渡すと Turbo が応答までボタンを無効にし、自動送信直後の手押しによる二重送信を防げる。
    const form = this.finishTarget
    this.handOver(form, form.querySelector("button[type=submit]"))
  }

  // 別の form と送信を重ねると、Turbo が直前の「興味なし」や「保存」の応答を捨てる。
  // 開き直す前に再判定しても同じ未完が返るだけなので、開いた印を下ろす。
  submit(event) {
    const form = event.target
    if ("handed" in form.dataset) return

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

  // 列で待つ間の手押しと、同期で発生する預けた送信を取り違えないよう、印は送る瞬間だけ立てる。
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
