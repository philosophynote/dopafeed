import { Controller } from "@hotwired/stimulus"
import { enqueue, noteSwipeFailed, noteSwipeSent } from "controllers/submission_queue"

const ROW_ID_PREFIX = "article_"

// 流れた行は DOM から抜かずに薄くして残す。iOS 27 より前の Safari は overflow-anchor を持たず、画面の上の行を抜くと見ている行が跳ねる。
// 行ごとには送らない。速く払い上げる間に送信が列に積み上がる。モードは写し・bfcache に持ち越さない（開いただけで消え始めないように）
export default class extends Controller {
  static targets = ["list", "form", "restoreForm", "restoreTemplate"]
  static values = { submitTimeoutSeconds: Number }

  connect() {
    this.kept = new Set()
    this.reset()
    // 払い・片付けのトーストは送信が終わってから描かれる。描かれる前に流しを送ると、DOM を見ただけでは置き換えてしまう
    const toast = document.getElementById("toast")
    if (toast) {
      this.toastObserver = new MutationObserver(() => { this.otherToastAwaited = false })
      this.toastObserver.observe(toast, { childList: true })
    }
  }

  disconnect() {
    this.stopWatching()
    this.toastObserver?.disconnect()
    this.submitCleanup?.()
  }

  toggle(event) {
    const flowing = event.target.value === "flow"
    if (flowing === this.flowing) return

    this.flowing = flowing
    this.element.toggleAttribute("data-flow-mode", flowing)
    if (flowing) {
      this.watch()
    } else {
      this.stopWatching()
      this.flush()
    }
  }

  // 入る前に上へ流れていた行は、一度画面に入るまで消さない（見てもいない行を消さない）
  watch() {
    if (!this.hasListTarget) return

    this.seen = new WeakSet()
    this.intersections = new IntersectionObserver((entries) => entries.forEach((entry) => this.observed(entry)))
    this.listTarget.querySelectorAll(":scope > li").forEach((row) => this.intersections.observe(row))
    // 払った跡や取り消しで戻った行は Turbo Stream が差し替えた別の要素なので、差し込まれたら見張り直す
    this.additions = new MutationObserver((records) => records.forEach(({ addedNodes }) => addedNodes.forEach((node) => {
      if (node instanceof HTMLLIElement) this.intersections.observe(node)
    })))
    this.additions.observe(this.listTarget, { childList: true })
  }

  stopWatching() {
    this.intersections?.disconnect()
    this.additions?.disconnect()
    this.intersections = null
    this.additions = null
  }

  observed({ target: row, isIntersecting, boundingClientRect, rootBounds }) {
    if (isIntersecting) return this.seen.add(row)
    if (!this.seen.has(row) || boundingClientRect.bottom > (rootBounds?.top ?? 0)) return

    if (this.flowable(row)) this.flow(row)
  }

  // 写しから戻ると kept は空になるが、広げた欄は中身ごと戻る。欄の中身で広げた行を見分ける
  flowable(row) {
    const detail = row.querySelector("[data-swipe-target~='detail']")
    return !row.hidden && !row.hasAttribute("data-flowed") && !row.classList.contains("swipe-active") &&
      !this.kept.has(row.id) && !(detail?.childElementCount > 0) && !row.querySelector("[data-completed='true']")
  }

  // 薄い行の「読む」に Tab や VoiceOver で届くと、消した記事を読み始めてしまう
  flow(row) {
    row.setAttribute("data-flowed", "")
    row.querySelector(":scope article").inert = true
    row.append(this.restoreTemplateTarget.content.cloneNode(true))
    this.pending.add(row.id)
  }

  unflow(id) {
    const row = document.getElementById(id)
    if (!row?.hasAttribute("data-flowed")) return

    row.removeAttribute("data-flowed")
    row.querySelector(":scope article").inert = false
    row.querySelector(":scope > .flow-restore")?.remove()
  }

  // 止まった合図は、最後に流れた行の IntersectionObserver の通知より先に来ることがある。2 フレーム待って拾い切ってから送る
  settled() {
    requestAnimationFrame(() => requestAnimationFrame(() => this.flush()))
  }

  flush() {
    if (this.sending || this.pending.size === 0) return

    const ids = [...this.pending]
    this.pending.clear()
    this.sending = true
    let stamped = false
    this.submit(this.formTarget, (form) => {
      form.querySelectorAll("input[name='article_ids[]']").forEach((input) => input.remove())
      ids.forEach((id) => form.append(this.idField(id)))
      // トーストを出さない送信で回数を進めると、残したトーストが自分は置き換わったと見て「元に戻す」を送らなくなる
      const keepToast = this.otherToastAwaited || this.otherToastShown()
      form.elements.namedItem("keep_toast").disabled = !keepToast
      stamped = !keepToast
      if (stamped) form.elements.namedItem("swipe").value = noteSwipeSent()
    }, (success, { timedOut = false, unsent = false } = {}) => {
      this.sending = false
      if (unsent) return
      if (!success && stamped) noteSwipeFailed()
      if (success) ids.forEach((id) => document.getElementById(id)?.setAttribute("data-flowed", "sent"))
      // 待ちの上限を越えただけなら届いているかもしれない。行は薄いまま残す
      if (!success && !timedOut) ids.forEach((id) => this.unflow(id))
      this.flush()
    })
  }

