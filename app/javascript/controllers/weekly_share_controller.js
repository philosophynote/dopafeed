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

// 画面の DOM を写さず、サーバーが渡した数字から描く。DOM を画像にするには外部 JS が要り、画面の崩れも写り込む。
export default class extends Controller {
  static values = { card: Object, filename: String }

  async share() {
    this.element.disabled = true
    try {
      const file = new File([await this.render()], this.filenameValue, { type: "image/png" })
      if (navigator.canShare?.({ files: [file] })) {
        await navigator.share({ files: [file], title: this.cardValue.title })
      } else {
        this.download(file)
      }
    } catch (error) {
      // 共有シートを閉じただけなら失敗ではない
      if (error.name !== "AbortError") console.error(error)
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
    setTimeout(() => URL.revokeObjectURL(url), 0)
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
    y += 64
    this.text(ctx, `🔥 ${card.streak}`, PAD, y, 36, MUTED, "700")

    y += 130
    this.text(ctx, String(card.count), PAD, y, 130, ORANGE, "900")
    const countWidth = this.measure(ctx, String(card.count), 130, "900")
    this.text(ctx, "本 読了", PAD + countWidth + 20, y, 48, INK, "700")
    y += 56
    this.text(ctx, card.change, PAD, y, 38, card.up ? "#047857" : MUTED, "700")

    // 一番高い棒の上に本数の字が乗るので、その分を空ける
    y = this.bars(ctx, card, y + 84)
    y = this.stats(ctx, card, y + 30)
    if (card.comment) this.comment(ctx, card.comment, y + 24)

    this.text(ctx, card.footer, WIDTH / 2, HEIGHT - PAD + 4, 28, MUTED, "500", "center")
    return new Promise((resolve, reject) => canvas.toBlob((blob) => (blob ? resolve(blob) : reject(new Error("toBlob failed"))), "image/png"))
  }

  bars(ctx, card, top) {
    const height = 180
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
        this.text(ctx, String(day.count), x + width / 2, top + height - barHeight - 14, 30, MUTED, "700", "center")
      }
      const color = day.state === "today" ? ORANGE : day.state === "future" ? FAINT : MUTED
      this.text(ctx, day.label, x + width / 2, top + height + 44, 32, color, "700", "center")
    })
    return top + height + 44
  }

  stats(ctx, card, top) {
    let y = top
    ctx.fillStyle = "#f3f4f6"
    ctx.fillRect(PAD, y, WIDTH - PAD * 2, 2)
    card.stats.forEach(([label, value]) => {
      y += 56
      this.text(ctx, label, PAD, y, 34, MUTED, "600")
      const labelWidth = this.measure(ctx, label, 34, "600")
      this.text(ctx, this.fit(ctx, value, WIDTH - PAD * 2 - labelWidth - 32, 34, "800"), WIDTH - PAD, y, 34, INK, "800", "right")
    })
    return y
  }

  comment(ctx, comment, top) {
    const lineHeight = 48
    const room = Math.floor((HEIGHT - PAD * 2 - top - 84) / lineHeight)
    let lines = this.wrap(ctx, comment, WIDTH - PAD * 2 - 64, 32, "500")
    if (lines.length > room) lines = [...lines.slice(0, room - 1), this.fit(ctx, `${lines[room - 1]}${lines[room]}`, WIDTH - PAD * 2 - 64, 32, "500")]
    ctx.fillStyle = "#fff7ed"
    this.roundRect(ctx, PAD, top, WIDTH - PAD * 2, 84 + lines.length * lineHeight, 28)
    ctx.fill()
    this.text(ctx, comment.label, PAD + 32, top + 56, 30, "#c2410c", "800")
    lines.forEach((line, i) => this.text(ctx, line, PAD + 32, top + 108 + i * lineHeight, 32, INK, "500"))
  }

  // 日本語は語の切れ目に空白が無いので、1 文字ずつ測って折り返す。句読点と閉じ括弧は行頭に送らず、前の行にはみ出させる
  wrap(ctx, comment, maxWidth, size, weight) {
    ctx.font = `${weight} ${size}px ${FONT}`
    const lines = []
    let line = ""
    for (const char of comment.body) {
      if (char === "\n") { lines.push(line); line = ""; continue }
      if (ctx.measureText(line + char).width > maxWidth && line && !CLOSING.includes(char)) { lines.push(line); line = "" }
      line += char
    }
    if (line) lines.push(line)
    return lines
  }

  // 収まらない分は末尾を「…」にする
  fit(ctx, string, maxWidth, size, weight) {
    ctx.font = `${weight} ${size}px ${FONT}`
    if (ctx.measureText(string).width <= maxWidth) return string
    let fitted = string
    while (fitted && ctx.measureText(`${fitted}…`).width > maxWidth) fitted = fitted.slice(0, -1)
    return `${fitted}…`
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
