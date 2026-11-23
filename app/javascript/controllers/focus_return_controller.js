import { Controller } from "@hotwired/stimulus"

// Turbo は送信の間ボタンを disabled にし、ブラウザはそこでフォーカスを外す。
// キーボードや VoiceOver で続けて押せるよう、送信が終わったら押したボタン（差し替わっていれば同じ id）へ戻す
export default class extends Controller {
  restore(event) {
    const id = event.detail.formSubmission?.submitter?.id
    if (!id) return

    requestAnimationFrame(() => document.getElementById(id)?.focus({ preventScroll: true }))
  }
}
