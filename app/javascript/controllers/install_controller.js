import { Controller } from "@hotwired/stimulus"

// ホーム画面から開いているか（standalone）で、見せる注記を切り替える。
// 判定は標準の display-mode と、iOS Safari だけが持つ navigator.standalone の両方を見る（iOS の版で返り方が揺れるため）。
// サーバーには分からないので JS で決める。JS が無いときは Safari のタブ向けの注記が出たまま
export default class extends Controller {
  static targets = ["browser", "standalone"]

  connect() {
    const standalone = window.matchMedia("(display-mode: standalone)").matches || navigator.standalone === true
    this.browserTargets.forEach((element) => { element.hidden = standalone })
    this.standaloneTargets.forEach((element) => { element.hidden = !standalone })
  }
}
