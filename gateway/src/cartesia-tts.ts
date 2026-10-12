// Cartesia WebSocket TTS — the live call's voice for a Cartesia clone
// (2026-10-12; why Cartesia: supabase/functions/_shared/cartesia.ts).
//
// Same shape as ElevenTTS so CallSession drives either without knowing which:
// one socket per call, one CONTEXT per line, sentences streamed into it as
// the model writes them, `flush` when the reply is complete. Measured on a
// warm socket (test/probe-tts-ttfb.mjs): first audio 100 ms median against
// ElevenLabs' 148 ms, word timings on every line.
//
// Each SENTENCE is its own Cartesia request (`continue: false`), played in
// order under the line's context. Streaming them into one context with
// `continue: true` held the first audio back to ~316 ms against ~90 ms
// (measured 2026-10-12) — and a sentence per generation is also what the
// ElevenLabs path does, where the generation boundary is the pause between
// sentences (CallSession.eachSentence). So:
//   sendText  → a new sub-context for that sentence
//   flush     → the line is complete; done once every sentence is
//   close…    → cancel every sentence of the line          (barge-in)
// Audio of a later sentence that arrives early is held until the ones before
// it are done, so the line always plays in order.

import { calmExclamations } from "./calm-exclamations"
import type { ElevenTTSCallbacks } from "./eleven-tts"

const URL_WS = "wss://api.cartesia.ai/tts/websocket"
const VERSION = "2026-08-14"
const MODEL = "sonic-3.6"

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
/** Cartesia clone ids are UUIDs; ElevenLabs ids are 20 alphanumerics. */
export function isCartesiaVoice(voiceId: string | null | undefined): boolean {
  return !!voiceId && UUID.test(voiceId)
}

/** Languages Cartesia is told a line is in — it reads a line in whatever
 *  language it is told, so the call's language is always named. */
const SUPPORTED = new Set(["en", "de", "ja", "ko", "fr", "es", "pt", "it", "nl", "zh", "hi", "pl", "ru", "sv", "tr"])

export interface CartesiaTTSConfig {
  apiKey: string
  voiceId: string
  /** e.g. "pcm_22050" — the same format string the app already plays. */
  outputFormat: string
  /** The call's target language ("en", "de-DE" …). */
  language: string
  /** 0.6–1.5; omitted = normal. */
  speed?: number
}

export class CartesiaTTS {
  private ws: WebSocket | null = null
  private closed = false
  private connecting: Promise<void> | null = null
  /** Lines (the session's contexts) still producing audio. */
  private lines = new Map<string, Line>()
  /** Sentence context id → its line. */
  private sentenceLine = new Map<string, string>()
  private seq = 0
  private queue: Promise<void> = Promise.resolve()

  constructor(private config: CartesiaTTSConfig, private callbacks: ElevenTTSCallbacks) {}

  private enqueue(fn: () => Promise<void> | void): Promise<void> {
    const run = this.queue.then(fn)
    this.queue = run.then(() => {}, () => {})
    return run
  }

  get sampleRate(): number {
    const m = /^pcm_(\d+)$/.exec(this.config.outputFormat)
    return m ? Number(m[1]) : 22050
  }

  private get language(): string {
    const base = this.config.language.toLowerCase().split("-")[0]
    return SUPPORTED.has(base) ? base : "en"
  }

  warm(): void {
    void this.ensureConnected().catch(() => { /* first sendText retries */ })
  }

  private async ensureConnected(): Promise<void> {
    if (this.ws) return
    if (this.connecting) return this.connecting
    this.connecting = this.connect().finally(() => { this.connecting = null })
    return this.connecting
  }

  private async connect(): Promise<void> {
    const resp = await fetch(`${URL_WS.replace("wss://", "https://")}?cartesia_version=${VERSION}`, {
      headers: { Upgrade: "websocket", "X-API-Key": this.config.apiKey, "Cartesia-Version": VERSION },
    })
    const ws = resp.webSocket
    if (!ws) {
      const body = await resp.text().catch(() => "")
      throw new Error(`cartesia upgrade refused: ${resp.status} ${body.slice(0, 200)}`)
    }
    ws.accept()
    this.ws = ws
    ws.addEventListener("message", (ev) => {
      const data = ev.data as unknown
      if (typeof data === "string") return this.handleText(data)
      if (data instanceof ArrayBuffer) return this.handleText(new TextDecoder().decode(data))
      if (typeof (data as Blob)?.text === "function") {
        void (data as Blob).text().then((t) => this.handleText(t)).catch(() => {})
      }
    })
    ws.addEventListener("close", () => {
      this.ws = null
      // Whatever was in flight on this socket will never finish: end those
      // lines rather than leave the call waiting on them.
      for (const id of [...this.lines.keys()]) {
        this.lines.delete(id)
        if (!this.closed) this.callbacks.onContextDone(id)
      }
      this.sentenceLine.clear()
    })
    ws.addEventListener("error", () => {
      this.ws = null
      if (!this.closed) this.callbacks.onError("cartesia socket error")
    })
  }

