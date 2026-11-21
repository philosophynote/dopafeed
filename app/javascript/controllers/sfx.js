// 効果音はその場で合成する。音源ファイルを置かないので、ライセンスも読み込み待ちも無い（ADR 0022）。
// iOS は利用者の操作の中でしか音を出させない。指の pointerdown はその操作に数えられない（数えるのは pointerup・touchend・click・keydown）ため、
// それらを capture で聞いて AudioContext を作り、起こす。最初の操作より前の音は捨てる。
// navigator.audioSession の種類は指定しない。既定でも iOS は Web Audio だけのページを消音に従わせ、聴いている音楽も止めない。"playback" は消音を越えて鳴り、音楽も止める（ADR 0025）。
const STORAGE_KEY = "sfx"
const LOG_KEY = "sfx-log"
const LEVEL_LOG_KEY = "sfx-log-levels"

let context = null
// localStorage に書けない端末でも、この画面を開いている間は切り替えを効かせる
let memoryEnabled = null

const recording = () => document.querySelector("meta[name='sfx-record']") !== null

export function enabled() {
  if (memoryEnabled !== null) return memoryEnabled
  try {
    return localStorage.getItem(STORAGE_KEY) !== "off"
  } catch {
    return true
  }
}

export function setEnabled(on) {
  try {
    on ? localStorage.removeItem(STORAGE_KEY) : localStorage.setItem(STORAGE_KEY, "off")
    memoryEnabled = null
  } catch {
    memoryEnabled = on
  }
}

function unlock() {
  if (recording()) return
  if (!context) {
    const AudioContextClass = window.AudioContext || window.webkitAudioContext
    if (!AudioContextClass) return
    try {
      context = new AudioContextClass()
    } catch {
      return
    }
  }
  // "interrupted"（iOS でバックグラウンドへ移った後や着信の後）も起こし直す
  if (context.state === "running") return

  context.resume().catch(() => {})
  // 操作の中で一度音を流しておかないと、後から setTimeout で鳴らす音を通さない WebKit がある
  const silent = context.createBufferSource()
  silent.buffer = context.createBuffer(1, 1, context.sampleRate)
  silent.connect(context.destination)
  silent.start()
}

for (const type of [ "pointerup", "touchend", "click", "keydown" ]) {
  document.addEventListener(type, unlock, { capture: true, passive: true })
}

// 高さ（level）は名前の列と別に残す。名前の列に混ぜると、level を渡すだけの音の検査がみな書き換わる
function record(cue, level) {
  try {
    const log = JSON.parse(sessionStorage.getItem(LOG_KEY) || "[]")
    log.push(cue)
    sessionStorage.setItem(LOG_KEY, JSON.stringify(log))
    const levels = JSON.parse(sessionStorage.getItem(LEVEL_LOG_KEY) || "[]")
    levels.push(level ?? null)
    sessionStorage.setItem(LEVEL_LOG_KEY, JSON.stringify(levels))
  } catch {
    // 記録できなくても画面は動かす
  }
}

function tone(frequency, { at = 0, length = 0.12, type = "sine", volume = 0.2, slideTo = null } = {}) {
  const start = context.currentTime + at
  const oscillator = context.createOscillator()
  const gain = context.createGain()
  oscillator.type = type
  oscillator.frequency.setValueAtTime(frequency, start)
  if (slideTo) oscillator.frequency.exponentialRampToValueAtTime(slideTo, start + length)
  gain.gain.setValueAtTime(0.0001, start)
  gain.gain.exponentialRampToValueAtTime(volume, start + 0.005)
  gain.gain.exponentialRampToValueAtTime(0.0001, start + length)
  oscillator.connect(gain).connect(context.destination)
  oscillator.start(start)
  oscillator.stop(start + length + 0.02)
}

function noise({ at = 0, length = 0.15, volume = 0.15, filter = "bandpass", from = 800, to = null } = {}) {
  const start = context.currentTime + at
  const buffer = context.createBuffer(1, Math.ceil(context.sampleRate * length), context.sampleRate)
  const data = buffer.getChannelData(0)
  for (let i = 0; i < data.length; i++) data[i] = Math.random() * 2 - 1
  const source = context.createBufferSource()
  source.buffer = buffer
  const band = context.createBiquadFilter()
  band.type = filter
  band.frequency.setValueAtTime(from, start)
  if (to) band.frequency.exponentialRampToValueAtTime(to, start + length)
  const gain = context.createGain()
  gain.gain.setValueAtTime(volume, start)
  gain.gain.exponentialRampToValueAtTime(0.0001, start + length)
  source.connect(band).connect(gain).connect(context.destination)
  source.start(start)
}

