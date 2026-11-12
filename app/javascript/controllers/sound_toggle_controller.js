import { Controller } from "@hotwired/stimulus"
import { enabled, play, setEnabled } from "controllers/sfx"

// 端末ごとの設定なのでサーバーに送らない（音を出すかは、その端末をどこで使うかで決まる）
export default class extends Controller {
  connect() {
    this.render()
  }

  toggle() {
    const on = !enabled()
    setEnabled(on)
    this.render()
    if (on) play("tap")
  }

  render() {
    this.element.setAttribute("aria-checked", String(enabled()))
  }
}
