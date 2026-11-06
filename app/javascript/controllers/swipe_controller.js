import { Controller } from "@hotwired/stimulus"

// 一覧のカード 1 枚。左へ引いて離すと「興味なし」の form を送る。記録と差し替えはサーバー（Turbo Stream）の仕事で、ここは指の動きを form の送信に変えるだけ。
// Pointer Events を使うのは、iPhone の指も Mac のマウスも同じ道で扱い、touch 固有の API を持たないため。
// 縦の動きはブラウザのスクロールに任せ（CSS の touch-action: pan-y）、横と決めてからカードを指に追従させる。
// 右へ引いても動かさない（右に充てる動作はまだ無い）

// 画面の左端からの横スワイプは iOS の「戻る」なので、この幅の中で始まった触りは拾わない
const EDGE_PX = 24
// 横か縦かを決めるまでの遊び。これより小さい動きはタップの揺れとして無視する
const LOCK_PX = 10
// カード幅に対して、ここまで引いて離すと送る。手前で離すと戻る
const DISMISS_RATIO = 0.4
// 引いている間に傾ける最大の角度。流れ出す感じを出すだけの演出
const MAX_TILT_DEG = 6
// 流れ出しの transition が無い（reduced motion）か transitionend が来ないときに送る保険
const SETTLE_FALLBACK_MS = 300

export default class extends Controller {
  static targets = ["card", "rail", "form"]

  start(event) {
    if (!event.isPrimary || event.button !== 0 || event.clientX < EDGE_PX) return
    // ボタンやリンクの上から始まった触りはタップとして押させる（押しながら引く操作は要らない）
    if (event.target.closest("a, button, input, select, textarea")) return

    this.pointerId = event.pointerId
    this.startX = event.clientX
    this.startY = event.clientY
    this.tracking = true
    this.horizontal = false
    this.dx = 0
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
      this.capture()
    }
    this.dx = Math.min(0, dx)
    this.render(this.dx)
    event.preventDefault()
  }

  end(event) {
    if (!this.tracking || event.pointerId !== this.pointerId) return

    this.tracking = false
    if (!this.horizontal) return

    this.cardTarget.classList.add("swipe-settling")
    if (-this.dx >= this.threshold()) {
      this.flyOut()
    } else {
      this.render(0)
    }
  }

  cancel(event) {
    if (!this.tracking || event.pointerId !== this.pointerId) return

    this.tracking = false
    this.cardTarget.classList.add("swipe-settling")
    this.render(0)
  }

  // 指がカードの外へ出ても pointermove を受け続ける。JS から合成した pointer（spec）は捕まえられないので失敗は無視する
  capture() {
    try {
      this.cardTarget.setPointerCapture(this.pointerId)
    } catch {
      // 合成イベントには対応する pointer が無い
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

  // 画面の外まで流してから送る。先に送ると Turbo の差し替えでカードが途中で消える
  flyOut() {
    this.render(-this.cardTarget.offsetWidth * 1.2)
    let sent = false
    const send = () => {
      if (sent) return
      sent = true
      this.submit()
    }
    this.cardTarget.addEventListener("transitionend", send, { once: true })
    setTimeout(send, SETTLE_FALLBACK_MS)
  }

  // Turbo は form の送信中に別の form が送られると先の送信を止めて応答を捨てる（先のカードが画面に残る）。
  // 送信中の form があれば、その終わりを待ってから送る
  submit() {
    const busy = document.querySelector("form[aria-busy='true']")
    if (busy) {
      document.addEventListener("turbo:submit-end", () => this.submit(), { once: true })
      return
    }
    this.formTarget.requestSubmit()
  }
}
