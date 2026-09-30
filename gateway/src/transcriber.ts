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
  /** The upstream socket is being replaced; `why` says what closed it. The
   *  call survives — audio is buffered until the new socket is set up. */
  onRotating(why: string): void
  /** Fatal: the socket could not be replaced. Only here is the call deaf. */
  onError(message: string): void
}

/** More rotations than this inside `rotationWindowMs` means upstream is
 *  refusing us in a loop, not hitting its ~10 min ceiling — give up instead
 *  of reconnecting forever with the learner hearing nothing. */
const maxRotationsPerWindow = 4
const rotationWindowMs = 60_000

export class GeminiTranscriber {
  private ws: WebSocket | null = null
  private resumptionHandle: string | null = null
  private closed = false
  private setupDone = false
  /** Mic frames that arrived while no socket could take them — before the
   *  first setupComplete, and during a rotation. Newest-kept: when it fills,
   *  the OLDEST frame goes, because the speech leading into the next
   *  utterance is worth more than the tail of the last one. Sized for a
   *  rotation (~1–2 s to upgrade + setup) at the 48 kHz tap's ~43 ms
   *  frames; a 16 kHz earphone tap's frames are three times longer. */
  private pendingAudio: string[] = []
  private static readonly maxPendingFrames = 120
  /** Bumped on every connect AND at the start of every rotation, so a socket
   *  being replaced can no longer speak for the transcriber: its close/error
   *  events (workerd fires both on an unclean end, and `close` again for the
   *  close() rotate itself issues) would otherwise start a SECOND rotation. */
  private generation = 0
  private rotationsAt: number[] = []

  constructor(private apiKey: string,
              private model: string,
              private language: string,
              private callbacks: TranscriberCallbacks) {}

  async connect(): Promise<void> {
    const resp = await fetch(`${LIVE_HOST}${LIVE_PATH}?key=${this.apiKey}`, {
      headers: { Upgrade: "websocket" },
    })
    const ws = resp.webSocket
    if (!ws) throw new Error(`transcribe-live upgrade refused: ${resp.status}`)
    ws.accept()
    const gen = ++this.generation
    console.log(`transcriber: upgraded (gen ${gen}), sending setup`)
    this.ws = ws
    this.setupDone = false

    ws.addEventListener("message", (ev) => {
      if (gen === this.generation) this.handleMessage(ev)
    })
    // Transcription sessions cap at ~10 min — rotate on any unasked end;
    // with a resumption handle the context survives, without one we simply
    // start fresh (the transcript state lives in the session, not here).
    //
    // `error` rotates too. Until 2026-09-16 it was FATAL — the call ended
    // with "transcribe-live socket error" while `close`, which always follows
    // it, had a perfectly good reconnect path it never got to run. Three of
    // that day's six dropped calls were this, one of them exactly 10 min 4 s
    // after the previous connect: the ceiling itself, arriving as an error.
    ws.addEventListener("close", (ev) => {
      console.log(`transcriber: closed gen=${gen} code=${ev.code} reason=${ev.reason ?? ""} wasClean=${(ev as any).wasClean}`)
      this.rotateFrom(gen, `closed ${ev.code} ${ev.reason ?? ""}`.trim())
    })
    ws.addEventListener("error", () => {
      console.log(`transcriber: socket error gen=${gen}`)
      this.rotateFrom(gen, "socket error")
    })

    ws.send(JSON.stringify({
      setup: {
        model: this.model,
        generationConfig: { responseModalities: ["TEXT"] },
        // The ONLY language hint this model accepts (probed 2026-09-01:
        // `speechConfig.languageCode` is rejected at setup, systemInstruction
        // is not). Without it the first phonemes of an utterance get
        // language-guessed from nothing, and the learner watched their
        // English open in Thai script.
        systemInstruction: { parts: [{ text: languagePin(this.language) }] },
        // Default end-of-speech sensitivity. HIGH was tried for the ~0.3 s
        // it shaves and withdrawn the same day: on a real earphone call it
        // committed turns on "…yet, but" and "…setting up my own" — cutting a
        // learner off mid-thought, the one failure the whole app is built to
        // avoid (its old VAD held 0.8–5 s adaptive tiers for exactly this).
        realtimeInputConfig: { automaticActivityDetection: {} },
        sessionResumption: this.resumptionHandle ? { handle: this.resumptionHandle } : {},
      },
    }))
  }

  /** Forward one mic frame (16 kHz mono s16le PCM). */
  sendAudio(pcm: ArrayBuffer): void {
    const data = base64Encode(pcm)
    if (!this.setupDone || !this.ws) {
      this.buffer(data)
      return
    }
    this.sendAudioB64(data)
  }

  private buffer(data: string): void {
    if (this.pendingAudio.length >= GeminiTranscriber.maxPendingFrames) this.pendingAudio.shift()
    this.pendingAudio.push(data)
  }

