import { Controller } from "@hotwired/stimulus"

const WIDTH = 1080
const HEIGHT = 1350
const PAD = 72
const FONT = '-apple-system, "Hiragino Sans", "Hiragino Kaku Gothic ProN", "Noto Sans JP", sans-serif'
const ORANGE = "#ea580c"
const BAR = "#fb923c"
const INK = "#111827"
const MUTED = "#6b7280"
const FAINT = "#d1d5db"
const CLOSING = "、。，．！？）」』】"
const COMMENT_BOTTOM = HEIGHT - PAD - 60
// 保存の画面が URL を読み終える前に解放すると、保存できないブラウザがある
const REVOKE_AFTER_MS = 60000

export default class extends Controller {
  static values = { card: Object, filename: String }

  // iOS は押した操作の中でしか共有シートを開かない。押してから描くと待ちの間に操作の扱いが切れうるので、表示したときに描いておく
  connect() {
    this.element.disabled = false
    this.file = null
    this.preparing = this.render().then((blob) => (this.file = new File([blob], this.filenameValue, { type: "image/png" })))
    this.preparing.catch((error) => console.error(error))
  }

  // 処理中に離れると、押せない状態のまま Turbo のキャッシュに残る
  reset() {
    this.element.disabled = false
  }

  async share() {
    this.element.disabled = true
    let file = null
    try {
      file = this.file || await this.preparing
      if (navigator.canShare?.({ files: [file] })) {
        await navigator.share({ files: [file], title: this.cardValue.title })
      } else {
        this.download(file)
      }
    } catch (error) {
      // 共有シートを閉じただけなら何もしない。開けなかったときは、作った画像を保存させて押した結果を残す
      if (error.name === "NotAllowedError" && file) this.download(file)
      else if (error.name !== "AbortError") console.error(error)
    } finally {
      this.element.disabled = false
    }
  }

  download(file) {
    const url = URL.createObjectURL(file)
    const link = document.createElement("a")
    link.href = url
    link.download = file.name
    link.click()
    setTimeout(() => URL.revokeObjectURL(url), REVOKE_AFTER_MS)
  }

  render() {
    const canvas = document.createElement("canvas")
    canvas.width = WIDTH
    canvas.height = HEIGHT
    const ctx = canvas.getContext("2d")
    const card = this.cardValue

    ctx.fillStyle = "#fff7ed"
    ctx.fillRect(0, 0, WIDTH, HEIGHT)
    ctx.fillStyle = "#ffffff"
    this.roundRect(ctx, PAD / 2, PAD / 2, WIDTH - PAD, HEIGHT - PAD, 48)
    ctx.fill()

    let y = PAD + 56
    this.text(ctx, card.title, PAD, y, 56, INK, "900")
    this.text(ctx, card.range, WIDTH - PAD, y, 36, MUTED, "600", "right")
    y += 60
    this.text(ctx, `🔥 ${card.streak}`, PAD, y, 34, MUTED, "700")

    y += 120
    const count = card.count.toLocaleString("ja-JP")
    this.text(ctx, count, PAD, y, 120, ORANGE, "900")
    this.text(ctx, "本 読了", PAD + this.measure(ctx, count, 120, "900") + 20, y, 46, INK, "700")
    y += 54
    this.text(ctx, card.change, PAD, y, 36, card.up ? "#047857" : MUTED, "700")

    // 一番高い棒の上に本数の字が乗るので、その分を空ける
    y = this.bars(ctx, card, y + 76)
    y = this.stats(ctx, card, y + 24)
    if (card.comment) this.comment(ctx, card.comment, y + 24)

    this.text(ctx, card.footer, WIDTH / 2, HEIGHT - PAD + 4, 28, MUTED, "500", "center")
    return new Promise((resolve, reject) => canvas.toBlob((blob) => (blob ? resolve(blob) : reject(new Error("toBlob failed"))), "image/png"))
  }

