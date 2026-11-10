import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"
import { EDGE_PX, LOCK_PX } from "controllers/swipe_thresholds"
import { enqueue as enqueueSubmission, noteSwipeFailed, noteSwipeSent } from "controllers/submission_queue"

// 一覧の 1 行。左へ引いて離すと form（Main では「興味なし」、保存の一覧では「保存を外す」）を、右へ引いて離すと saveForm（「保存」）を送り、
// 触れて離すと「読む」の form を送る（読み終えた行ではリンクを開く）。記録と差し替えはサーバー（Turbo Stream）の仕事で、ここは指の動きを form の送信に変えるだけ。
// 行の下に広げる欄（detail）がある行では、欄は最初の「読む」の応答が埋め、それからは送らずに開閉だけする（抽選も要約の Job も 1 回で足りる）。
// 行全体が「読む」のボタンなので、引く操作とタップを同じコントローラで見分ける（引いた後の click を読みにしない）。
// Pointer Events を使うのは、iPhone の指も Mac のマウスも同じ道で扱い、touch 固有の API を持たないため。
// 縦の動きはブラウザのスクロールに任せ（CSS の touch-action: pan-y）、横と決めてからカードを指に追従させる。
// 送る form の無い向き（保存の一覧の右）へは動かさない。
// 送るのは、閾値まで引いて離したときと、閾値の手前でも引いた向きへ速く払って離したとき（誤って消しても「元に戻す」で戻せるので、軽い払いで片付ける）。
// iOS が途中で指を取り上げた（pointercancel）ときも、閾値を越えていれば送る。戻すと、引ききった行が理由も無く戻って見える。
// 取り上げでは払いを見ない。取り上げは縦のスクロールや OS のジェスチャーなど、指が払うつもりでないときにも来る

// 送るときに流す先。カード幅より大きくして画面の外まで出す
const FLY_OUT_RATIO = 1.2
// transitionend を待つ上限に足す余裕。合図が来なくても止まった頃に次へ進むため
const SETTLE_MARGIN_MS = 100
// 払う速さは離す直前のこの長さの動きで測る（離した時刻までの平均）。それより前の動きを混ぜると、速く引いてから止めて離した指まで払いになる
const FLICK_WINDOW_MS = 100

// 最後に「読む」を押した印。応答は送った順に届くので、待つ間に押し直した行を後の応答で負かさないよう、開くのはこの印を持つ行だけにする
let latestTap = 0

