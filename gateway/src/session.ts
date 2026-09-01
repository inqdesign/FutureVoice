// CallSession — one Durable Object per live call.
//
// The gateway's own cascade (as of 2026-08-31 the Gemini API has no
// text-output conversational Live model — probed, see README):
//
//   mic PCM ──> gemini-3.5-transcribe-live ──utterance──> flash reply (SSE)
//                     │                                        │ deltas
//                     │ interim text                           ▼
//                     ├──> client (bubble)              ElevenLabs multi-ctx WS
//                     └──> barge-in witness                    │ PCM
//                                                              ▼
//                                                           client
//
// Auth and voice ownership are checked ONCE, at session start. Turn-taking is
// entirely server-side: the transcriber's utterance finalization IS the
// endpoint, and an interim arriving while a reply is playing IS the barge-in.
// Metering is Phase 1: speech seconds are counted and reported in `stats`
// events but not yet charged — billing lands in Phase 3 (see README).

import { GeminiTranscriber } from "./transcriber"
import { ReplyEngine } from "./reply"
import { ElevenTTS } from "./eleven-tts"
import { send, type ClientMessage, type ServerMessage } from "./protocol"
import { verifyUser, ownsVoice, type Env } from "./supabase"

const DEFAULT_TRANSCRIBE_MODEL = "models/gemini-3.5-transcribe-live"
const DEFAULT_REPLY_MODEL = "gemini-3.6-flash"
const DEFAULT_OUTPUT_FORMAT = "pcm_22050"
const CONVERSATION_MODEL = "eleven_turbo_v2_5"

export class CallSession implements DurableObject {
  private client: WebSocket | null = null
  private transcriber: GeminiTranscriber | null = null
  private replyEngine: ReplyEngine | null = null
  private eleven: ElevenTTS | null = null
  private started = false
  private ended = false

  /** The conversation so far, replayed into every reply call. */
  private history: { role: "user" | "model"; text: string }[] = []
  /** Monotonic reply-turn counter; each reply is one EL context ("t1", ...). */
  private turnCount = 0
  private activeContext: string | null = null
  private activeReplyAbort: AbortController | null = null
  /** Rough speech seconds from mic bytes forwarded while the transcriber is
   *  producing interim text. Phase-1 metric, not a bill. */
  private speechSeconds = 0
  private lastInterimAt = 0
  private statsTimer: number | null = null

  /** A reply generation fired BEFORE the transcriber committed the turn —
   *  the same trick the app's SpeculativeReply plays on its VAD, moved
   *  server-side: the utterance finalization lands ~0.7–1.2 s after the
   *  interim already shows the full sentence, and the model can spend that
   *  window thinking. Nothing is EVER voiced from a speculation: deltas
   *  buffer here, and only an utterance whose words match the snapshot
   *  adopts them (else the speculation is aborted and a fresh reply runs). */
  private spec: {
    text: string
    buffered: string
    abort: AbortController
    done: boolean
    fullText: string | null
  } | null = null
  private specTimer: number | null = null
  /** Interim must sit unchanged this long before a speculation fires. */
  private static readonly specSettleMs = 350

  /// A call with nobody in it hangs itself up.
  ///
  /// The app's own Talk screen has had this since 2026-08-18 (30 s, then a
  /// pause) for one reason: a call left open keeps the mic hot, and every
  /// second of that streams audio upstream whether anyone is speaking or not.
  /// This path bills nothing today, which makes the open mic MORE dangerous,
  /// not less — a phone in a pocket on this screen would stream until the
  /// battery died. Longer than the app's 30 s because there is no "tap to
  /// resume" here: the session simply ends.
  private static readonly idleHangUpMs = 3 * 60 * 1000
  private idleTimer: number | null = null

  /** When the fluent self last had audio in flight. Belt to the client's
   *  braces: even with the echo gate, a stray word can survive the speaker
   *  bouncing back into the mic, and a one-word "turn" landing right after a
   *  line is far more likely to be the line itself than the learner
   *  ("did you say box?", reported 2026-09-01). */
  private lastSpokeAt = 0
  /** How long after a line an utterance is still suspect. */
  private static readonly echoSuspicionMs = 1200

