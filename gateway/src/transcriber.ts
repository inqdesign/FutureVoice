// gemini-3.5-transcribe-live client — streaming ASR + utterance endpointing.
//
// Why this model and not a conversational Live session: as of 2026-08-31 the
// Gemini API's Live models are audio-output only (probed — TEXT modality is
// rejected by every conversational live model; see test/probe-live-setup.mjs),
// and the voice here must be the learner's ElevenLabs clone. So the gateway
// runs its own cascade: this transcriber decides WHEN a turn ends and WHAT
// was said; reply.ts writes the answer; eleven-tts.ts speaks it.
//
// Observed message shapes (test/probe-transcribe.mjs, 2026-08-31):
//   serverContent.interimInputTranscription.text — cumulative interim for the
//     utterance in progress (a fresh utterance starts a fresh text).
//   serverContent.inputTranscription.text — the FINAL utterance transcript,
//     arriving ~0.6–1.4 s into the silence after speech. This is the
//     endpoint signal — no client-side VAD exists on this path at all.

const LIVE_HOST = "https://generativelanguage.googleapis.com"
const LIVE_PATH = "/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent"

export interface TranscriberCallbacks {
  /** Cumulative interim text of the utterance in progress. Doubles as the
   *  "the learner is speaking" witness for barge-in. */
  onInterim(text: string): void
  /** The utterance is over and this is its transcript — the turn signal. */
  onUtterance(text: string): void
  onRotating(): void
  onError(message: string): void
}

export class GeminiTranscriber {
  private ws: WebSocket | null = null
  private resumptionHandle: string | null = null
  private closed = false
  private setupDone = false
  private pendingAudio: string[] = []

  constructor(private apiKey: string,
              private model: string,
              private callbacks: TranscriberCallbacks) {}

  async connect(): Promise<void> {
    const resp = await fetch(`${LIVE_HOST}${LIVE_PATH}?key=${this.apiKey}`, {
      headers: { Upgrade: "websocket" },
    })
    const ws = resp.webSocket
    if (!ws) throw new Error(`transcribe-live upgrade refused: ${resp.status}`)
    ws.accept()
    console.log("transcriber: upgraded, sending setup")
    this.ws = ws
    this.setupDone = false

    ws.addEventListener("message", (ev) => this.handleMessage(ev))
    ws.addEventListener("close", (ev) => {
      console.log(`transcriber: closed code=${ev.code} reason=${ev.reason ?? ""} wasClean=${(ev as any).wasClean}`)
      if (this.closed) return
      // Transcription sessions cap at ~10 min — rotate on any unasked close;
      // with a resumption handle the context survives, without one we simply
      // start fresh (the transcript state lives in the session, not here).
      this.callbacks.onRotating()
      this.rotate().catch(() =>
        this.callbacks.onError(`transcribe-live closed: ${ev.code} ${ev.reason ?? ""}`))
    })
    ws.addEventListener("error", () => {
      if (!this.closed) this.callbacks.onError("transcribe-live socket error")
    })

    ws.send(JSON.stringify({
      setup: {
        model: this.model,
        generationConfig: { responseModalities: ["TEXT"] },
        // The utterance finalization IS the turn endpoint, so its silence
        // window is the first slice of every reply's latency. HIGH trades a
        // little cut-off risk for a faster commit; revisit against real
        // learners (the app's old VAD held 0.8–5 s adaptive tiers).
        realtimeInputConfig: {
          automaticActivityDetection: {
            endOfSpeechSensitivity: "END_SENSITIVITY_HIGH",
          },
        },
        sessionResumption: this.resumptionHandle ? { handle: this.resumptionHandle } : {},
      },
    }))
  }

  /** Forward one mic frame (16 kHz mono s16le PCM). */
  sendAudio(pcm: ArrayBuffer): void {
    const data = base64Encode(pcm)
    if (!this.setupDone) {
      if (this.pendingAudio.length < 50) this.pendingAudio.push(data)
      return
    }
    this.sendAudioB64(data)
  }

  private sendAudioB64(data: string): void {
    this.ws?.send(JSON.stringify({
      realtimeInput: { audio: { data, mimeType: "audio/pcm;rate=16000" } },
    }))
  }

  private async rotate(): Promise<void> {
    if (this.closed) return
    try { this.ws?.close() } catch { /* already closing */ }
    await this.connect()
  }

  private handleMessage(ev: MessageEvent): void {
    // Gemini delivers messages as BINARY frames — ArrayBuffer on the edge,
    // Blob under `wrangler dev`. A Blob fed to TextDecoder THROWS inside the
    // listener, which killed the whole socket (found 2026-08-31: every local
    // session died right after setup with an uncaught error).
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
  }

  private handleText(text: string): void {
    let msg: Record<string, any>
    try {
      msg = JSON.parse(text)
    } catch { return }

    if (msg.setupComplete !== undefined) {
      console.log("transcriber: setupComplete")
      this.setupDone = true
      for (const data of this.pendingAudio.splice(0)) this.sendAudioB64(data)
      return
    }
    if (msg.sessionResumptionUpdate?.resumable && msg.sessionResumptionUpdate.newHandle) {
      this.resumptionHandle = msg.sessionResumptionUpdate.newHandle
      return
    }
    if (msg.goAway !== undefined) {
      this.callbacks.onRotating()
      this.rotate().catch((e) => this.callbacks.onError(String(e)))
      return
    }
    const content = msg.serverContent
    if (!content) return
    const interim = content.interimInputTranscription?.text
    if (typeof interim === "string" && interim.length > 0) {
      this.callbacks.onInterim(interim)
    }
    const final = content.inputTranscription?.text
    if (typeof final === "string" && final.trim().length > 0) {
      this.callbacks.onUtterance(final.trim())
    }
  }

  close(): void {
    this.closed = true
    try { this.ws?.close() } catch { /* already closed */ }
    this.ws = null
  }
}

function base64Encode(buf: ArrayBuffer): string {
  const bytes = new Uint8Array(buf)
  let binary = ""
  const chunk = 0x8000
  for (let i = 0; i < bytes.length; i += chunk) {
    binary += String.fromCharCode(...bytes.subarray(i, i + chunk))
  }
  return btoa(binary)
}
