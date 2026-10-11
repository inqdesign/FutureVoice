// Which mic frames are worth sending to the live transcriber.
//
// Google bills gemini-3.5-transcribe-live by audio streamed in. The phone
// sends exact zeros while the fluent self is audible (dropped since
// 2026-10-09 — see GeminiTranscriber's zero tail), but a quiet room is never
// digital zero, so a learner's thinking pause went upstream in full: 146.7
// audio minutes against 85.0 minutes of learner speech, Oct 9–11 2026.
//
// THE RULE: only Gemini decides that speech is over. The first version of
// this gate (2026-10-11, same evening) judged speech by loudness on its own,
// closed in the middle of a learner's drawn-out "uhhh…" and soft word endings,
// and the next words reached Gemini as a NEW utterance that overwrote the
// sentence on screen — reported from the first real call. So:
//
//   * The gate may close only BETWEEN utterances: after Gemini's final for
//     the last one (`noteFinal`), with no interim since (`noteInterim` opens
//     it for good until the next final), `settleMs` after that final, and
//     after `quietMs` of frames no louder than the room.
//   * It reopens on the first frame `reopenOverFloorDb` above the room — a
//     deliberately low bar — and sends the `preRollMs` it was holding first,
//     so the start of the next utterance arrives whole. Reopening on a door
//     slam costs a few seconds of audio; reopening late would cost words.
//   * A room louder than `noisyFloorDb` (a café) never closes at all: there
//     the difference between a voice and the room is too small to trust.
//   * While closed, one frame every `keepAliveMs` — with nothing at all the
//     live socket is aborted (1008) after 60–90 s.
//
// Exact-zero frames are left to the transcriber's existing zero tail; this
// gate only ever sees the frames that rule would forward.

export class SpeechGate {
  static readonly settleMs = 800
  static readonly quietMs = 800
  static readonly preRollMs = 1000
  static readonly keepAliveMs = 5000
  static readonly reopenOverFloorDb = 4
  static readonly noisyFloorDb = -48
  static readonly floorRiseDbPerSec = 1.0

  /** Gemini has finalized the last utterance and heard nothing new since. */
  private between = false
  private sinceFinalMs = 0
  private quietRunMs = 0
  private floorDb = Number.NaN
  private closed = false
  private closedForMs = 0
  private keptAliveAtMs = 0
  private preRoll: ArrayBuffer[] = []
  private preRollMs = 0
  /** Audio seen and audio forwarded, in ms — their difference is the saving. */
  seenMs = 0
  sentMs = 0

  /** Gemini wrote interim text: an utterance is under way. Never close now. */
  noteInterim(): void {
    this.between = false
    this.open()
  }

  /** Gemini finalized an utterance: from here the gate may close once the
   *  room has been quiet for a moment. */
  noteFinal(): void {
    this.between = true
    this.sinceFinalMs = 0
    this.quietRunMs = 0
  }

  /** The upstream socket was replaced: forget what Gemini said; stay open
   *  until it finalizes something on the new socket. */
  reset(): void {
    this.between = false
    this.open()
  }

  /** Frames to forward now, oldest first. */
  push(frame: ArrayBuffer): ArrayBuffer[] {
    const out = this.decide(frame)
    this.seenMs += frame.byteLength / 32
    for (const f of out) this.sentMs += f.byteLength / 32
    return out
  }

  private decide(frame: ArrayBuffer): ArrayBuffer[] {
    const ms = frame.byteLength / 32 // 16 kHz s16le mono
    const db = levelDb(frame)
    const loud = !Number.isNaN(this.floorDb) && db > this.floorDb + SpeechGate.reopenOverFloorDb

    // The room's level: drops at once to a quieter frame, rises slowly.
    if (db !== Number.NEGATIVE_INFINITY) {
      if (Number.isNaN(this.floorDb) || db < this.floorDb) this.floorDb = db
      else this.floorDb = Math.min(db, this.floorDb + SpeechGate.floorRiseDbPerSec * ms / 1000)
    }
    const noisy = !Number.isNaN(this.floorDb) && this.floorDb > SpeechGate.noisyFloorDb

    if (this.closed) {
      if (loud || noisy || !this.between) {
        const out = this.preRoll.concat([frame])
        this.open()
        return out
      }
      this.closedForMs += ms
      this.preRoll.push(frame)
      this.preRollMs += ms
      while (this.preRoll.length > 1 && this.preRollMs - this.preRoll[0].byteLength / 32 >= SpeechGate.preRollMs) {
        this.preRollMs -= this.preRoll.shift()!.byteLength / 32
      }
      if (this.closedForMs - this.keptAliveAtMs >= SpeechGate.keepAliveMs) {
        this.keptAliveAtMs = this.closedForMs
        this.preRoll.pop()
        this.preRollMs -= ms
        return [frame]
      }
      return []
    }

    // Open: forward, and decide whether this was the last frame for a while.
    if (this.between) {
      this.sinceFinalMs += ms
      this.quietRunMs = loud ? 0 : this.quietRunMs + ms
      if (!noisy && this.sinceFinalMs >= SpeechGate.settleMs && this.quietRunMs >= SpeechGate.quietMs) {
        this.closed = true
        this.closedForMs = 0
        this.keptAliveAtMs = 0
      }
    }
    return [frame]
  }

  private open(): void {
    this.closed = false
    this.preRoll = []
    this.preRollMs = 0
    this.closedForMs = 0
    this.keptAliveAtMs = 0
    this.quietRunMs = 0
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
