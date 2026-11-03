import { Controller } from "@hotwired/stimulus"

// 記事から戻ってきた瞬間に、読了を記録する form を送る。
// iOS の standalone ではアプリ内シートを閉じると visibilitychange、Safari の戻るは pageshow（bfcache）か
// back_forward の遷移で戻ってくる。開き直し（navigate）では送らず、ボタンで記録してもらう
export default class extends Controller {
  connect() {
    this.submitted = false
    this.onVisibilityChange = () => { if (document.visibilityState === "visible") this.submit() }
    this.onPageShow = (event) => { if (event.persisted) this.submit() }
    document.addEventListener("visibilitychange", this.onVisibilityChange)
    window.addEventListener("pageshow", this.onPageShow)
    if (this.returnedByHistory()) this.submit()
  }

  disconnect() {
    document.removeEventListener("visibilitychange", this.onVisibilityChange)
    window.removeEventListener("pageshow", this.onPageShow)
  }

  returnedByHistory() {
    const [navigation] = performance.getEntriesByType("navigation")
    return navigation !== undefined && navigation.type === "back_forward"
  }

  submit() {
    if (this.submitted) return
    this.submitted = true
    this.element.requestSubmit()
  }
}
