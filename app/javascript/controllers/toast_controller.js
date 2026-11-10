import { Controller } from "@hotwired/stimulus"
import { enqueue, swipeCount } from "controllers/submission_queue"

// 画面下の取り消しのトースト。秒数（dopamine.yml の toast.visible_seconds を view が渡す）が経ったら自分を外す。
// 0（鍵が無い）なら外さず、次のトーストに置き換わるか画面を移るまで残す。
// 「元に戻す」は行のスワイプと同じ送信の列に並べる。並べずに送ると、応答待ちのスワイプの送信を Turbo が止め、消したはずの行が画面に戻る。
// トーストが出た後に別の行を片付ける送信が出ていたら送らない。その応答でトーストは置き換わるので、押したのは前の行の取り消しで、これから見えるトーストのではない
export default class extends Controller {
  static values = { seconds: Number, submitTimeoutSeconds: Number }

  connect() {
    this.swipesAtShow = swipeCount()
    if (this.secondsValue > 0) this.timer = setTimeout(() => this.element.remove(), this.secondsValue * 1000)
  }

  disconnect() {
    clearTimeout(this.timer)
  }

  // 「元に戻す」の form の submit。Turbo より先に止めて列に並べ、順番が来たら送り直す（送り直しの submit はそのまま Turbo に渡す）
  undo(event) {
    if (this.releasing) return

    event.preventDefault()
    // 押した後に消えると、指の下の行に click が抜ける
    clearTimeout(this.timer)
    if (this.queued) return

    this.queued = true
    const form = event.target
    enqueue(() => new Promise((resolve) => {
      if (!form.isConnected || swipeCount() > this.swipesAtShow) {
        this.queued = false
        return resolve()
      }

      // 送れなかったとき（圏外・サーバーの失敗）はトーストが残るので、もう一度押せるようにする
      const finish = () => {
        clearTimeout(timer)
        document.removeEventListener("turbo:submit-end", ended)
        this.queued = false
        resolve()
      }
      const ended = (e) => { if (e.target === form) finish() }
      // 応答が来なくても列は止めない（届いていれば後から Turbo が差し替える）
      const timer = setTimeout(finish, this.submitTimeoutSecondsValue * 1000)
      document.addEventListener("turbo:submit-end", ended)
      this.releasing = true
      form.requestSubmit()
      this.releasing = false
    }))
  }
}
