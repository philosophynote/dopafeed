import { Controller } from "@hotwired/stimulus"
import { enqueue, noteSwipeFailed, noteSwipeSent } from "controllers/submission_queue"

const ROW_ID_PREFIX = "article_"

// 流れた行は DOM から抜かずに薄くして残す。iOS 27 より前の Safari は overflow-anchor を持たず、画面の上の行を抜くと見ている行が跳ねる。
// 流れるたびには送らず、スクロールが止まったときにまとめて送る。行ごとに送ると、速く払い上げる間に送信が列に積み上がる。
// モードは写し・bfcache に持ち越さない。開いただけで消え始めないように
export default class extends Controller {
  static targets = ["list", "form", "restoreForm", "restoreTemplate"]
  static values = { submitTimeoutSeconds: Number }

  connect() {
    this.kept = new Set()
    this.reset()
  }

  disconnect() {
    this.stopWatching()
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

  // 広げた行は読むつもりで触った行なので流さない。払っている行・読み終えた行・隠れた跡も外す
  flowable(row) {
    const detail = row.querySelector("[data-swipe-target~='detail']")
    return !row.hidden && !row.hasAttribute("data-flowed") && !row.classList.contains("swipe-active") &&
      !this.kept.has(row.id) && !(detail?.childElementCount > 0) && !row.querySelector("[data-completed='true']")
  }

  flow(row) {
    row.setAttribute("data-flowed", "")
    row.append(this.restoreTemplateTarget.content.cloneNode(true))
    this.pending.add(row.id)
  }

  unflow(id) {
    const row = document.getElementById(id)
    row?.removeAttribute("data-flowed")
    row?.querySelector(":scope > .flow-restore")?.remove()
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
    this.submit(this.formTarget, (form) => {
      form.querySelectorAll("input[name='article_ids[]']").forEach((input) => input.remove())
      ids.forEach((id) => form.append(this.idField(id)))
      form.elements.namedItem("swipe").value = noteSwipeSent()
    }, (success, { timedOut = false } = {}) => {
      this.sending = false
      if (!success) noteSwipeFailed()
      // 待ちの上限を越えただけなら届いているかもしれない。行は薄いまま残す
      if (!success && !timedOut) ids.forEach((id) => this.unflow(id))
      this.flush()
    })
  }

  // 送る前の行は手元で戻すだけ。送った行は 1 本だけ戻し、まとまりのトーストは残す（keep_toast）
  restore(event) {
    const row = event.currentTarget.closest("li")
    this.kept.add(row.id)
    if (this.pending.delete(row.id)) return this.unflow(row.id)

    this.submit(this.restoreFormTarget, (form) => {
      form.querySelector("input[name='article_ids[]']")?.remove()
      form.append(this.idField(row.id))
    })
  }

  // トーストの「元に戻す」で戻った行と、読むために押した行は、このページにいる間は流さない
  noteSubmit({ target: form }) {
    if (!(form instanceof HTMLFormElement)) return

    const path = new URL(form.action).pathname
    const reading = path.match(/\/articles\/(\d+)\/reading$/)
    if (reading) this.kept.add(`${ROW_ID_PREFIX}${reading[1]}`)
    if (path === new URL(this.formTarget.action).pathname && form.querySelector("input[name='_method'][value='delete']")) {
      form.querySelectorAll("input[name='article_ids[]']").forEach((input) => this.kept.add(`${ROW_ID_PREFIX}${input.value}`))
    }
  }

  idField(rowId) {
    return Object.assign(document.createElement("input"), { type: "hidden", name: "article_ids[]", value: rowId.slice(ROW_ID_PREFIX.length) })
  }

  // 行の送信と同じ列に並べる。並べずに送ると、応答待ちのスワイプの送信を Turbo が止める
  submit(form, prepare, done = () => {}) {
    enqueue(() => new Promise((resolve) => {
      if (!form.isConnected) {
        resolve()
        return done(false)
      }

      const finish = (success, options) => {
        clearTimeout(timer)
        document.removeEventListener("turbo:submit-end", ended)
        this.submitCleanup = null
        resolve()
        done(success, options)
      }
      const ended = (event) => { if (event.target === form) finish(event.detail.success) }
      // 応答が来なくても列は止めない（届いていれば後から Turbo が差し替える）
      const timer = setTimeout(() => finish(false, { timedOut: true }), this.submitTimeoutSecondsValue * 1000)
      document.addEventListener("turbo:submit-end", ended)
      this.submitCleanup = () => finish(true)
      prepare(form)
      form.requestSubmit()
    }))
  }

  // 写しに薄い行を残すと、戻ったときに消えた記事が並んで見える
  reset(event) {
    if (event?.type === "turbo:before-cache" && this.hasListTarget) {
      this.listTarget.querySelectorAll(":scope > li[data-flowed]").forEach((row) => { row.hidden = true })
    }
    this.flowing = false
    this.pending = new Set()
    this.element.removeAttribute("data-flow-mode")
    this.stopWatching()
  }
}
