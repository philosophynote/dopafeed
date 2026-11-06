import { Controller } from "@hotwired/stimulus"

// 一覧のカード 1 枚。左へ引いて離すと「興味なし」の form を送る。記録と差し替えはサーバー（Turbo Stream）の仕事で、ここは指の動きを form の送信に変えるだけ。
// Pointer Events を使うのは、iPhone の指も Mac のマウスも同じ道で扱い、touch 固有の API を持たないため。
// 縦の動きはブラウザのスクロールに任せ（CSS の touch-action: pan-y）、横と決めてからカードを指に追従させる。
// 右へ引いても動かさない（右に充てる動作は無い。ADR 0012）

// 画面の左端からの横スワイプは iOS の「戻る」なので、この幅の中で始まった触りは拾わない
const EDGE_PX = 24
// 横か縦かを決めるまでの遊び。これより小さい動きはタップの揺れとして無視する
const LOCK_PX = 10
// カード幅に対して、ここまで引いて離すと送る。手前で離すと戻る
const DISMISS_RATIO = 0.4
// 送るときに流す先。カード幅より大きくして画面の外まで出す
const FLY_OUT_RATIO = 1.2
// 引いている間に傾ける最大の角度。流れ出す感じを出すだけの演出
const MAX_TILT_DEG = 6
// transitionend を待つ上限に足す余裕。合図が来なくても止まった頃に次へ進むため
const SETTLE_MARGIN_MS = 100
// 1 回の送信を待つ上限。turbo:submit-end が来ないまま列が止まらないため。過ぎたら送れなかった扱いにする
const SUBMIT_TIMEOUT_MS = 10000

// Turbo は form の送信中に別の form が送られると先の送信を止めて応答を捨てる（先のカードが画面に残る）。
// 送信は全カードで 1 本の列に並べ、前の turbo:submit-end を待ってから次を送る
let submissions = Promise.resolve()

export default class extends Controller {
  static targets = ["card", "rail", "form"]

  disconnect() {
    this.settleCleanup?.()
    this.submitCleanup?.()
  }

  start(event) {
    if (this.flying || !event.isPrimary || event.button !== 0 || event.clientX < EDGE_PX) return
    // ボタンやリンクの上から始まった触りはタップとして押させる（押しながら引く操作は要らない）
    if (event.target.closest("a, button, input, select, textarea")) return

    this.pointerId = event.pointerId
    this.startX = event.clientX
    this.startY = event.clientY
    this.tracking = true
    this.horizontal = false
    this.dx = 0
    this.settleCleanup?.()
    this.cardTarget.classList.remove("swipe-settling")
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
    return this.cardTarget.offsetWidth * DISMISS_RATIO
  }

  render(dx) {
    const progress = Math.min(1, -dx / this.threshold())
    this.cardTarget.style.transform = dx === 0 ? "" : `translateX(${dx}px) rotate(${-MAX_TILT_DEG * progress}deg)`
    this.railTarget.style.opacity = progress
  }

  // 離した後の動き（戻る・流れ出す）は CSS の transition に任せ、止まってから done を呼ぶ。
  // 長さは CSS から読む（reduced motion で 0 なら待たない）ので、CSS を変えてもここは変えない
  settle(dx, done = () => {}) {
    this.settleCleanup?.()
    const card = this.cardTarget
    card.classList.add("swipe-settling")
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

  submit() {
    submissions = submissions.then(() => new Promise((resolve) => {
      const form = this.formTarget
      if (!form.isConnected) return resolve()

      // 列は必ず進める。結果を待たずに外されても（画面を移ってカードが消えた）ここで解いて、次のカードが止まらないようにする
      const finish = () => {
        clearTimeout(timer)
        document.removeEventListener("turbo:submit-end", ended)
        this.submitCleanup = null
        resolve()
      }
      // 送れなかったら（圏外など）カードを戻して、もう一度引けるようにする
      const ended = (event) => {
        if (event.target !== form) return

        finish()
        if (!event.detail.success) this.restore()
      }
      // 応答が来ないまま待ち続けない。送れなかった扱いでカードを戻す（届いていれば後から Turbo が差し替える）
      const timer = setTimeout(() => { finish(); this.restore() }, SUBMIT_TIMEOUT_MS)
      document.addEventListener("turbo:submit-end", ended)
      this.submitCleanup = finish
      form.requestSubmit()
    }))
  }

  restore() {
    this.settle(0, () => { this.flying = false })
  }
}
