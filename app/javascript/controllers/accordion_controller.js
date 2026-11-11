import { Controller } from "@hotwired/stimulus"

// 複数の欄を残すと一覧が狭くなり、どの要約を読んでいたか見失う。
export default class extends Controller {
  static outlets = ["swipe"]

  collapseOthers(event) {
    this.swipeOutlets.forEach((row) => {
      if (row.element !== event.target) row.collapse()
    })
  }
}
