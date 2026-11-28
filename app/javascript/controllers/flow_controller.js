import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"
import { enqueue, noteSwipeFailed, noteSwipeSent } from "controllers/submission_queue"

const ROW_ID_PREFIX = "article_"
// Safari 26.2 より前は scrollend が無い。止まりを測る秒数を足す代わりに、流れた分をすぐ送り、応答を待つ間に流れた分を次にまとめる
const SCROLLEND_SUPPORTED = "onscrollend" in window
// 「次は」で開く先だけを流すのまま始める。URL や sessionStorage に持たせると再読込でも流すで始まり、開いただけで消え始める。
// モジュールの変数なら再読込で消え、戻る・チップでは立たない
let carriedTo = null

// 流れた行は DOM から抜かずに薄くして残す。iOS 27 より前の Safari は overflow-anchor を持たず、画面の上の行を抜くと見ている行が跳ねる。
// 行ごとには送らない。速く払い上げる間に送信が列に積み上がる。モードは写し・bfcache に持ち越さない（開いただけで消え始めないように）
export default class extends Controller {
  static targets = ["list", "form", "restoreForm", "restoreTemplate", "result"]
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
    this.resumeCarried()
  }

  resumeCarried() {
    if (!carriedTo) return

    const carried = carriedTo === window.location.href
    carriedTo = null
    const radio = this.element.querySelector("input[name=mode][value=flow]")
    if (!carried || !radio) return

    radio.checked = true
    radio.dispatchEvent(new Event("change", { bubbles: true }))
  }

  // 先頭へ戻る間、行は画面の下へ動くだけなので流れない
  toTop() {
    const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches
    window.scrollTo({ top: 0, behavior: reduced ? "instant" : "smooth" })
    const current = this.element.querySelector("nav.feed-filter [aria-current='page']") ?? this.element.querySelector("input[name=mode]:checked")
    current?.focus({ preventScroll: true })
  }

  // 流した分を送り切ってから移る。送信中に移ると Turbo が送信を止め、流した記事が未読のまま残る。
  // 送れなかった・待ちの上限を越えたときは移らず、薄さの取れた行を見せる。待つ間に流れた分は送らないので、見張りもやめる
  next(event) {
    event.preventDefault()
    if (this.leavingTo) return

    this.leavingTo = event.currentTarget.href
    this.stopWatching()
    this.seal()
  }

  // 送信の終わりのたびに flush からも呼ばれるので、移るのは 1 度だけ。
  // 描かれるまで列を止める。止めないと、待つ間に押した「戻す」などの送信を Turbo が始め、移動の方を取り消す。
  // 別の画面へのリンクで移動が取り消されたら、描かれた先が違うので持ち越しを捨てる
  leave() {
    if (!this.leavingTo || this.left) return

    this.left = true
    const href = this.leavingTo
    carriedTo = href
    enqueue(() => new Promise((resolve) => {
      const settle = (timedOut) => {
        document.removeEventListener("turbo:before-render", rendered)
        clearTimeout(timer)
        if (window.location.href !== href) carriedTo = null
        if (timedOut && this.element.isConnected) {
          this.left = false
          this.stay()
        }
        resolve()
      }
      const rendered = () => settle(false)
      const timer = setTimeout(() => settle(true), this.submitTimeoutSecondsValue * 1000)
      document.addEventListener("turbo:before-render", rendered)
      Turbo.visit(href, { action: "replace" })
    }))
  }

  stay() {
    if (!this.leavingTo || this.left) return

    this.leavingTo = null
    if (this.flowing) this.watch()
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
      this.stay()
      this.stopWatching()
      this.seal()
    }
  }

  // 入る前に上へ流れていた行は、一度画面に入るまで消さない（見てもいない行を消さない）
  watch() {
    if (!this.hasListTarget) return

    this.seen = new WeakSet()
    this.intersections = new IntersectionObserver((entries) => {
      entries.forEach((entry) => this.observed(entry))
      if (!SCROLLEND_SUPPORTED) this.seal()
    })
    this.listTarget.querySelectorAll(":scope > li").forEach((row) => this.intersections.observe(row))
    // 払った跡や取り消しで戻った行は Turbo Stream が差し替えた別の要素なので、差し込まれたら見張り直し、外された行は見張りをやめる
    this.additions = new MutationObserver((records) => records.forEach(({ addedNodes, removedNodes }) => {
      addedNodes.forEach((node) => { if (node instanceof HTMLLIElement) this.intersections.observe(node) })
      removedNodes.forEach((node) => { if (node instanceof HTMLLIElement) this.intersections.unobserve(node) })
    }))
    this.additions.observe(this.listTarget, { childList: true })
  }

  stopWatching() {
    this.intersections?.disconnect()
    this.additions?.disconnect()
    this.intersections = null
    this.additions = null
  }

  // 差し替えで外された古い行にも「画面の外へ出た」通知が届く。一覧に残っている行だけを見る。
  // Tab で送った行はフォーカスに合わせてブラウザがスクロールするので、キーボードで動かした分は流さない
  observed({ target: row, isIntersecting, boundingClientRect, rootBounds }) {
    if (row.parentElement !== this.listTarget) return
    if (isIntersecting) return this.seen.add(row)
    if (this.keyboard || !this.seen.has(row) || boundingClientRect.bottom > (rootBounds?.top ?? 0)) return

    if (this.flowable(row)) this.flow(row)
  }

  noteKeyboard() {
    this.keyboard = true
  }

  notePointer() {
    this.keyboard = false
  }

  // 写しから戻ると kept は空になるが、広げた欄は中身ごと戻る。欄の中身で広げた行を見分ける
  flowable(row) {
    const detail = row.querySelector("[data-swipe-target~='detail']")
    return !row.hidden && !row.hasAttribute("data-flowed") && !row.classList.contains("swipe-active") &&
      !this.kept.has(row.id) && !(detail?.childElementCount > 0) && !row.querySelector("[data-completed='true']")
  }

  // 薄い行の「読む」に Tab や VoiceOver で届くと、消した記事を読み始めてしまう。戻すボタンは見出しで読み分けられるようにする
  flow(row) {
    row.setAttribute("data-flowed", "")
    row.querySelector(":scope article").inert = true
    const restore = this.restoreTemplateTarget.content.cloneNode(true)
    restore.querySelector("[data-flow-title]").textContent = `「${row.querySelector("h2")?.textContent.trim() ?? ""}」を`
    row.append(restore)
    this.pending.add(row.id)
  }

  unflow(id) {
    const row = document.getElementById(id)
    if (!row?.hasAttribute("data-flowed")) return

    row.removeAttribute("data-flowed")
    row.querySelector(":scope article").inert = false
    row.querySelector(":scope > .flow-restore")?.remove()
  }

  // 止まった合図は、最後に流れた行の IntersectionObserver の通知より先に来ることがある。2 フレーム待って拾い切ってから締める
  settled() {
    requestAnimationFrame(() => requestAnimationFrame(() => this.seal()))
  }

  // 送るまとまりは止まった時点（またはモードを抜けた時点）で締める。応答を待つ間に流れ始めた分を前のまとまりに混ぜない
  seal() {
    if (this.pending.size > 0) this.batches.push(this.pending)
    this.pending = new Set()
    this.flush()
  }

  forget(id) {
    this.pending.delete(id)
    this.batches.forEach((batch) => batch.delete(id))
  }

  flush() {
    if (this.sending) return

    const batch = this.batches.shift()
    if (!batch) return this.leave()
    if (batch.size === 0) return this.flush()

    const ids = [...batch]
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
    }, {
      released: ({ timedOut = false, unsent = false, failed = false } = {}) => {
        this.sending = false
        if (timedOut || unsent || failed) this.stay()
        if (unsent) return ids.forEach((id) => this.unflow(id))
        if (timedOut && stamped) noteSwipeFailed()
        this.flush()
      },
      // 待ちの上限を越えた後に届いた終わりも拾う。成功は応答の result が行に反映する
      ended: (success, { late }) => {
        if (success) return
        if (!late && stamped) noteSwipeFailed()
        ids.forEach((id) => { if (document.getElementById(id)?.dataset.flowed !== "sent") this.unflow(id) })
      }
    })
  }

  // 送った id のうち、サーバーが実際に消した記事だけを「送った」にする。別のタブで先に消えていた記事などは薄さを取る
  // （その行の「戻す」で、ほかで付いた削除まで外さないため）
  resultTargetConnected(result) {
    const flowed = new Set(result.dataset.flowed.split(" ").filter(Boolean).map((id) => `${ROW_ID_PREFIX}${id}`))
    result.dataset.requested.split(" ").filter(Boolean).forEach((id) => {
      const rowId = `${ROW_ID_PREFIX}${id}`
      if (flowed.has(rowId)) {
        document.getElementById(rowId)?.setAttribute("data-flowed", "sent")
      } else {
        this.unflow(rowId)
      }
    })
    result.remove()
  }

  // 払った行・片付けた行は跡に替わり、トーストの「元に戻す」でしか戻せない。押していない流しのトーストで置き換えない（流した行は薄い行のタップで戻せる）
  otherToastShown() {
    const undo = document.querySelector("#toast [data-controller='toast'] form")
    return Boolean(undo) && !undo.querySelector("input[name='flow']")
  }

  restore(event) {
    const row = event.currentTarget.closest("li")
    this.kept.add(row.id)
    if (row.dataset.flowed !== "sent") {
      this.forget(row.id)
      return this.unflow(row.id)
    }

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
    if (row.dataset.flowed !== "sent") {
      this.forget(row.id)
      this.unflow(row.id)
    }
  }

  // 戻した記事は、まだ送っていないまとまりからも外す。外さないと「読む」に切り替えたときに戻した記事をまた消す
  noteSubmit({ target: form }) {
    if (!(form instanceof HTMLFormElement)) return

    const path = new URL(form.action).pathname
    if (this.makesOtherToast(form)) this.otherToastAwaited = true
    const reading = path.match(/\/articles\/(\d+)\/reading$/)
    if (reading) this.kept.add(`${ROW_ID_PREFIX}${reading[1]}`)
    if (path === new URL(this.formTarget.action).pathname && form.querySelector("input[name='_method'][value='delete']")) {
      form.querySelectorAll("input[name='article_ids[]']").forEach((input) => {
        const rowId = `${ROW_ID_PREFIX}${input.value}`
        this.kept.add(rowId)
        this.forget(rowId)
      })
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

  // 行の送信と同じ列に並べる。並べずに送ると、応答待ちのスワイプの送信を Turbo が止める。
  // 応答が来なくても列は止めない（released）。今回の送信の終わり（ended）は、待ちの上限を越えた後に届いても渡す
  submit(form, prepare, { released = () => {}, ended = () => {} } = {}) {
    enqueue(() => new Promise((resolve) => {
      if (!form.isConnected) {
        resolve()
        return released({ unsent: true })
      }

      let late = false
      let submission
      const release = (options) => {
        clearTimeout(timer)
        this.submitCleanup = null
        resolve()
        released(options)
      }
      const stopListening = () => {
        document.removeEventListener("turbo:submit-start", started)
        document.removeEventListener("turbo:submit-end", onEnd)
      }
      // 同じ form から前の送信の終わりが遅れて届くことがあるので、今回の送信の終わりだけを拾う
      const started = (event) => { if (event.target === form) submission ??= event.detail.formSubmission }
      const onEnd = (event) => {
        if (event.target !== form || event.detail.formSubmission !== submission) return

        stopListening()
        if (!late) release({ failed: !event.detail.success })
        ended(event.detail.success, { late })
      }
      const timer = setTimeout(() => {
        late = true
        release({ timedOut: true })
      }, this.submitTimeoutSecondsValue * 1000)
      document.addEventListener("turbo:submit-start", started)
      document.addEventListener("turbo:submit-end", onEnd)
      // 外されたときは列を解くだけ。応答を待たずに送り直さない
      this.submitCleanup = () => {
        clearTimeout(timer)
        stopListening()
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
    this.keyboard = false
    this.leavingTo = null
    this.left = false
    this.pending = new Set()
    this.batches = []
    this.element.removeAttribute("data-flow-mode")
    this.stopWatching()
  }
}
