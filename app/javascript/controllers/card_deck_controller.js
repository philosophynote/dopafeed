import { Controller } from "@hotwired/stimulus"

// めくれるカードの束の後始末。めくり自体は CSS が動かす。
// Turbo がスナップショットを取る前にめくりの印（card-reveal・style・裏面）を落とし、履歴で戻ってきたときにめくり直さない。
// 一度きりだからめくりが効く（全画面の方は reveal が受け持つ）
export default class extends Controller {
  settle() {
    this.element.querySelectorAll(".card-reveal").forEach((card) => {
      card.classList.remove("card-reveal")
      card.removeAttribute("style")
      card.querySelector(".card-back")?.remove()
    })
  }
}
