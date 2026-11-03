import { Controller } from "@hotwired/stimulus"

// 記事から戻ってきた瞬間に、読了を記録する form を送る。
// 記事へ出るリンク（ルーレットが止まって踏むもの、Jackpot の「受け取って読む」）の click で sessionStorage に印を付け、
// 戻りの合図があったとき印があれば 1 回だけ送る。「読む」の submit で付けないのは、Jackpot から戻るで Main に帰った
// だけの人を、次に画面が見えた拍子に読了扱いにしないため。
// 合図は iOS の standalone ならアプリ内シートを閉じたときの visibilitychange、Safari の戻るなら
// pageshow（bfcache 復元）か back_forward の再読込。
// 印を文書に持たないのは、戻り先が「読む」を押す前に描いた文書のままで、押した事実を文書が知らないから。
// 開き直し（navigate）では送らず、ピルのボタンで記録してもらう
const KEY = "dopafeed.reading-opened"

export default class extends Controller {
  static targets = ["form"]

  connect() {
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

  // 記事へ出るリンクが踏まれた
  opened() {
    this.mark(true)
  }

  // ピルのボタンで手で記録した。戻りの合図で二度送らない
  returned() {
    this.mark(false)
  }

  returnedByHistory() {
    const [navigation] = performance.getEntriesByType("navigation")
    return navigation !== undefined && navigation.type === "back_forward"
  }

  submit() {
    // Turbo のプレビュー描画でも connect が走るので、本描画だけが送る
    if (document.documentElement.hasAttribute("data-turbo-preview")) return
    if (!this.hasFormTarget || !this.marked()) return
    this.mark(false)
    this.formTarget.requestSubmit()
  }

  // プライベートブラウズなどで sessionStorage が使えなくても画面は壊さない
  marked() {
    try { return sessionStorage.getItem(KEY) !== null } catch { return false }
  }

  mark(on) {
    try { on ? sessionStorage.setItem(KEY, "1") : sessionStorage.removeItem(KEY) } catch { /* 印無しで進む */ }
  }
}