  /** An utterance that ended on a word nobody ends a thought on — held, not
   *  answered. If the learner continues, the next utterance merges into it;
   *  if this timer fires first, the pause was real and the turn commits as
   *  is. Ported from the app's own VAD, whose lexical tiers held 5 s on a
   *  hanging conjunction for exactly this reason; the transcriber's
   *  endpointing has no such judgement and committed "…yet, but" as a turn
   *  (earphone call, 2026-09-01). */
  private pendingUtterance: string | null = null
  private pendingTimer: number | null = null
  private static readonly pendingHoldMs = 4000

  /** Words a spoken thought does not END on. The app's lists, verbatim
   *  (ConversationView.trailingConjunctions / trailingFunctionWords /
   *  fillerWords). */
  private static readonly hangingWords = new Set([
    "and", "but", "or", "so", "because", "cause",
    "if", "when", "while", "that", "which", "though", "although",
    "the", "a", "an", "to", "in", "on", "at", "of",
    "for", "with", "by", "from", "into", "about",
    "uh", "um", "er", "ah", "hmm", "mm", "well",
  ])

  private static endsHanging(text: string): boolean {
    const words = text.trim().toLowerCase().split(/\s+/).filter(Boolean)
    const last = words.at(-1)?.replace(/[^\p{L}\p{N}']+/gu, "")
    return last !== undefined && CallSession.hangingWords.has(last)
  }

  constructor(private state: DurableObjectState, private env: Env) {}

  async fetch(request: Request): Promise<Response> {
    if (request.headers.get("Upgrade")?.toLowerCase() !== "websocket") {
      return new Response("expected websocket", { status: 426 })
    }
    if (this.client) return new Response("session in use", { status: 409 })

    const pair = new WebSocketPair()
    const [toClient, ours] = [pair[0], pair[1]]
    ours.accept()
    this.client = ours

    ours.addEventListener("message", (ev) => {
      this.handleClientMessage(ev).catch((e) => this.fail("internal", String(e)))
    })
    ours.addEventListener("close", () => this.teardown())
    ours.addEventListener("error", () => this.teardown())

    return new Response(null, { status: 101, webSocket: toClient })
  }

  private async handleClientMessage(ev: MessageEvent): Promise<void> {
    if (this.ended) return
    if (typeof ev.data !== "string") {
      if (this.started && this.transcriber) {
        // Binary frames are ArrayBuffer on the edge but Blob under
        // `wrangler dev` — a Blob fed onward becomes ZERO bytes of audio and
        // the transcriber hears nothing (found 2026-08-31, silent failure).
        const raw = ev.data as unknown
        const pcm = raw instanceof ArrayBuffer
          ? raw
          : typeof (raw as Blob)?.arrayBuffer === "function"
            ? await (raw as Blob).arrayBuffer()
            : null
        if (!pcm) return
        this.transcriber.sendAudio(pcm)
        if (Date.now() - this.lastInterimAt < 2000) {
          this.speechSeconds += pcm.byteLength / 2 / 16000
        }
      }
      return
    }

    let msg: ClientMessage
    try { msg = JSON.parse(ev.data) } catch { return this.fail("bad_json", "unparseable control message") }

    if (msg.type === "end") {
      this.teardown()
      return
    }
    if (msg.type !== "start" || this.started) return

    // --- Session-start gate: the ONE place auth and ownership are paid. ---
    if (this.env.DEV_ALLOW_ANON !== "1") {
      const userId = msg.token ? await verifyUser(this.env, msg.token) : null
      if (!userId) return this.fail("unauthorized", "invalid session token")
      if (!(await ownsVoice(this.env, userId, msg.voiceId))) {
        return this.fail("voice_forbidden", "voice_id not permitted")
      }
    }

    this.history = msg.history ? [...msg.history] : []
    this.replyEngine = new ReplyEngine({
      apiKey: this.env.GEMINI_API_KEY,
      model: DEFAULT_REPLY_MODEL,
      system: msg.system,
    })

    this.eleven = new ElevenTTS(
      {
        apiKey: this.env.ELEVENLABS_API_KEY,
        voiceId: msg.voiceId,
        modelId: CONVERSATION_MODEL,
        outputFormat: this.env.ELEVEN_OUTPUT_FORMAT ?? DEFAULT_OUTPUT_FORMAT,
      },
      {
        onAudio: (contextId, pcm) => {
          this.lastSpokeAt = Date.now()
          // Only the ACTIVE context reaches the speaker — a context closed by
          // barge-in can still have chunks in flight, and playing them would
          // talk over the learner who just interrupted.
          if (contextId !== this.activeContext || !this.client) return
          this.client.send(pcm)
        },
        onContextDone: (contextId) => {
          if (contextId !== this.activeContext) return
          this.emit({ type: "audio_end", context: contextId })
          this.activeContext = null
        },
        onError: (message) => this.emit({ type: "error", code: "tts", message }),
      },
    )

    this.transcriber = new GeminiTranscriber(
      this.env.GEMINI_API_KEY,
      this.env.GEMINI_LIVE_MODEL ?? DEFAULT_TRANSCRIBE_MODEL,
      msg.language || "en",
      {
        onInterim: (text) => {
          this.lastInterimAt = Date.now()
          this.armIdleHangUp()
          this.emit({ type: "user_partial", text })
          // The learner is audibly speaking. If the fluent self is mid-reply,
          // that's a barge-in: cut the voice and the generation NOW — the
          // pending utterance will arrive as its own turn and get a fresh
          // reply grounded in what was actually heard.
          if (this.activeContext) this.interrupt()
          // A changed interim invalidates any speculation answering older
          // words (matching the app's rule: only the TEXT moving on cancels,
          // never audio energy). A settled one re-arms the fire timer.
          if (this.spec && this.spec.text !== text) this.dropSpec()
          if (this.specTimer !== null) clearTimeout(this.specTimer)
          this.specTimer = setTimeout(() => this.fireSpec(text),
                                      CallSession.specSettleMs) as unknown as number
        },
        onUtterance: (text) => this.handleUtterance(text),
        onRotating: () => this.emit({ type: "rotating" }),
        onError: (message) => this.fail("transcriber", message),
      },
    )

    await this.transcriber.connect()
    // The first reply's TTS must not pay the ElevenLabs TLS + WS handshake
    // mid-turn — open the socket now, while the learner is still greeting.
    this.eleven.warm()
    this.started = true
    this.armIdleHangUp()
    this.emit({ type: "ready" })
    // The fluent self speaks first, exactly as a phone call does. Sent
    // through the normal reply path so the client needs no special case,
    // and recorded in history so the model knows what it just said.
    if (msg.opener && msg.opener.trim().length > 0) {
      this.speakOpener(msg.opener.trim())
    }

    this.statsTimer = setInterval(() => {
      this.emit({
        type: "stats",
        speechSeconds: Math.round(this.speechSeconds),
        turns: this.turnCount,
      })
    }, 15000) as unknown as number
  }

  /** Speak a line the app chose, with no model call at all. */
  private speakOpener(text: string): void {
    this.turnCount += 1
    const context = `t${this.turnCount}`
    this.activeContext = context
    this.emit({
      type: "audio_start",
      context,
      sampleRate: this.eleven?.sampleRate ?? 22050,
    })
    this.routeDelta(context, text)
    this.history.push({ role: "model", text })
    this.eleven?.flush(context)
    this.emit({ type: "reply", context, text })
  }

  /** Fire a reply generation against a SETTLED interim, before the turn is
   *  committed. Deltas buffer silently; `handleUtterance` adopts or drops. */
  private fireSpec(text: string): void {
    this.specTimer = null
    if (this.ended || !this.started || !this.replyEngine) return
    if (this.spec || this.activeContext) return
    const trimmed = text.trim()
    if (trimmed.length === 0) return

    const abort = new AbortController()
    const spec: NonNullable<CallSession["spec"]> & { context?: string } = {
      text, buffered: "", abort, done: false, fullText: null,
    }
    this.spec = spec
    this.replyEngine.generate(
      [...this.history, { role: "user", text: trimmed }],
      abort.signal,
      (delta) => {
        if (abort.signal.aborted || this.ended) return
        if (spec.context) this.routeDelta(spec.context, delta)
        else spec.buffered += delta
      },
    ).then((full) => {
      if (abort.signal.aborted || this.ended) return
      spec.done = true
      spec.fullText = full
      if (spec.context) this.finishReply(spec.context, full)
    }).catch((e) => {
      if (abort.signal.aborted || this.ended) return
      if (spec.context) {
        // Already adopted and partially voiced — same surface as a live
        // reply failure.
        this.activeContext = null
        this.emit({ type: "error", code: "reply", message: String(e) })
      } else if (this.spec === spec) {
        // Died while still speculative: forget it, the utterance path will
        // simply run a fresh generation.
        this.spec = null
      }
    })
  }

  private dropSpec(): void {
    if (this.specTimer !== null) { clearTimeout(this.specTimer); this.specTimer = null }
    if (this.spec) {
      this.spec.abort.abort()
      this.spec = null
    }
  }

  /** Case, punctuation and spacing are transcription styling, not speech —
   *  the same words must adopt (mirror of ConversationEngine.saysTheSameThing). */
  private static sameWords(a: string, b: string): boolean {
    const norm = (s: string) =>
      s.toLowerCase().replace(/[^\p{L}\p{N}]+/gu, " ").trim()
    return norm(a) === norm(b)
  }

  /** The transcriber finalized an utterance. It becomes a turn now, or it
   *  waits: a line ending on a hanging word is a breath, not an ending. */
  private handleUtterance(text: string): void {
    console.log(`utterance: "${text.slice(0, 80)}" pending=${this.pendingUtterance !== null}`)
    // Discard what is almost certainly our own voice: a scrap of a word,
    // arriving while (or just after) we were speaking. A real interjection
    // that short — "yeah", "wait" — arrives with the learner's own volume
    // behind it and passes the client's gate, so it never gets this far
    // silently; what lands here is the room.
    const words = text.trim().split(/\s+/).filter(Boolean)
    const sinceSpoke = Date.now() - this.lastSpokeAt
    if (words.length <= 1 && sinceSpoke < CallSession.echoSuspicionMs
        && this.pendingUtterance === null) {
      return
    }

    // A held fragment absorbs whatever follows it — the learner was
    // mid-thought, and this is the rest of the thought.
    const merged = this.pendingUtterance !== null
      ? this.pendingUtterance + " " + text.trim()
      : text.trim()
    this.clearPending()
    if (CallSession.endsHanging(merged)) {
      this.pendingUtterance = merged
      this.emit({ type: "user_partial", text: merged })
      console.log(`holding (ends hanging): "${merged.slice(-30)}"`)
      this.pendingTimer = setTimeout(() => {
        const held = this.pendingUtterance
        this.clearPending()
        // The pause was real — a learner who trails off on "but" still
        // deserves an answer to what they DID say.
        if (held) this.commitTurn(held)
      }, CallSession.pendingHoldMs) as unknown as number
      return
    }
    this.commitTurn(merged)
  }

  private clearPending(): void {
    if (this.pendingTimer !== null) { clearTimeout(this.pendingTimer); this.pendingTimer = null }
    this.pendingUtterance = null
  }

  /** A turn is settled. Commit it and speak the reply. */
  private commitTurn(text: string): void {
    console.log(`commit: "${text.slice(0, 80)}"`)
    this.emit({ type: "user_turn", text })
    this.history.push({ role: "user", text })
    // A stale reply still going (e.g. utterance finalized right behind a
    // barge-in interim) must not race the new one.
    this.activeReplyAbort?.abort()
    if (this.specTimer !== null) { clearTimeout(this.specTimer); this.specTimer = null }

    const spec = this.spec as (NonNullable<CallSession["spec"]> & { context?: string }) | null
    if (spec && CallSession.sameWords(spec.text, text)) {
      // The model has been writing since the interim settled — adopt it.
      // Only NOW does anything reach the voice: a speculation for words the
      // learner didn't finish saying dies unvoiced above.
      this.spec = null
      this.turnCount += 1
      const context = `t${this.turnCount}`
      this.activeContext = context
      this.activeReplyAbort = spec.abort
      this.emit({
        type: "audio_start",
        context,
        sampleRate: this.eleven?.sampleRate ?? 22050,
      })
      spec.context = context
      const buffered = spec.buffered
      spec.buffered = ""
      if (buffered.length > 0) this.routeDelta(context, buffered)
      if (spec.done) this.finishReply(context, spec.fullText ?? buffered)
      return
    }
    if (spec) this.dropSpec()

    this.turnCount += 1
    const context = `t${this.turnCount}`
    const abort = new AbortController()
    this.activeReplyAbort = abort
    this.activeContext = context
    let announced = false

    this.replyEngine!.generate(this.history, abort.signal, (delta) => {
      if (abort.signal.aborted || this.ended) return
      if (!announced) {
        announced = true
        this.emit({
          type: "audio_start",
          context,
          sampleRate: this.eleven?.sampleRate ?? 22050,
        })
      }
      this.routeDelta(context, delta)
    }).then((full) => {
      if (abort.signal.aborted || this.ended) return
      this.finishReply(context, full)
    }).catch((e) => {
      if (abort.signal.aborted || this.ended) return
      this.activeContext = null
      this.emit({ type: "error", code: "reply", message: String(e) })
    })
  }

  private routeDelta(context: string, delta: string): void {
    this.emit({ type: "reply_delta", context, text: delta })
    this.eleven?.sendText(context, delta)
      .catch((e) => this.emit({ type: "error", code: "tts", message: String(e) }))
  }

  private finishReply(context: string, full: string): void {
    if (this.ended) return
    if (full.trim().length === 0) {
      this.activeContext = null
      return
    }
    this.history.push({ role: "model", text: full })
    this.eleven?.flush(context)
    this.emit({ type: "reply", context, text: full })
  }

  /** Barge-in: stop the voice and the generation for the active turn. */
  private interrupt(): void {
    const context = this.activeContext
    if (!context) return
    this.activeContext = null
    this.activeReplyAbort?.abort()
    this.eleven?.closeContext(context)
    this.emit({ type: "interrupted", context })
    // What was already voiced still happened — keep the model's half honest
    // by not pretending the turn never existed. The aborted generate() call
    // resolved with the partial text; simplest correct record: drop it from
    // history (the learner interrupted precisely because it wasn't landing).
  }

  /** Restart the nobody-is-here clock. Speech is the only thing that counts:
   *  mic bytes keep arriving from an empty room forever. */
  private armIdleHangUp(): void {
    if (this.idleTimer !== null) clearTimeout(this.idleTimer)
    this.idleTimer = setTimeout(() => {
      this.emit({ type: "error", code: "idle", message: "Call ended — no one was talking." })
      this.teardown()
    }, CallSession.idleHangUpMs) as unknown as number
  }

  private emit(msg: ServerMessage): void {
    if (this.client) send(this.client, msg)
  }

  private fail(code: string, message: string): void {
    this.emit({ type: "error", code, message })
    this.teardown()
  }

  private teardown(): void {
    if (this.ended) return
    this.ended = true
    if (this.statsTimer !== null) clearInterval(this.statsTimer)
    if (this.idleTimer !== null) clearTimeout(this.idleTimer)
    this.clearPending()
    this.dropSpec()
    this.activeReplyAbort?.abort()
    this.transcriber?.close()
    this.eleven?.close()
    try { this.client?.close(1000, "session ended") } catch { /* gone */ }
    this.client = null
  }
}