  bars(ctx, card, top) {
    const height = 150
    const gap = 24
    const width = (WIDTH - PAD * 2 - gap * 6) / 7
    const peak = Math.max(...card.days.map((day) => day.count), 0)
    card.days.forEach((day, i) => {
      const x = PAD + i * (width + gap)
      const barHeight = peak > 0 ? Math.round((day.count / peak) * height) : 0
      ctx.fillStyle = BAR
      if (barHeight > 0) {
        this.roundRect(ctx, x, top + height - barHeight, width, barHeight, 14)
        ctx.fill()
        this.text(ctx, String(day.count), x + width / 2, top + height - barHeight - 12, 28, MUTED, "700", "center")
      }
      const color = day.state === "today" ? ORANGE : day.state === "future" ? FAINT : MUTED
      this.text(ctx, day.label, x + width / 2, top + height + 40, 30, color, "700", "center")
    })
    return top + height + 40
  }

  // 値が長いときは名前だけを「…」で詰め、後ろの本数は残す
  stats(ctx, card, top) {
    let y = top
    ctx.fillStyle = "#f3f4f6"
    ctx.fillRect(PAD, y, WIDTH - PAD * 2, 2)
    card.stats.forEach(([label, value, tail]) => {
      y += 50
      this.text(ctx, label, PAD, y, 32, MUTED, "600")
      const suffix = tail ? ` ${tail}` : ""
      const room = WIDTH - PAD * 2 - this.measure(ctx, label, 32, "600") - 32 - this.measure(ctx, suffix, 32, "800")
      this.text(ctx, `${this.fit(ctx, value, room, 32, "800")}${suffix}`, WIDTH - PAD, y, 32, INK, "800", "right")
    })
    return y
  }

  comment(ctx, comment, top) {
    const lineHeight = 44
    const room = Math.floor((COMMENT_BOTTOM - top - 80) / lineHeight)
    let lines = this.wrap(ctx, comment.body, WIDTH - PAD * 2 - 64, 30, "500")
    if (lines.length > room) lines = [...lines.slice(0, room - 1), this.fit(ctx, lines.slice(room - 1).join(""), WIDTH - PAD * 2 - 64, 30, "500")]
    ctx.fillStyle = "#fff7ed"
    this.roundRect(ctx, PAD, top, WIDTH - PAD * 2, 80 + lines.length * lineHeight, 28)
    ctx.fill()
    this.text(ctx, comment.label, PAD + 32, top + 52, 28, "#c2410c", "800")
    lines.forEach((line, i) => this.text(ctx, line, PAD + 32, top + 100 + i * lineHeight, 30, INK, "500"))
  }

  // 日本語は語の切れ目に空白が無いので 1 文字ずつ測り、英数字の語だけはまとめて送る。句読点と閉じ括弧は行頭に送らず、前の行にはみ出させる
  wrap(ctx, body, maxWidth, size, weight) {
    ctx.font = `${weight} ${size}px ${FONT}`
    const lines = []
    let line = ""
    for (const token of body.match(/[A-Za-z0-9_.\-/]+|\n|./gu) || []) {
      if (token === "\n") { lines.push(line); line = ""; continue }
      if (line && !CLOSING.includes(token) && ctx.measureText(line + token).width > maxWidth) {
        lines.push(line)
        line = token.trimStart()
        continue
      }
      line += token
    }
    if (line) lines.push(line)
    return lines
  }

  fit(ctx, string, maxWidth, size, weight) {
    ctx.font = `${weight} ${size}px ${FONT}`
    if (ctx.measureText(string).width <= maxWidth) return string
    // 1 文字ずつ削ると、外から来る長い名前で測る回数が字数に比例し、表示した直後に画面が止まる
    const chars = Array.from(string)
    let low = 0
    let high = chars.length
    while (low < high) {
      const mid = Math.ceil((low + high) / 2)
      if (ctx.measureText(`${chars.slice(0, mid).join("")}…`).width <= maxWidth) low = mid
      else high = mid - 1
    }
    return `${chars.slice(0, low).join("")}…`
  }

  text(ctx, string, x, y, size, color, weight, align = "left") {
    ctx.font = `${weight} ${size}px ${FONT}`
    ctx.fillStyle = color
    ctx.textAlign = align
    ctx.fillText(string, x, y)
  }

  measure(ctx, string, size, weight) {
    ctx.font = `${weight} ${size}px ${FONT}`
    return ctx.measureText(string).width
  }

  roundRect(ctx, x, y, width, height, radius) {
    ctx.beginPath()
    ctx.roundRect(x, y, width, height, radius)
  }
}