  // 払った行・片付けた行は跡に替わり、トーストの「元に戻す」でしか戻せない。押していない流しのトーストで置き換えない（流した行は薄い行のタップで戻せる）
  otherToastShown() {
    const undo = document.querySelector("#toast [data-controller='toast'] form")
    return Boolean(undo) && !undo.querySelector("input[name='flow']")
  }

  restore(event) {
    const row = event.currentTarget.closest("li")
    this.kept.add(row.id)
    if (this.pending.delete(row.id)) return this.unflow(row.id)

    this.submit(this.restoreFormTarget, (form) => {
      form.querySelector("input[name='article_ids[]']")?.remove()
      form.append(this.idField(row.id))
    })
  }

  // 読むの送信は前の送信の応答を待って列で遅れて始まる。始まるまでに流れて溜まらないよう、押した時点で外す
  noteTap(event) {
    const row = event.target.closest?.("[data-swipe-target~='read']")?.closest("li")
    if (!row || !this.listTarget?.contains(row)) return

    this.kept.add(row.id)
    if (this.pending.delete(row.id)) this.unflow(row.id)
  }

  noteSubmit({ target: form }) {
    if (!(form instanceof HTMLFormElement)) return

    const path = new URL(form.action).pathname
    if (this.makesOtherToast(form)) this.otherToastAwaited = true
    const reading = path.match(/\/articles\/(\d+)\/reading$/)
    if (reading) this.kept.add(`${ROW_ID_PREFIX}${reading[1]}`)
    if (path === new URL(this.formTarget.action).pathname && form.querySelector("input[name='_method'][value='delete']")) {
      form.querySelectorAll("input[name='article_ids[]']").forEach((input) => this.kept.add(`${ROW_ID_PREFIX}${input.value}`))
    }
  }

  noteSubmitEnd({ target: form, detail: { success } }) {
    if (!success && this.makesOtherToast(form)) this.otherToastAwaited = false
  }

  // 送った回数を付ける送信（払い・片付け）は応答でトーストを置き換える
  makesOtherToast(form) {
    return form instanceof HTMLFormElement && form !== this.formTarget && Boolean(form.elements.namedItem("swipe"))
  }

  idField(rowId) {
    return Object.assign(document.createElement("input"), { type: "hidden", name: "article_ids[]", value: rowId.slice(ROW_ID_PREFIX.length) })
  }

  // 行の送信と同じ列に並べる。並べずに送ると、応答待ちのスワイプの送信を Turbo が止める
  submit(form, prepare, done = () => {}) {
    enqueue(() => new Promise((resolve) => {
      if (!form.isConnected) {
        resolve()
        return done(false, { unsent: true })
      }

      const finish = (success, options) => {
        clearTimeout(timer)
        document.removeEventListener("turbo:submit-start", started)
        document.removeEventListener("turbo:submit-end", ended)
        this.submitCleanup = null
        resolve()
        done(success, options)
      }
      // 待ちの上限を越えた前の送信は止めていないので、同じ form から遅れて終わりが届く。今回の送信の終わりだけを拾う
      let submission
      const started = (event) => { if (event.target === form) submission ??= event.detail.formSubmission }
      const ended = (event) => { if (event.target === form && event.detail.formSubmission === submission) finish(event.detail.success) }
      // 応答が来なくても列は止めない（届いていれば後から Turbo が差し替える）
      const timer = setTimeout(() => finish(false, { timedOut: true }), this.submitTimeoutSecondsValue * 1000)
      document.addEventListener("turbo:submit-start", started)
      document.addEventListener("turbo:submit-end", ended)
      // 外されたときは列を解くだけ。応答を待たずに送り直さない
      this.submitCleanup = () => {
        clearTimeout(timer)
        document.removeEventListener("turbo:submit-start", started)
        document.removeEventListener("turbo:submit-end", ended)
        this.submitCleanup = null
        resolve()
      }
      prepare(form)
      form.requestSubmit()
    }))
  }

  // 写しと bfcache に薄い行を残すと、戻ったときに消えた記事が並んで見える。届いたか分からない行は未読のまま戻す
  reset(event) {
    if (event && this.hasListTarget) {
      this.listTarget.querySelectorAll(":scope > li[data-flowed='sent']").forEach((row) => { row.hidden = true })
      this.listTarget.querySelectorAll(":scope > li[data-flowed]:not([hidden])").forEach((row) => this.unflow(row.id))
    }
    this.flowing = false
    this.pending = new Set()
    this.element.removeAttribute("data-flow-mode")
    this.stopWatching()
  }
}
