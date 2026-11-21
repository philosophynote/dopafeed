import { Controller } from "@hotwired/stimulus"
import { play } from "controllers/sfx"

const COUNT_UP_MS = 600

// 戻ってきたときは読むつもりのことが多いので、モードを写し・bfcache・ブラウザのフォーム復元に持ち越さない。
// コンボはサーバーに残さない。読了の「n 連続」やストリークに混ぜると、消すだけで読書の報酬が増える
export default class extends Controller {
  static targets = ["list", "switch", "status", "combo", "count", "band", "cheer", "burst", "result", "resultCount", "resultTime", "resultPace", "resultBreakdown"]
  static outlets = ["swipe"]
  static values = { smallEvery: Number, largeEvery: Number }

  connect() {
    this.reset()
    // 行は Turbo Stream が隠したり戻したりする。:has() は入れ子にできないので、ヘッダの切り替えは CSS では隠せない
    if (this.hasListTarget) {
      this.observer = new MutationObserver(() => this.syncSwitch())
      this.observer.observe(this.listTarget, { childList: true, subtree: true, attributeFilter: ["hidden"] })
    }
  }

  disconnect() {
    this.observer?.disconnect()
    cancelAnimationFrame(this.countUp)
  }

  toggle(event) {
    const processing = event.target.value === "process"
    if (processing === this.processing) return

    this.processing = processing
    this.element.toggleAttribute("data-process-mode", processing)
    this.syncReadable(processing)
    this.syncSwitch()
    if (processing) {
      this.swipeOutlets.forEach((row) => row.collapse())
      this.startedAt = performance.now()
      this.counted = new Set()
      this.late = new Set()
      this.setCombo(0)
      this.clearMilestones()
    } else if (this.combo > 0) {
      this.showResult(this.combo, performance.now() - this.startedAt)
    }
  }

  processed({ detail: { form } }) {
    if (!this.processing) return

    this.late.delete(this.key(form))
    this.counted.add(this.key(form))
    this.setCombo(this.combo + 1)
    play("melody", this.combo)
    this.restartAnimation(this.countTarget, "combo-pop")
    this.celebrate()
  }

  // 待ちの上限を越えた送信は止めずに列だけ進めるので、失敗に見えた送信の成功が後から届くことがある。そのときは数え直す
  processFailed({ detail: { form } }) {
    if (this.uncount(form)) this.late.add(this.key(form))
  }

  // 「元に戻す」は列で飛ばされることがあるので応答で引く。数えた回の削除と保存だけを引き、前の回のトーストで今の回のコンボは減らさない
  submitted(event) {
    const form = event.target
    if (!this.processing || !event.detail.success || !(form instanceof HTMLFormElement)) return
    if (!this.kind(form)) return

    if (form.querySelector("input[name='_method']")?.value === "delete") {
      this.uncount(form)
    } else if (this.late.delete(this.key(form))) {
      this.counted.add(this.key(form))
      this.setCombo(this.combo + 1)
    }
  }

  // 元に戻して届き直すたびに出すと、戻して払うだけで報酬が出る。大と小が重なる数では大だけ（演出は一度に一番大きい 1 つ。ADR 0022）。
  // 後から届いた成功で数え直したときは呼ばない。払っていない瞬間に節目の音だけが鳴る
  celebrate() {
    if (this.combo <= this.best) return
    this.best = this.combo

    if (this.reached(this.largeEveryValue)) {
      this.cheer("great", "GREAT!!")
      this.bandTarget.classList.add("is-great")
      if (!matchMedia("(prefers-reduced-motion: reduce)").matches) this.restartAnimation(this.burstTarget, "is-bursting")
      play("combo_great")
    } else if (this.reached(this.smallEveryValue)) {
      this.cheer("nice", "NICE!")
      this.restartAnimation(this.bandTarget, "is-nice")
      play("combo_nice")
    }
  }

  reached(every) {
    return every > 0 && this.combo % every === 0
  }

  cheer(tier, text) {
    if (!this.hasCheerTarget) return

    this.cheerTarget.textContent = text
    this.restartAnimation(this.cheerTarget, `is-${tier}`)
  }

