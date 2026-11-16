import { Controller } from "@hotwired/stimulus"
import { play } from "controllers/sfx"

const COUNT_UP_MS = 600

// 戻ってきたときは読むつもりのことが多いので、モードを写し・bfcache・ブラウザのフォーム復元に持ち越さない。
// コンボはサーバーに残さない。読了の「n 連続」やストリークに混ぜると、消すだけで読書の報酬が増える
export default class extends Controller {
  static targets = ["list", "switch", "status", "combo", "count", "result", "resultCount", "resultTime", "resultPace"]
  static outlets = ["swipe"]

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
    const deleting = event.target.value === "delete"
    if (deleting === this.deleting) return

    this.deleting = deleting
    this.element.toggleAttribute("data-delete-mode", deleting)
    this.syncReadable(deleting)
    this.syncSwitch()
    if (deleting) {
      this.swipeOutlets.forEach((row) => row.collapse())
      this.startedAt = performance.now()
      this.counted = new Set()
      this.late = new Set()
      this.setCombo(0)
    } else if (this.combo > 0) {
      this.showResult(this.combo, performance.now() - this.startedAt)
    }
  }

  // 応答を待たずに押した時点で数える。応答で数えると、続けて押してすぐ「読む」に戻したとき、まだ列に並んでいる分がリザルトから抜ける
  removed({ detail: { form } }) {
    if (!this.deleting) return

    this.late.delete(this.key(form))
    this.counted.add(this.key(form))
    this.setCombo(this.combo + 1)
    // sfx の combo は 2 から上がり始める
    play("combo", this.combo + 1)
    this.countTarget.classList.remove("combo-pop")
    void this.countTarget.offsetWidth
    this.countTarget.classList.add("combo-pop")
  }

  // 待ちの上限を越えた送信は止めずに列だけ進めるので、失敗に見えた削除の成功が後から届くことがある。そのときは数え直す
  removeFailed({ detail: { form } }) {
    if (this.uncount(form)) this.late.add(this.key(form))
  }

  // 「元に戻す」は列で飛ばされることがあるので応答で引く。数えた回の削除だけを引き、前の回のトーストで今の回のコンボは減らさない
  submitted(event) {
    const form = event.target
    if (!this.deleting || !event.detail.success || !(form instanceof HTMLFormElement)) return
    if (!new URL(form.action).pathname.endsWith("/dismissal")) return

    if (form.querySelector("input[name='_method']")?.value === "delete") {
      this.uncount(form)
    } else if (this.late.delete(this.key(form))) {
      this.counted.add(this.key(form))
      this.setCombo(this.combo + 1)
    }
  }

  uncount(form) {
    if (!this.deleting || !this.counted.delete(this.key(form))) return false

    this.setCombo(this.combo - 1)
    return true
  }

  key(form) {
    return new URL(form.action).pathname
  }

  setCombo(combo) {
    this.combo = combo
    if (this.hasCountTarget) this.countTarget.textContent = combo
  }

  showResult(count, elapsedMs) {
    const seconds = Math.floor(elapsedMs / 1000)
    const minutes = Math.floor(seconds / 60)
    this.resultTimeTarget.textContent = minutes > 0 ? `${minutes} 分 ${seconds % 60} 秒` : `${seconds} 秒`
    this.resultPaceTarget.textContent = `${(elapsedMs / 1000 / count).toFixed(1)} 秒`
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
    this.deleting = false
    this.counted = new Set()
    this.late = new Set()
    this.setCombo(0)
    this.element.removeAttribute("data-delete-mode")
    if (this.hasResultTarget && this.resultTarget.open) this.resultTarget.close()
    if (!this.hasListTarget) return

    this.syncReadable(false)
    this.syncSwitch()
  }

  // 削除モードの間は 0 本になっても残す。消すと「読む」に戻せない
  syncSwitch() {
    if (!this.hasSwitchTarget) return

    const empty = !this.listTarget.querySelector(":scope > li:not([hidden])")
    this.switchTarget.hidden = empty && !this.deleting
  }

  // pointer-events を止めるだけでは、Tab と VoiceOver に押しても何も起きない「読む」が行の数だけ残る。
  // ステータスの行もコンボの下に隠れたまま押せる。後から差し込まれた行（取り消しで戻った行）は swipe が繋がったときに合わせる
  syncReadable(deleting) {
    if (this.hasStatusTarget) this.statusTarget.inert = deleting
    this.listTarget.querySelectorAll("[data-swipe-target~='read']").forEach((button) => { button.inert = deleting })
  }
}