  private handleText(text: string): void {
    let msg: Record<string, any>
    try { msg = JSON.parse(text) } catch { return }
    const sid: string = msg.context_id ?? ""
    const lineId = this.sentenceLine.get(sid)
    if (lineId === undefined) return
    const line = this.lines.get(lineId)
    if (!line) return
    const sentence = line.sentences.find((x) => x.id === sid)
    if (!sentence) return
    if (msg.type === "chunk" && typeof msg.data === "string" && msg.data.length > 0) {
      sentence.audio.push(base64Decode(msg.data))
    }
    if (msg.type === "error") {
      sentence.done = true
      this.callbacks.onError(String(msg.message ?? msg.title ?? "cartesia error"))
    }
    if (msg.type === "done") sentence.done = true
    this.drain(lineId, line)
  }

  /** Hand the line's audio over in sentence order, and finish the line once
   *  it is flushed and every sentence is done. */
  private drain(lineId: string, line: Line): void {
    while (line.next < line.sentences.length) {
      const s = line.sentences[line.next]
      for (const pcm of s.audio.splice(0)) this.callbacks.onAudio(lineId, pcm)
      if (!s.done) return
      this.sentenceLine.delete(s.id)
      line.next++
    }
    if (line.flushed) {
      this.lines.delete(lineId)
      this.callbacks.onContextDone(lineId)
    }
  }

  private request(sentenceId: string, transcript: string): Record<string, unknown> {
    return {
      model_id: MODEL,
      transcript,
      voice: { mode: "id", id: this.config.voiceId },
      language: this.language,
      context_id: sentenceId,
      continue: false,
      output_format: { container: "raw", encoding: "pcm_s16le", sample_rate: this.sampleRate },
      ...(this.config.speed !== undefined ? { generation_config: { speed: this.config.speed } } : {}),
    }
  }

  /** One sentence of the line, generated on its own. */
  sendText(contextId: string, text: string): Promise<void> {
    return this.enqueue(async () => {
      await this.ensureConnected()
      let line = this.lines.get(contextId)
      if (!line) { line = { sentences: [], next: 0, flushed: false }; this.lines.set(contextId, line) }
      const id = `${contextId}:${++this.seq}`
      line.sentences.push({ id, audio: [], done: false })
      this.sentenceLine.set(id, contextId)
      this.ws?.send(JSON.stringify(this.request(id, calmExclamations(text).trim())))
    })
  }

  setSpeed(speed: number | undefined): void {
    this.config.speed = speed
  }

  /** The line is complete: it ends once its last sentence is spoken. */
  flush(contextId: string): void {
    void this.enqueue(() => {
      const line = this.lines.get(contextId)
      if (!line) return
      line.flushed = true
      this.drain(contextId, line)
    })
  }

  /** Barge-in, or a finished line letting go. Idempotent. */
  closeContext(contextId: string): void {
    const line = this.lines.get(contextId)
    if (!line) return
    this.lines.delete(contextId)
    void this.enqueue(() => {
      for (const s of line.sentences) {
        this.sentenceLine.delete(s.id)
        if (!s.done) this.ws?.send(JSON.stringify({ context_id: s.id, cancel: true }))
      }
    })
  }

  close(): void {
    this.closed = true
    try { this.ws?.close() } catch { /* gone */ }
    this.ws = null
  }
}

function base64Decode(b64: string): Uint8Array {
  const binary = atob(b64)
  const bytes = new Uint8Array(binary.length)
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i)
  return bytes
}

interface Line {
  sentences: { id: string; audio: Uint8Array[]; done: boolean }[]
  /** First sentence not yet fully handed over. */
  next: number
  /** The reply is complete — no more sentences will be added. */
  flushed: boolean
}
