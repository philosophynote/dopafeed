import { Controller } from "@hotwired/stimulus"
import { EDGE_PX, LOCK_PX } from "controllers/swipe_thresholds"

// 一覧の 1 行。左へ引いて離すと「興味なし」の form を送り、触れて離すと「読む」の form を送る。記録と差し替えはサーバー（Turbo Stream）の仕事で、ここは指の動きを form の送信に変えるだけ。
// 行全体が「読む」のボタンなので、引く操作とタップを同じコントローラで見分ける（引いた後の click を読みにしない）。
// Pointer Events を使うのは、iPhone の指も Mac のマウスも同じ道で扱い、touch 固有の API を持たないため。
// 縦の動きはブラウザのスクロールに任せ（CSS の touch-action: pan-y）、横と決めてからカードを指に追従させる。
// 右へ引いても動かさない（右に充てる動作は無い。ADR 0012）

// 送るときに流す先。カード幅より大きくして画面の外まで出す
const FLY_OUT_RATIO = 1.2
// transitionend を待つ上限に足す余裕。合図が来なくても止まった頃に次へ進むため
const SETTLE_MARGIN_MS = 100

// Turbo は form の送信中に別の form が送られると先の送信を止めて応答を捨てる（先のカードが画面に残る）。
// 送信は全カードで 1 本の列に並べ、前の turbo:submit-end を待ってから次を送る
let submissions = Promise.resolve()

export default class extends Controller {
  static targets = ["card", "rail", "form", "read"]
  // 送る閾値（カード幅に対する比）と、送信の応答を待つ上限（秒）。dopamine.yml の値を view が渡す
  static values = { dismissRatio: Number, submitTimeoutSeconds: Number }

  disconnect() {
    this.settleCleanup?.()
    this.submitCleanup?.()
  }

  start(event) {
    this.swiped = false
    if (this.flying || this.opening || !event.isPrimary || event.button !== 0 || event.clientX < EDGE_PX) return
    // 行を覆う「読む」以外のボタンやリンクの上から始まった触りはタップとして押させる（押しながら引く操作は要らない）
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
    this.railTarget.classList.remove("swipe-settling")
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
    this.dx = Math.min(0, dx)
    this.render(this.dx)
  }

  end(event) {
    if (!this.tracking || event.pointerId !== this.pointerId) return

    this.tracking = false
    if (!this.horizontal) return

    if (-this.dx >= this.threshold()) {
      this.flyOut()
    } else {
      this.settle(0)
    }
  }

  cancel(event) {
    if (!this.tracking || event.pointerId !== this.pointerId) return

    this.tracking = false
    if (this.horizontal) this.settle(0)
  }

  // 指がカードの外へ出ても pointermove を受け続ける。対応する実 pointer の無い合成イベントでは NotFoundError になるので無視する
  capture() {
    try {
      this.cardTarget.setPointerCapture(this.pointerId)
    } catch {
      // 捕まえられなくても追従はできる
    }
  }

  threshold() {
    return this.cardTarget.offsetWidth * this.dismissRatioValue
  }

  // 引いた幅だけ背景を伸ばし、閾値に届いたら色を変えて「離せば消える」と知らせる
  render(dx) {
    const progress = Math.min(1, -dx / this.threshold())
    // 一覧の行は横へ平らに滑らせる（傾けると隣の行と背景の丸に食い込む）
    this.cardTarget.style.transform = dx === 0 ? "" : `translateX(${dx}px)`
    this.railTarget.style.opacity = progress
    this.railTarget.style.width = `${-dx}px`
    this.railTarget.classList.toggle("swipe-armed", progress >= 1)
  }

  // 離した後の動き（戻る・流れ出す）は CSS の transition に任せ、止まってから done を呼ぶ。
  // 長さは CSS から読む（reduced motion で 0 なら待たない）ので、CSS を変えてもここは変えない
  settle(dx, done = () => {}) {
    this.settleCleanup?.()
    const card = this.cardTarget
    card.classList.add("swipe-settling")
    this.railTarget.classList.add("swipe-settling")
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

  // 画面の外まで流してから送る。先に送ると Turbo の差し替えでカードが途中で消える。
  // 流している間と送信中は次の触りを受けない
  flyOut() {
    this.flying = true
    this.settle(-this.cardTarget.offsetWidth * FLY_OUT_RATIO, () => this.submit())
  }

  // 送れなかったら（圏外など）行を戻して、もう一度引けるようにする
  submit() {
    this.enqueue(this.formTarget, null, (success) => { if (!success) this.restore() })
  }

  enqueue(form, submitter, done) {
    submissions = submissions.then(() => new Promise((resolve) => {
      if (!form.isConnected) return resolve()

      // 列は必ず進める。結果を待たずに外されても（画面を移って行が消えた）ここで解いて、次の行が止まらないようにする
      const finish = () => {
        clearTimeout(timer)
        document.removeEventListener("turbo:submit-end", ended)
        this.submitCleanup = null
        resolve()
      }
      const ended = (event) => {
        if (event.target !== form) return

        finish()
        done(event.detail.success)
      }
      // 応答が来ないまま列を止めない。次の送信に進む（届いていれば後から Turbo が差し替える。送信中の「読む」のボタンは Turbo が押せなくしたまま）
      const timer = setTimeout(() => { finish(); done(false) }, this.submitTimeoutSecondsValue * 1000)
      document.addEventListener("turbo:submit-end", ended)
      this.submitCleanup = finish
      form.requestSubmit(submitter)
    }))
  }

  // 「読む」のボタンの click。横へ引いた触りの後に click が来る端末でも読まない（引いて戻した行が開いてしまう）。
  // キーボードの Enter / Space（detail が 0）は指の動きと関係ないので通す。
  // 送信は興味なしと同じ列に並べる（送信中の興味なしの応答を Turbo に捨てさせない）。二度押しでルーレットを重ねない
  open(event) {
    event.preventDefault()
    const swiped = this.swiped && event.detail > 0
    this.swiped = false
    if (swiped || this.flying || this.opening) return

    this.opening = true
    this.enqueue(this.readTarget.form, this.readTarget, () => { this.opening = false })
  }

  restore() {
    this.settle(0, () => { this.flying = false })
  }
}