export default class extends Controller {
  static targets = ["card", "rail", "saveRail", "form", "saveForm", "read", "detail"]
  // 送る閾値（カード幅に対する比）、払いと見なす速さ（px/ms。0 なら払いでは送らない）と払いでも要る引いた幅（px。少し滑ったタップを払いにしない）、
  // 送信の応答を待つ上限（秒）。dopamine.yml の値を view が渡す
  static values = { dismissRatio: Number, flickVelocity: Number, flickMinPx: Number, submitTimeoutSeconds: Number }

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
    this.samples = [{ t: event.timeStamp, x: event.clientX }]
    this.settleCleanup?.()
    this.cardTarget.classList.remove("swipe-settling")
    this.rails().forEach((rail) => rail.classList.remove("swipe-settling"))
  }

  move(event) {
    if (!this.tracking || event.pointerId !== this.pointerId) return

    const dx = event.clientX - this.startX
    const dy = event.clientY - this.startY
    this.samples.push({ t: event.timeStamp, x: event.clientX })
    this.samples = this.samples.filter((sample) => sample.t >= event.timeStamp - FLICK_WINDOW_MS)
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
    // 送る form の無い向きへは 0 で止める
    this.dx = Math.max(this.hasFormTarget ? -Infinity : 0, Math.min(this.hasSaveFormTarget ? Infinity : 0, dx))
    this.render(this.dx)
  }

  end(event) {
    if (!this.tracking || event.pointerId !== this.pointerId) return

    this.tracking = false
    if (!this.horizontal) return

    const flicked = event.type === "pointerup" && this.flicked(event.timeStamp)
    if (this.dx !== 0 && (Math.abs(this.dx) >= this.threshold() || flicked)) {
      this.flyOut(Math.sign(this.dx))
    } else {
      this.settle(0)
    }
  }

  // 離す直前に、引いた向きへ速く動いていたか。指を止めると pointermove は来ないので、時間は離した時刻まで数える
  flicked(now) {
    if (!(this.flickVelocityValue > 0) || Math.abs(this.dx) < this.flickMinPxValue) return false

    const recent = this.samples.filter((sample) => sample.t >= now - FLICK_WINDOW_MS)
    const first = recent[0]
    const last = recent[recent.length - 1]
    const elapsed = now - first?.t
    // 時刻の差が無い動きは測れない（一度の跳びを払いにしない）
    if (recent.length < 2 || !(elapsed > 0)) return false

    const velocity = (last.x - first.x) / elapsed
    return Math.sign(velocity) === Math.sign(this.dx) && Math.abs(velocity) >= this.flickVelocityValue
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

  rails() {
    return this.hasSaveRailTarget ? [this.railTarget, this.saveRailTarget] : [this.railTarget]
  }

  // 引いた向きの背景だけを引いた幅だけ伸ばし、閾値に届いたら色を変えて「離せば送る」と知らせる。反対の背景は畳む
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

  // 離した後の動き（戻る・流れ出す）は CSS の transition に任せ、止まってから done を呼ぶ。
  // 長さは CSS から読む（reduced motion で 0 なら待たない）ので、CSS を変えてもここは変えない
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

  // 画面の外まで流してから送る。先に送ると Turbo の差し替えでカードが途中で消える。
  // 流している間と送信中は次の触りを受けない
  // direction は -1（左）か 1（右）
  flyOut(direction) {
    this.flying = true
    this.settle(direction * this.cardTarget.offsetWidth * FLY_OUT_RATIO, () => this.submit(direction))
  }

  // 送れなかったら（圏外など）行を戻して、もう一度引けるようにする
  submit(direction) {
    const form = direction > 0 ? this.saveFormTarget : this.formTarget
    const done = (success) => {
      if (success) return

      noteSwipeFailed()
      this.restore()
    }
    this.enqueue(form, null, done, { send: () => { this.stamp(form, noteSwipeSent()); form.requestSubmit() } })
  }

  // 送った回数を送信に付ける。応答のトーストがそれを持ち、後から来た送信に置き換わる側かを見分ける（submission_queue）
  stamp(form, count) {
    let field = form.elements.namedItem("swipe")
    if (!field) {
      field = Object.assign(document.createElement("input"), { type: "hidden", name: "swipe" })
      form.append(field)
    }
    field.value = count
  }

  enqueue(form, submitter, done, { stopOnTimeout = false, send = () => form.requestSubmit(submitter) } = {}) {
    enqueueSubmission(() => new Promise((resolve) => {
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

  // 「読む」のボタンの click。横へ引いた触りの後に click が来る端末でも読まない（引いて戻した行が開いてしまう）。
  // キーボードの Enter / Space（detail が 0）は指の動きと関係ないので通す。
  // 送信は興味なしと同じ列に並べる（送信中の興味なしの応答を Turbo に捨てさせない）。二度押しで送信を重ねない。
  // 応答を待つ印（awaiting）は欄が差し替わるまで持つ。Turbo は submit-end の後のフレームで差し替えるので、opening だけではその隙に 2 本目を送ってしまう
  // 読み終えた行の「読む」はリンク（Reader を開くだけで送るものが無い）。それでも遷移は同じ列の後ろで始める。
  // 遷移は送信中の form を止めるので、直前に引いた行の「保存を外す」が届く前に止まってしまう
  open(event) {
    const swiped = this.swiped && event.detail > 0
    this.swiped = false
    event.preventDefault()
    if (swiped || this.flying || this.opening || this.awaiting) return

    if (this.readTarget.tagName === "A") {
      const href = this.readTarget.href
      enqueueSubmission(() => Turbo.visit(href))
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

  // 中身の入った欄が繋がるのは、応答の差し替えか、Turbo のキャッシュから戻ったとき。
  // 開くのは自分が待っていた応答で、待つ間に他の行が押されていないときと、ボタンが開いた印を持っているとき（キャッシュの状態を保つ）だけ。
  // 最後に押した行を勝たせる（遅れて届いた応答が、後から開いた行を畳まない）
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

  // 開いたら知らせる。一度に開く行を 1 つにするのは受け取る側の仕事
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
