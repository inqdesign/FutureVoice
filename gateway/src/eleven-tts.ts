// ElevenLabs multi-context WebSocket TTS client.
//
// One connection per call, reused across reply turns — each turn is a
// CONTEXT on the socket, so a barge-in closes one context while the next
// reply opens a fresh one on the same warm connection. This is where the
// old per-turn tts_first_ms cost (TLS + auth + charge + upstream handshake,
// p50 ~2.3 s) goes away: after the first line the connection already exists.
//
// The socket idles out server-side between long gaps (inactivity_timeout is
// capped at 180 s), so `ensureConnected()` lazily reopens it at the start of
// a reply — worst case a turn pays one reconnect, never a failure.

const ELEVEN_HOST = "https://api.elevenlabs.io"

export interface ElevenTTSCallbacks {
  /** PCM audio for a context (decoded from base64). */
  onAudio(contextId: string, pcm: Uint8Array): void
  /** No more audio will arrive for this context. */
  onContextDone(contextId: string): void
  onError(message: string): void
}

export interface ElevenTTSConfig {
  apiKey: string
  voiceId: string
  modelId: string
  /** e.g. "pcm_22050"; must be allowed on the ElevenLabs plan. */
  outputFormat: string
}

export class ElevenTTS {
  private ws: WebSocket | null = null
  private closed = false
  private connecting: Promise<void> | null = null
  /** Contexts already opened on this socket. ElevenLabs accepts
   *  `voice_settings` only in a context's FIRST message and rejects the
   *  whole turn if a later one repeats it — sending it on every delta
   *  killed replies outright ("voice_settings field must be provided in
   *  the first message and then either be not provided or not change",
   *  device log 2026-09-01). */
  private openContexts = new Set<string>()
  /** All outgoing messages ride ONE promise chain. `sendText` is async
   *  (it awaits the connection) while `flush`/`closeContext` used to send
   *  synchronously — so a flush issued right after a sendText could reach
   *  ElevenLabs FIRST, creating the context settings-less; the text that
   *  followed then carried voice_settings into a context that already
   *  existed and the whole reply died ("voice_settings field must be
   *  provided in the first message…", device log 2026-09-01). */
  private queue: Promise<void> = Promise.resolve()

  private enqueue(fn: () => Promise<void> | void): Promise<void> {
    const run = this.queue.then(fn)
    this.queue = run.then(() => {}, () => {})
    return run
  }

  constructor(private config: ElevenTTSConfig,
              private callbacks: ElevenTTSCallbacks) {}

  get sampleRate(): number {
    const m = /^pcm_(\d+)$/.exec(this.config.outputFormat)
    return m ? Number(m[1]) : 22050
  }

  /** Open the socket ahead of need — called at session start so the FIRST
   *  reply doesn't pay the TLS + WS handshake on its critical path. */
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
    const url = `${ELEVEN_HOST}/v1/text-to-speech/${this.config.voiceId}/multi-stream-input` +
      `?model_id=${this.config.modelId}` +
      `&output_format=${this.config.outputFormat}` +
      // auto_mode drops the chunk scheduler — the lowest-latency setting;
      // we flush explicitly at turn end anyway. It voices each text message
      // AS IS, so the caller must send complete sentences, never raw model
      // deltas (see CallSession.voiceBuffer).
      `&auto_mode=true` +
      `&inactivity_timeout=180`
    const resp = await fetch(url, {
      headers: {
        Upgrade: "websocket",
        "xi-api-key": this.config.apiKey,
      },
    })
    const ws = resp.webSocket
    if (!ws) throw new Error(`elevenlabs upgrade refused: ${resp.status}`)
    ws.accept()
    this.ws = ws

    ws.addEventListener("message", (ev) => {
      // Same binary-frame reality as the transcriber: ArrayBuffer on the
      // edge, Blob under `wrangler dev` — a Blob fed to TextDecoder throws
      // inside the listener and takes the socket down with it.
      const data = ev.data as unknown
      if (typeof data === "string") return this.handleText(data)
      if (data instanceof ArrayBuffer) {
        return this.handleText(new TextDecoder().decode(data))
      }
      if (typeof (data as Blob)?.text === "function") {
        void (data as Blob).text()
          .then((text) => this.handleText(text))
          .catch(() => { /* unreadable frame — drop it */ })
      }
    })
    ws.addEventListener("close", () => {
      // Idle timeout between turns is normal — drop the handle and let the
      // next reply reconnect. Only a close mid-close() is final.
      this.ws = null
      this.openContexts.clear()
    })
    ws.addEventListener("error", () => {
      this.ws = null
      if (!this.closed) this.callbacks.onError("elevenlabs socket error")
    })
  }

  private handleText(text: string): void {
    let msg: Record<string, any>
    try {
      msg = JSON.parse(text)
    } catch { return }
    const contextId = msg.contextId ?? msg.context_id ?? ""
    if (typeof msg.audio === "string" && msg.audio.length > 0) {
      this.callbacks.onAudio(contextId, base64Decode(msg.audio))
    }
    if (msg.isFinal === true || msg.is_final === true) {
      this.callbacks.onContextDone(contextId)
    }
    if (msg.error) this.callbacks.onError(String(msg.message ?? msg.error))
  }

  /** Open a context and/or stream reply text into it as the model writes. */
  sendText(contextId: string, text: string): Promise<void> {
    return this.enqueue(async () => {
    await this.ensureConnected()
    // Voice settings mirror the elevenlabs-tts edge function: style MUST
    // stay 0 for cloned voices (see that function's comment — TestFlight
    // users reported the clone drifting at 0.15).
    const first = !this.openContexts.has(contextId)
    if (first) this.openContexts.add(contextId)
    this.ws?.send(JSON.stringify({
      context_id: contextId,
      text,
      ...(first
        ? {
            voice_settings: {
              stability: 0.55,
              similarity_boost: 0.9,
              style: 0,
              use_speaker_boost: true,
            },
          }
        : {}),
    }))
    })
  }

  /** The reply is fully written — synthesize whatever text remains buffered. */
  flush(contextId: string): void {
    void this.enqueue(() => {
      this.ws?.send(JSON.stringify({ context_id: contextId, flush: true }))
    })
  }

  /** Barge-in: kill this context's generation; audio stops arriving. */
  closeContext(contextId: string): void {
    this.openContexts.delete(contextId)
    void this.enqueue(() => {
      this.ws?.send(JSON.stringify({ context_id: contextId, close_context: true }))
    })
  }

  close(): void {
    this.closed = true
    try { this.ws?.send(JSON.stringify({ close_socket: true })) } catch { /* gone */ }
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
