import { Controller } from "@hotwired/stimulus"

// 一覧で一度に広がるのは 1 行だけにする。開いた行（swipe）が swipe:expanded を流すと、他の行を畳む。
// 開いた欄をいくつも残すと一画面に並ぶ行が減り、どの要約を読んでいたか見失うため
export default class extends Controller {
  static outlets = ["swipe"]

  collapseOthers(event) {
    this.swipeOutlets.forEach((row) => {
      if (row.element !== event.target) row.collapse()
    })
  }
}