// 音程は平均律の音名で持つ（C5 = 523.25Hz）。和音が濁らないように同じ調の中で選ぶ
const NOTE = { C5: 523.25, D5: 587.33, E5: 659.25, G5: 783.99, A5: 880, C6: 1046.5, D6: 1174.66, E6: 1318.5, G6: 1568, B6: 1975.5 }

// ペンタトニックだけで組む。間合いが詰まって前の音の余韻と重なっても濁らない
const MELODY = [
  NOTE.C5, NOTE.E5, NOTE.G5, NOTE.E5, NOTE.A5, NOTE.G5, NOTE.E5, NOTE.G5,
  NOTE.A5, NOTE.C6, NOTE.D6, NOTE.C6, NOTE.A5, NOTE.G5, NOTE.D5, NOTE.C5,
]

const CUES = {
  tap: () => tone(1800, { length: 0.03, type: "triangle", volume: 0.08 }),
  swipe: () => noise({ length: 0.08, volume: 0.12, filter: "highpass", from: 2500 }),
  rare: () => {
    tone(NOTE.E6, { length: 0.35, volume: 0.15 })
    tone(NOTE.B6, { at: 0.08, length: 0.45, volume: 0.12 })
  },
  gold: () => [ NOTE.C6, NOTE.E6, NOTE.G6 ].forEach((f, i) => tone(f, { at: i * 0.06, length: 0.6, type: "triangle", volume: 0.12 })),
  card: () => {
    noise({ length: 0.14, volume: 0.1, filter: "bandpass", from: 600, to: 3000 })
    tone(180, { at: 0.12, length: 0.12, slideTo: 70, volume: 0.25 })
  },
  // 連続が伸びるほど半音ずつ上がる。上がり過ぎて耳に痛くならないよう 1 オクターブで止める
  combo: (level = 2) => {
    const step = Math.min(Math.max(level - 2, 0), 12)
    const base = NOTE.E5 * 2 ** (step / 12)
    tone(base, { length: 0.1, type: "square", volume: 0.06 })
    tone(base * 1.5, { at: 0.08, length: 0.2, type: "triangle", volume: 0.1 })
  },
  melody: (note = 1) => {
    const index = (Math.max(note, 1) - 1) % MELODY.length
    const frequency = MELODY[index]
    tone(150, { length: 0.08, slideTo: 60, volume: 0.2 })
    tone(frequency, { length: 0.22, type: "triangle", volume: 0.14 })
    if ((index + 1) % (MELODY.length / 2) === 0) tone(frequency * 1.5, { at: 0.02, length: 0.35, type: "triangle", volume: 0.08 })
  },
  highlight: () => [ NOTE.C6, NOTE.E6, NOTE.G6, NOTE.C6 * 2 ].forEach((f, i) => tone(f, { at: i * 0.07, length: 0.3, type: "triangle", volume: 0.1 })),
  puff: () => noise({ length: 0.3, volume: 0.06, filter: "lowpass", from: 900, to: 200 }),
  fanfare: () => {
    [ NOTE.C5, NOTE.E5, NOTE.G5 ].forEach((f, i) => tone(f, { at: i * 0.09, length: 0.16, type: "square", volume: 0.06 }))
    ;[ NOTE.C6, NOTE.E6, NOTE.G6 ].forEach((f) => tone(f, { at: 0.3, length: 0.9, type: "triangle", volume: 0.1 }))
  },
  chest: () => {
    noise({ length: 0.2, volume: 0.08, filter: "lowpass", from: 400 })
    ;[ NOTE.G5, NOTE.C6, NOTE.E6, NOTE.G6 ].forEach((f, i) => tone(f, { at: 0.2 + i * 0.08, length: 0.5, type: "triangle", volume: 0.1 }))
  }
}

export function play(cue, level) {
  if (!CUES[cue] || !enabled()) return
  if (recording()) return record(cue, level)
  if (!context) return
  if (context.state === "running") return CUES[cue](level)

  // 起こした直後のタップでは、resume がまだ済んでいないことがある
  context.resume().then(() => CUES[cue](level)).catch(() => {})
}
