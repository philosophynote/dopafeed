import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"
import { EDGE_PX, LOCK_PX } from "controllers/swipe_thresholds"

const FLY_OUT_RATIO = 1.2
// transitionend を待つ上限に足す余裕。合図が来なくても止まった頃に次へ進むため
const SETTLE_MARGIN_MS = 100

// Turbo は form の送信中に別の form が送られると先の送信を止めて応答を捨てる（先のカードが画面に残る）。
// 送信は全カードで 1 本の列に並べ、前の turbo:submit-end を待ってから次を送る
let submissions = Promise.resolve()
// 最後に「読む」を押した印。応答は送った順に届くので、待つ間に押し直した行を後の応答で負かさないよう、開くのはこの印を持つ行だけにする
let latestTap = 0

export default class extends Controller {
  static targets = ["card", "rail", "saveRail", "form", "saveForm", "read", "detail"]
  static values = { dismissRatio: Number, submitTimeoutSeconds: Number }

  disconnect() {
    this.settleCleanup?.()
    this.submitCleanup?.()
  }

  start(event) {
    this.swiped = false
    if (this.flying || this.opening || !event.isPrimary || event.button !== 0 || event.clientX < EDGE_PX) return
    const control = event.target.closest("a, button, input, select, textarea")
    if (control && control !== this.readTarget) return

    this.pointerId = event.pointerId
    this.startX = event.clientX
    this.startY = event.clientY
    this.tracking = true
    this.horizontal = false
    this.dx = 0
    this.settleCleanup?.()
    this.cardTarget.classList.remove("swipe-settling")
    this.rails().forEach((rail) => rail.classList.remove("swipe-settling"))
  }

  move(event) {
    if (!this.tracking || event.pointerId !== this.pointerId) return

    const dx = event.clientX - this.startX
    const dy = event.clientY - this.startY
    if (!this.horizontal) {
      if (Math.abs(dy) > LOCK_PX && Math.abs(dy) >= Math.abs(dx)) {
        this.tracking = false
        return
      }
      if (Math.abs(dx) < LOCK_PX) return

      this.horizontal = true
      this.swiped = true
      this.element.classList.add("swipe-active")
      this.capture()
    }
    this.dx = Math.max(this.hasFormTarget ? -Infinity : 0, Math.min(this.hasSaveFormTarget ? Infinity : 0, dx))
    this.render(this.dx)
  }

  end(event) {
    if (!this.tracking || event.pointerId !== this.pointerId) return

    this.tracking = false
    if (!this.horizontal) return

    if (this.dx !== 0 && Math.abs(this.dx) >= this.threshold()) {
      this.flyOut(Math.sign(this.dx))
    } else {
      this.settle(0)
    }
  }

  cancel(event) {
    if (!this.tracking || event.pointerId !== this.pointerId) return

    this.tracking = false
    if (this.horizontal) this.settle(0)
  }

  capture() {
    try {
      this.cardTarget.setPointerCapture(this.pointerId)
    } catch {
      // 合成イベントには実 pointer が無いが、捕捉できなくても追従は続けられる。
    }
  }

  threshold() {
    return this.cardTarget.offsetWidth * this.dismissRatioValue
  }

  rails() {
    return this.hasSaveRailTarget ? [this.railTarget, this.saveRailTarget] : [this.railTarget]
  }

  render(dx) {
    const progress = Math.min(1, Math.abs(dx) / this.threshold())
    const active = dx < 0 ? this.railTarget : dx > 0 && this.hasSaveRailTarget ? this.saveRailTarget : null
    // 一覧の行は横へ平らに滑らせる（傾けると隣の行と背景の丸に食い込む）
    this.cardTarget.style.transform = dx === 0 ? "" : `translateX(${dx}px)`
    this.rails().forEach((rail) => {
      const shown = rail === active
      rail.style.opacity = shown ? progress : 0
      rail.style.width = `${shown ? Math.abs(dx) : 0}px`
      rail.classList.toggle("swipe-armed", shown && progress >= 1)
    })
  }

  // 長さを固定すると reduced motion や CSS の変更に追従しないため、CSS から読む。
  settle(dx, done = () => {}) {
    this.settleCleanup?.()
    const card = this.cardTarget
    card.classList.add("swipe-settling")
    this.rails().forEach((rail) => rail.classList.add("swipe-settling"))
    const duration = parseFloat(getComputedStyle(card).transitionDuration) * 1000
    this.render(dx)

    const finish = () => {
      this.settleCleanup?.()
      if (dx === 0) this.element.classList.remove("swipe-active")
      done()
    }
    if (!(duration > 0)) return finish()

    const timer = setTimeout(finish, duration + SETTLE_MARGIN_MS)
    card.addEventListener("transitionend", finish, { once: true })
    this.settleCleanup = () => {
      clearTimeout(timer)
      card.removeEventListener("transitionend", finish)
      this.settleCleanup = null
    }
  }

