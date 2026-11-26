import { Controller } from "@hotwired/stimulus"
import { enqueue, noteSwipeFailed, noteSwipeSent } from "controllers/submission_queue"

const SETTLE_POLL_MS = 50

export default class extends Controller {
  static targets = ["list", "count", "form"]
  static values = { submitTimeoutSeconds: Number }

  // 行は Turbo Stream が隠したり、一覧の中で読み終えて区切りに替わったりする。:has() では数を出せないので見張る
  connect() {
    this.sync()
    this.observer = new MutationObserver(() => this.sync())
    this.observer.observe(this.listTarget, { childList: true, subtree: true, attributeFilter: ["hidden", "data-completed", "data-flowed"] })
  }

  disconnect() {
    this.observer.disconnect()
    clearTimeout(this.settleTimer)
    this.submitCleanup?.()
  }

  // 一覧の中で読み終えた行と流した行は li が残るが、未読ではないので数えない
  sync() {
    const count = this.listTarget.querySelectorAll(":scope > li:not([hidden]):not([data-flowed]):not(:has([data-completed='true']))").length
    this.countTarget.textContent = count
    this.formTarget.hidden = count === 0
  }

  // 払った行は流れ切ってから列に並ぶ。その前に片付けを並べると、後から届くその行のトーストが片付けのトーストを置き換え、
  // 片付けを戻せなくなる。流れている行（swipe-active）が落ち着くまで待ってから並べる
  submit(event) {
    if (this.releasing) return

    event.preventDefault()
    if (this.queued) return

    this.queued = true
    this.whenSettled(() => this.send())
  }

  whenSettled(run, waited = 0) {
    const moving = this.listTarget.querySelector(":scope > li.swipe-active")
    if (!moving || waited >= this.submitTimeoutSecondsValue * 1000) return run()

    this.settleTimer = setTimeout(() => this.whenSettled(run, waited + SETTLE_POLL_MS), SETTLE_POLL_MS)
  }

  // サーバーは表示の後に消えた記事を「届かなかった片付けの分」として戻す側に入れる。払って隠した行や流した行の id を送ると、
  // 片付けを元に戻したときにそれらの行まで戻ってしまう
  sendOnlyVisible(form) {
    form.querySelectorAll("input[name='article_ids[]']").forEach((input) => {
      const row = this.listTarget.querySelector(`:scope > li#article_${CSS.escape(input.value)}`)
      input.disabled = !row || row.hidden || row.hasAttribute("data-flowed")
    })
  }

  // 送った回数を付けるのは、前の行のトーストの「元に戻す」を、このトーストに置き換わった後で送らせないため
  send() {
    const form = this.formTarget
    enqueue(() => new Promise((resolve) => {
      if (!form.isConnected) {
        this.queued = false
        return resolve()
      }

      const finish = (success) => {
        clearTimeout(timer)
        document.removeEventListener("turbo:submit-end", ended)
        if (!success) noteSwipeFailed()
        this.queued = false
        this.submitCleanup = null
        resolve()
      }
      const ended = (e) => { if (e.target === form) finish(e.detail.success) }
      // 応答が来なくても列は止めない（届いていれば後から Turbo が差し替える）
      const timer = setTimeout(() => finish(false), this.submitTimeoutSecondsValue * 1000)
      document.addEventListener("turbo:submit-end", ended)
      this.submitCleanup = () => finish(true)
      this.sendOnlyVisible(form)
      form.elements.namedItem("swipe").value = noteSwipeSent()
      this.releasing = true
      form.requestSubmit()
      this.releasing = false
    }))
  }
}