  /** Never throws. A socket that has closed under us — its close event not
   *  yet delivered, or delivered and a rotation already under way — refuses
   *  `send()` with a TypeError, and until 2026-09-17 that TypeError escaped
   *  through the session's message handler and ended the CALL as
   *  `internal` ("Can't call WebSocket send() after close()"), one second
   *  after a `goAway` rotation had been announced as survivable. The frame
   *  is kept for the replacement socket instead. */
  private sendAudioB64(data: string): void {
    const ws = this.ws
    if (!ws) return this.buffer(data)
    try {
      ws.send(JSON.stringify({
        realtimeInput: { audio: { data, mimeType: "audio/pcm;rate=16000" } },
      }))
    } catch (e) {
      this.buffer(data)
      // workerd may deliver the dead socket's close/error event late or,
      // for a socket we closed ourselves, only after the next macrotask;
      // rotate now rather than wait, idempotent per generation either way.
      if (ws === this.ws) this.rotateFrom(this.generation, `send failed: ${String(e).slice(0, 80)}`)
    }
  }

  /** Replace the socket of generation `gen`, unless it is already stale
   *  (a rotation is under way, or a newer socket is live) or the transcriber
   *  was closed on purpose. Idempotent per generation — the same socket's
   *  `error` and `close` both land here and only the first one acts. */
  private rotateFrom(gen: number, why: string): void {
    if (this.closed || gen !== this.generation) return
    this.generation += 1
    // A socket that never reached setupComplete died on the handshake — most
    // likely a resumption handle the service no longer honours. Retrying with
    // the same handle would fail the same way; start fresh instead.
    if (!this.setupDone) this.resumptionHandle = null
    const now = Date.now()
    this.rotationsAt = this.rotationsAt.filter((t) => now - t < rotationWindowMs)
    this.rotationsAt.push(now)
    if (this.rotationsAt.length > maxRotationsPerWindow) {
      this.callbacks.onError(`transcribe-live ${why} (${this.rotationsAt.length} rotations in ${rotationWindowMs / 1000}s)`)
      return
    }
    this.callbacks.onRotating(why)
    this.rotate().catch((e) =>
      this.callbacks.onError(`transcribe-live reconnect failed after ${why}: ${String(e)}`))
  }

  private async rotate(): Promise<void> {
    if (this.closed) return
    // Take the old socket OUT of the way before the (awaited) upgrade of the
    // new one: `setupDone` stays true and `ws` keeps pointing at the closed
    // socket for the whole round trip otherwise, so every mic frame in that
    // window is a `send()` on a closed socket. Frames buffer instead and
    // are flushed on the new socket's setupComplete.
    const old = this.ws
    this.ws = null
    this.setupDone = false
    try { old?.close() } catch { /* already closing */ }
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
      this.rotateFrom(this.generation, "goAway")
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

/** The language pin — the whole of it, since this model takes no config-level
 *  language setting (see `connect`). Every sentence here is load-bearing.
 *
 *  The first version of it was written in terms of SCRIPT, because that is the
 *  bug it was born from: English opening in Thai letters. A script rule is a
 *  no-op for the learner who reported the next one (2026-09-15, German —
 *  "내가 하는 말은 당연히 독일어일텐데 자꾸 다른 나라 언어로 인식하는게
 *  아쉬웠어요"): German and English share the Latin alphabet, so accented
 *  German written down as English breaks nothing the old sentence asked for.
 *
 *  So the rule is about the LANGUAGE now, and it says out loud the thing the
 *  model keeps getting wrong — a foreign accent and broken grammar are what a
 *  LEARNER sounds like, never evidence that they switched languages. The
 *  ambiguous cases are named too (the first phonemes of an utterance, and
 *  one-word replies that sound identical across languages), because those are
 *  where a per-utterance guess has the least to go on. */
export function languagePin(code: string): string {
  const name = languageName(code)
  return [
    `You transcribe a language LEARNER speaking ${name}. Write down exactly what you hear, word for word.`,
    `The language is settled before you hear anything: the speaker is speaking ${name}, and every line you write is ${name}. That holds for the first words of an utterance, when you have heard almost nothing yet, and for short replies that sound the same in several languages — write those in ${name} too.`,
    `The speaker has a foreign accent, hesitates, and makes grammar mistakes. That is what a learner sounds like. It is never evidence that they switched to another language, and never a reason to write their words in another language, another spelling or another script.`,
    `Hesitation sounds — uh, um, a drawn-out vowel before the first word — belong to the ${name} utterance too. Write them the way ${name} writes a filler, or leave them out; they are never a word of another language and never another script.`,
    `Never translate and never correct — their mistakes are the material. If part of an utterance is unintelligible, write the ${name} words you are sure of and leave the rest out; do not fill the gap with another language.`,
  ].join("\n")
}

/** English name for the few languages the app teaches; the code itself for
 *  anything else — still a better hint than nothing. */
export function languageName(code: string): string {
  const names: Record<string, string> = {
    en: "English", de: "German", ko: "Korean", ja: "Japanese",
    es: "Spanish", fr: "French", zh: "Chinese",
  }
  return names[code.toLowerCase().split("-")[0]] ?? code
}

export function base64Encode(buf: ArrayBuffer): string {
  const bytes = new Uint8Array(buf)
  let binary = ""
  const chunk = 0x8000
  for (let i = 0; i < bytes.length; i += chunk) {
    binary += String.fromCharCode(...bytes.subarray(i, i + chunk))
  }
  return btoa(binary)
}
