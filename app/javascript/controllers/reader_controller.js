import { Controller } from "@hotwired/stimulus"

// 記事の末尾（「読み終えた」の form）がスクロールで画面に入ってきたら、1 回だけ送る。
// 最初から見えているとき（短い記事・要約だけの記事）は送らない。読む前に判定が走って未完になるので、
// 一度画面の外にあった後に入ってきたときだけ自動で送り、それ以外はボタンを押してもらう
export default class extends Controller {
  connect() {
    this.armed = false
    this.observer = new IntersectionObserver((entries) => {
      const entry = entries[entries.length - 1]
      if (!entry.isIntersecting) {
        this.armed = true
      } else if (this.armed) {
        this.observer.disconnect()
        this.element.requestSubmit()
      }
    })
    this.observer.observe(this.element)
  }

  disconnect() {
    this.observer.disconnect()
  }
}