  // 先に送ると Turbo の差し替えで、流れ出す途中のカードが消えてしまう。
  flyOut(direction) {
    this.flying = true
    this.settle(direction * this.cardTarget.offsetWidth * FLY_OUT_RATIO, () => this.submit(direction))
  }

  submit(direction) {
    const form = direction > 0 ? this.saveFormTarget : this.formTarget
    this.enqueue(form, null, (success) => { if (!success) this.restore() })
  }

  enqueue(form, submitter, done, { stopOnTimeout = false, send = () => form.requestSubmit(submitter) } = {}) {
    submissions = submissions.then(() => new Promise((resolve) => {
      if (!form.isConnected) return resolve()

      let submission
      const started = (event) => { if (event.target === form) submission = event.detail.formSubmission }

      // 列は必ず進める。結果を待たずに外されても（画面を移って行が消えた）ここで解いて、次の行が止まらないようにする
      const finish = () => {
        clearTimeout(timer)
        document.removeEventListener("turbo:submit-start", started)
        document.removeEventListener("turbo:submit-end", ended)
        this.submitCleanup = null
        resolve()
      }
      const ended = (event) => {
        if (event.target !== form) return

        finish()
        done(event.detail.success)
      }
      // 応答が来ないまま列を止めない。次の送信に進む（興味なしは届いていれば後から Turbo が差し替える）。
      // stopOnTimeout なら送信を止める。Turbo は送信中のボタンを押せなくするので、止めないと応答が来るまで押し直せない
      const timer = setTimeout(() => {
        finish()
        if (stopOnTimeout) submission?.stop()
        done(false)
      }, this.submitTimeoutSecondsValue * 1000)
      document.addEventListener("turbo:submit-start", started)
      document.addEventListener("turbo:submit-end", ended)
      this.submitCleanup = finish
      send()
    }))
  }

  // 引いた後にも click が来る端末があるため、タップと区別する。キーボード操作（detail: 0）は通す。
  // 別の送信を重ねると、Turbo が直前の「興味なし」や「保存を外す」の応答を捨てる。
  // 差し替えは submit-end の次のフレームなので、その間も awaiting を保たないと二重送信する。
  open(event) {
    const swiped = this.swiped && event.detail > 0
    this.swiped = false
    event.preventDefault()
    if (swiped || this.flying || this.opening || this.awaiting) return

    if (this.readTarget.tagName === "A") {
      const href = this.readTarget.href
      submissions = submissions.then(() => Turbo.visit(href))
      return
    }
    this.tap = ++latestTap
    if (this.loaded()) return this.expand(this.detailTarget.hidden)

    this.opening = true
    this.awaiting = this.hasDetailTarget
    this.enqueue(this.readTarget.form, this.readTarget, (success) => {
      this.opening = false
      if (!success) this.awaiting = false
    }, { stopOnTimeout: true })
  }

  // 遅れて届いた応答で、後から開いた行を畳まない。キャッシュ復元時は元の開閉状態を保つ。
  detailTargetConnected() {
    if (!this.loaded()) return

    const open = (this.awaiting && this.tap === latestTap) || this.readTarget.getAttribute("aria-expanded") === "true"
    this.awaiting = false
    this.expand(open)
  }

  collapse() {
    if (this.hasDetailTarget) this.expand(false)
  }

  loaded() {
    return this.hasDetailTarget && this.detailTarget.childElementCount > 0
  }

  expand(open) {
    this.detailTarget.hidden = !open
    this.readTarget.setAttribute("aria-expanded", String(open))
    if (open) this.dispatch("expanded")
  }

  // 行の下の欄が戻りの「読み終えた」を預けてきた。興味なし・保存・読むと同じ列に並べ、送信中の応答を捨てさせない。
  // 送るのは欄が渡した send（預けた送信と手押しを欄が見分けるため）
  finish(event) {
    event.preventDefault()
    const { form, submitter, send } = event.detail
    this.enqueue(form, submitter, () => {}, { send })
  }

  restore() {
    this.settle(0, () => { this.flying = false })
  }
}
