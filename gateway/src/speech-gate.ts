// Which mic frames are worth sending to the live transcriber.
//
// Google bills gemini-3.5-transcribe-live by audio streamed in. The phone
// sends exact zeros while the fluent self is audible (dropped since
// 2026-10-09), but a quiet room is never digital zero, so a learner's
// thinking pause went upstream in full: 146.7 audio minutes against 85.0
// minutes of learner speech, Oct 9–11 2026 — 42% of the bill was silence.
//
// The gate is built to fail OPEN. It only closes on a frame that is clearly
// quieter than the speech heard around it, so a café's babble (loud, steady)
// keeps it open exactly as before, and the money saved comes from quiet rooms.
//
//   * Noise floor: tracks the quiet frames — drops at once to a quieter frame,
//     rises slowly (`floorRiseDbPerSec`) so a talker can't drag it up.
//   * Speech: a frame `speechOverFloorDb` above the floor and above
//     `absoluteMinDb`. Zeros are never speech.
//   * Hangover: after the last speech frame the gate stays open
//     `hangoverMs` — the same 2 s the zero tail always forwarded, so Gemini's
//     own end-of-speech detection sees the silence it always saw.
//   * Pre-roll: while closed, the last `preRollMs` are held and sent the
//     moment speech opens the gate, so the first syllable is never clipped.
//   * Noisy room: a floor above `noisyFloorDb` keeps the gate open, full
//     stop. Measured 2026-10-11 (test/probe-speech-gate.mjs): with café-level
//     noise at the speaker's own level the gate read speech as noise and cut
//     sentences off; a quiet-only gate gives that saving up and loses nothing.
//   * Warm-up: open for the first `warmupMs` while the floor settles.
//   * Keep-alive: while closed, one frame every `keepAliveMs` — with nothing
//     at all the live socket is aborted (1008) after 60–90 s.

export interface GateDecision {
  /** Frames to forward now, oldest first (pre-roll + this frame, this frame, or none). */
  send: ArrayBuffer[]
}

export class SpeechGate {
  static readonly hangoverMs = 2000
  static readonly preRollMs = 500
  static readonly warmupMs = 1500
  static readonly keepAliveMs = 5000
  static readonly speechOverFloorDb = 9
  static readonly absoluteMinDb = -62
  static readonly floorRiseDbPerSec = 1.5
  static readonly noisyFloorDb = -48

  private floorDb = Number.NaN
  private elapsedMs = 0
  private sinceSpeechMs = Number.POSITIVE_INFINITY
  private closedForMs = 0
  private keptAliveAtMs = 0
  private preRoll: { frame: ArrayBuffer; ms: number }[] = []
  private preRollMs = 0
  /** Audio seen and audio forwarded, in ms — their difference is the saving. */
  seenMs = 0
  sentMs = 0

  push(frame: ArrayBuffer): GateDecision {
    const d = this.decide(frame)
    this.seenMs += frame.byteLength / 32
    for (const f of d.send) this.sentMs += f.byteLength / 32
    return d
  }

  private decide(frame: ArrayBuffer): GateDecision {
    const ms = frame.byteLength / 32 // 16 kHz s16le mono
    this.elapsedMs += ms
    const db = levelDb(frame)
    const zero = db === Number.NEGATIVE_INFINITY

    if (!zero) {
      if (Number.isNaN(this.floorDb) || db < this.floorDb) this.floorDb = db
      else this.floorDb = Math.min(db, this.floorDb + SpeechGate.floorRiseDbPerSec * ms / 1000)
    }
    const speech = !zero && db > SpeechGate.absoluteMinDb
      && db > this.floorDb + SpeechGate.speechOverFloorDb
    if (speech) this.sinceSpeechMs = 0
    else this.sinceSpeechMs += ms

    const noisy = !Number.isNaN(this.floorDb) && this.floorDb > SpeechGate.noisyFloorDb
    const open = noisy || this.elapsedMs <= SpeechGate.warmupMs || this.sinceSpeechMs <= SpeechGate.hangoverMs
    if (open) {
      const send = this.preRoll.map((p) => p.frame)
      send.push(frame)
      this.preRoll = []
      this.preRollMs = 0
      this.closedForMs = 0
      this.keptAliveAtMs = 0
      return { send }
    }

    // Closed: hold the frame as pre-roll; forward one now and then.
    this.closedForMs += ms
    this.preRoll.push({ frame, ms })
    this.preRollMs += ms
    while (this.preRoll.length > 1 && this.preRollMs - this.preRoll[0].ms >= SpeechGate.preRollMs) {
      this.preRollMs -= this.preRoll.shift()!.ms
    }
    if (this.closedForMs - this.keptAliveAtMs >= SpeechGate.keepAliveMs) {
      this.keptAliveAtMs = this.closedForMs
      // The keep-alive frame leaves the pre-roll: it has been sent.
      this.preRoll.pop()
      this.preRollMs -= ms
      return { send: [frame] }
    }
    return { send: [] }
  }
}

/** RMS level of a 16-bit PCM frame in dBFS; -Infinity for exact zeros. */
export function levelDb(frame: ArrayBuffer): number {
  const s = new Int16Array(frame, 0, Math.floor(frame.byteLength / 2))
  if (s.length === 0) return Number.NEGATIVE_INFINITY
  let sum = 0
  for (let i = 0; i < s.length; i++) sum += s[i] * s[i]
  if (sum === 0) return Number.NEGATIVE_INFINITY
  return 10 * Math.log10(sum / s.length / (32768 * 32768))
}