  clearMilestones() {
    this.best = 0
    if (!this.hasBandTarget) return

    this.bandTarget.classList.remove("is-nice", "is-great")
    this.burstTarget.classList.remove("is-bursting")
  }

  restartAnimation(element, className) {
    element.classList.remove(className)
    void element.offsetWidth
    element.classList.add(className)
  }

  uncount(form) {
    if (!this.processing || !this.counted.delete(this.key(form))) return false

    this.setCombo(this.combo - 1)
    return true
  }

  key(form) {
    return new URL(form.action).pathname
  }

  kind(form) {
    return this.key(form).match(/\/(dismissal|bookmark)$/)?.[1]
  }

  // 節目の文字は aria-live の中にあるので、消えた後も残すと次の数でも読み上げられる。動きを減らす設定では見えたまま残る
  setCombo(combo) {
    this.combo = combo
    if (this.hasCountTarget) this.countTarget.textContent = combo
    if (this.hasCheerTarget) {
      this.cheerTarget.textContent = ""
      this.cheerTarget.classList.remove("is-nice", "is-great")
    }
  }

  showResult(count, elapsedMs) {
    const seconds = Math.floor(elapsedMs / 1000)
    const minutes = Math.floor(seconds / 60)
    this.resultTimeTarget.textContent = minutes > 0 ? `${minutes} 分 ${seconds % 60} 秒` : `${seconds} 秒`
    this.resultPaceTarget.textContent = `${(elapsedMs / 1000 / count).toFixed(1)} 秒`
    const kinds = [...this.counted].map((key) => key.split("/").pop())
    this.resultBreakdownTarget.textContent = `削除 ${kinds.filter((kind) => kind === "dismissal").length} ・ 保存 ${kinds.filter((kind) => kind === "bookmark").length}`
    this.resultTarget.showModal()
    play("fanfare")
    this.countUpTo(count)
  }

  countUpTo(count) {
    cancelAnimationFrame(this.countUp)
    if (matchMedia("(prefers-reduced-motion: reduce)").matches) {
      this.resultCountTarget.textContent = count
      return
    }

    let start
    const step = (now) => {
      start ??= now
      const progress = Math.min(1, (now - start) / COUNT_UP_MS)
      this.resultCountTarget.textContent = Math.round(count * progress)
      if (progress < 1) this.countUp = requestAnimationFrame(step)
    }
    this.resultCountTarget.textContent = 0
    this.countUp = requestAnimationFrame(step)
  }

  // 中身は余白ごと内側の要素が覆うので、dialog 自身に来る click は背景を押したときだけ
  closeOnBackdrop(event) {
    if (event.target === this.resultTarget) this.resultTarget.close()
  }

  reset() {
    const read = this.element.querySelector("input[name=mode][value=read]")
    if (read) read.checked = true
    this.processing = false
    this.counted = new Set()
    this.late = new Set()
    this.setCombo(0)
    this.clearMilestones()
    this.element.removeAttribute("data-process-mode")
    if (this.hasResultTarget && this.resultTarget.open) this.resultTarget.close()
    if (!this.hasListTarget) return

    this.syncReadable(false)
    this.syncSwitch()
  }

  // 処理モードの間は 0 本になっても残す。消すと「読む」に戻せない
  syncSwitch() {
    if (!this.hasSwitchTarget) return

    const empty = !this.listTarget.querySelector(":scope > li:not([hidden])")
    this.switchTarget.hidden = empty && !this.processing
  }

  // pointer-events を止めるだけでは、Tab と VoiceOver に押しても何も起きない「読む」が行の数だけ残る。
  // ステータスの行もコンボの下に隠れたまま押せる。後から差し込まれた行（取り消しで戻った行）は swipe が繋がったときに合わせる
  syncReadable(processing) {
    if (this.hasStatusTarget) this.statusTarget.inert = processing
    this.listTarget.querySelectorAll("[data-swipe-target~='read']").forEach((button) => { button.inert = processing })
  }
}
