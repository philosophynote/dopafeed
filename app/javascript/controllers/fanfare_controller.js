import { Controller } from "@hotwired/stimulus"

// 演出は押せば即終わる（dopairb と同じ）。消すのは動きだけで、何が起きたかの文字は残す
export default class extends Controller {
  skip() {
    this.element.classList.add("is-settled")
  }
}
