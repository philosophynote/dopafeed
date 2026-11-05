// 診断用（マージしない）。iPhone のホーム画面アプリでシートを開いて閉じたとき、どの合図が来るかを画面の下に出す
import { Controller } from "@hotwired/stimulus"

const t0 = performance.now()
const lines = []
let box = null

function log(message) {
  const s = ((performance.now() - t0) / 1000).toFixed(1)
  lines.push(`${s}s ${message}`)
  while (lines.length > 14) lines.shift()
  if (box) box.textContent = lines.join("\n")
}

function setup() {
  if (window.__eventLog) return
  window.__eventLog = log
  box = document.createElement("pre")
  box.setAttribute("style", "position:fixed;left:0;right:0;bottom:0;z-index:9999;margin:0;padding:6px 8px;max-height:45vh;overflow:auto;background:rgba(0,0,0,.82);color:#7CFC00;font:11px/1.35 ui-monospace,monospace;white-space:pre-wrap;pointer-events:none")
  document.documentElement.appendChild(box)

  document.addEventListener("visibilitychange", () => log(`visibilitychange ${document.visibilityState}`))
  window.addEventListener("focus", () => log("window focus"))
  window.addEventListener("blur", () => log("window blur"))
  window.addEventListener("pageshow", (e) => log(`pageshow persisted=${e.persisted}`))
  window.addEventListener("pagehide", (e) => log(`pagehide persisted=${e.persisted}`))
  document.addEventListener("freeze", () => log("freeze"))
  document.addEventListener("resume", () => log("resume"))
  window.addEventListener("resize", () => log(`resize ${innerWidth}x${innerHeight}`))
  document.addEventListener("click", (e) => { if (e.target.closest("a[target=_blank]")) log("click 記事を開く") }, true)

  let focused = document.hasFocus()
  let last = performance.now()
  setInterval(() => {
    const now = performance.now()
    const gap = now - last
    last = now
    if (gap > 2000) log(`timer gap ${(gap / 1000).toFixed(1)}s`)
    const f = document.hasFocus()
    if (f !== focused) { focused = f; log(`hasFocus ${f}`) }
  }, 500)
  log(`start visibility=${document.visibilityState} hasFocus=${document.hasFocus()} standalone=${navigator.standalone}`)
}

export default class extends Controller {
  connect() { setup() }
}
