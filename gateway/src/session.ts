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
import { TalkBilling } from "./billing"

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
  /** Server-side meter — the gateway charges the call itself (see billing.ts);
   *  the app's TalkMeter stays local-only on this path. */
  private billing: TalkBilling | null = null

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

  /// A call whose PHONE is gone hangs itself up — and pays for nothing while
  /// it works that out.
  ///
  /// The idle clock above is armed by transcriber interims, which is a
  /// judgement about the ROOM. It says nothing about whether anyone is still
  /// on the other end: a killed app on a mobile network leaves a half-open
  /// socket that never delivers a `close` event, so `teardown` is never
  /// reached, and any session state that happens to read as "busy" (an
  /// `activeContext` whose ElevenLabs context never reported done) then bills
  /// every second forever. Two such sessions were found alive 45 minutes
  /// after their call ended, charging 15 s every 15 s (2026-09-05).
  ///
  /// The phone is the witness: the client streams mic PCM continuously —
  /// echo-muted buffers are sent as SILENCE, never as a gap — so frames stop
  /// only when nobody is there. A route rebuild costs a second or two of
  /// them, hence the generous windows.
  /** Has the learner said anything yet in this call? The meter waits for
   *  it — see the billing predicate. */
  private learnerSpoke = false
  private lastClientFrameAt = Date.now()
  /** Nothing from the phone for this long → the socket is dead; hang up. */
  private static readonly clientGoneMs = 45_000
  /** Billing needs the phone present, whatever the session thinks it is
   *  doing. Silence between frames is never this long on a live call. */
  private static readonly billableClientGapMs = 10_000
  /** No conversation runs this long; past it the session is a leak. */
  private static readonly maxSessionMs = 60 * 60 * 1000
  /** An `activeContext` outliving this is a lost ElevenLabs context, not a
   *  reply — clearing it is what stops the meter believing we are speaking. */
  private static readonly maxContextMs = 90_000
  private sessionStartedAt = Date.now()
  private watchTimer: number | null = null
  private watchSeenContext: { context: string; at: number } | null = null

  /** Sliding window of what the fluent self RECENTLY said out loud — the
   *  reference the echo judgement compares against. The server is the one
   *  party that knows the speaker's words verbatim, so "the learner just
   *  said a contiguous fragment of the line we're playing" is the one echo
   *  test that needs no thresholds. Kept short: echo only ever quotes the
   *  last few seconds. */
  private recentReplyText = ""
  /** Reply text written but not yet VOICED, per context. The ElevenLabs
   *  socket runs `auto_mode` (no server-side buffering — lowest latency),
   *  which its docs recommend only for full sentences: "sending partial
   *  phrases will result in highly reduced quality". Gemini's SSE deltas
   *  break wherever the tokenizer happened to ("Take" ‖ " a deep breath",
   *  "for the" ‖ " constant shifts", even "U" ‖ "gh" — probed 2026-09-03),
   *  and each fragment came out as its own generation: a pitch reset and a
   *  stray pause at every seam, which learners heard as odd phrasing. So
   *  the voice gets text one complete SENTENCE at a time; the screen still
   *  gets every delta the instant it lands. The whole reply burst-writes in
   *  ~200 ms, so waiting for the first terminator costs a delta or two. */
  private voiceBuffer = new Map<string, string>()
  /** Projected instant the PHONE finishes playing what we have sent. */
  private playoutEndAt = 0

  /** Dictation EXPANDS contractions ("what's" → "what is"), so the mic's
   *  version of our own line never matched it verbatim and the echo check
   *  below let "What is the best thing that is" through as the learner
   *  (speakerphone, 2026-09-11). Both sides are expanded before comparing;
   *  the table is the app's own `ConversationEngine` list, plus the
   *  negations. Ambiguous forms ('d, 's as "has") are left alone — a miss
   *  there costs one uncaught echo, a wrong expansion costs nothing worse. */
  private static readonly contractions: [RegExp, string][] = [
    [/\b(what|that|it|he|she|there|here|who|where|how)'s\b/g, "$1 is"],
    [/\bi'm\b/g, "i am"], [/\blet's\b/g, "let us"],
    [/\b(you|we|they)'re\b/g, "$1 are"],
    [/\b(i|you|we|they)'ve\b/g, "$1 have"],
    [/\b(i|you|we|they|it|he|she|that|there)'ll\b/g, "$1 will"],
    [/\bcan't\b/g, "cannot"], [/\bwon't\b/g, "will not"],
    [/\b(do|does|did|is|are|was|were|has|have|had|would|could|should|must)n't\b/g, "$1 not"],
  ]

  private static normWords(s: string): string {
    let t = s.toLowerCase().replace(/[’‘]/g, "'")
    for (const [re, to] of CallSession.contractions) t = t.replace(re, to)
    return t.replace(/[^\p{L}\p{N}]+/gu, " ").trim().replace(/\s+/g, " ")
  }

  /** Longest run of consecutive `u` words that appears consecutively in
   *  `reply` (word-level longest common substring). */
  private static longestRun(u: string[], reply: string[]): number {
    let best = 0
    let prev = new Array<number>(reply.length + 1).fill(0)
    for (let i = 1; i <= u.length; i++) {
      const cur = new Array<number>(reply.length + 1).fill(0)
      for (let j = 1; j <= reply.length; j++) {
        if (u[i - 1] === reply[j - 1]) {
          cur[j] = prev[j - 1] + 1
          if (cur[j] > best) best = cur[j]
        }
      }
      prev = cur
    }
    return best
  }

  /** Is this utterance almost certainly our own speaker coming back?
   *  True when it lands while (or just after) the fluent self is audible AND
   *  its words are a contiguous fragment of what was just spoken. The
   *  contiguity requirement is what keeps a real short answer that happens
   *  to reuse the reply's words ("yeah, I agree") alive — shared vocabulary
   *  is conversation, a verbatim run of it during playback is a microphone. */
  private isLikelyEcho(text: string): boolean {
    // Suspicion holds while the reply is still being written, while the
    // PHONE is still projected to be playing it (the play-out clock), and
    // for a beat of room tail after — never keyed to send time alone.
    const withinWindow = this.activeContext !== null
      || Date.now() < this.playoutEndAt + 3000
    if (!withinWindow) return false
    const u = CallSession.normWords(text)
    if (u.length === 0) return false
    const words = u.split(" ")
    // A long verbatim run is MORE certainly the speaker, not less — the
    // old 8-word cap waved through exactly the fragments a loud line
    // produces. Short utterances must match whole; from four words on, a
    // transcriber slip inside an otherwise verbatim run still counts.
    if (words.length > 16) return false
    const reply = CallSession.normWords(this.recentReplyText)
    if (reply.includes(u)) return true
    if (words.length < 4) return false
    const run = CallSession.longestRun(words, reply.split(" "))
    return run >= Math.ceil(words.length * 0.75)
  }

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
  /** EVERY final is held this long before it becomes a turn — not only
   *  the hanging-word ones. The transcriber's final is not "the learner
   *  stopped": it segments a long monologue mid-stream (a 36 s sentence
   *  finalized at "…let's see if this", and "and works" arrived 2 s later
   *  as its own turn, answered on its own), and it finalizes a clause the
   *  learner resumes 0.3–0.6 s later. Measured on device 2026-09-04: every
   *  observed continuation reached its next interim within 0.6 s of the
   *  final. The reply the speculation already wrote waits with it, so the
   *  cost is this window on the VOICE, not on the thinking. */
  private static readonly continuationMs = 800

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
    // Any frame at all — audio or control — is proof the phone is still on
    // the other end. See `lastClientFrameAt`.
    this.lastClientFrameAt = Date.now()
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
      // The gateway meters the call itself — a client that never ticks
      // still pays (the classic path's talk-tick is client-driven, which
      // was the one bypass left on this path). Same billable rule as
      // ConversationView.isBillableMoment, read off session state.
      this.billing = new TalkBilling(
        this.env,
        msg.token,
        crypto.randomUUID(),
        msg.language || null,
        // Nothing is charged until the learner has actually SAID something.
        // The opener speaks whether or not it is answered, so a call opened
        // and abandoned billed its own greeting and the silence after it —
        // and the ring showed that wait back as talk time (2026-09-07). A
        // committed turn is the witness, never an interim: a room's noise
        // makes interims all day.
        () => this.learnerSpoke
          && this.clientPresent(CallSession.billableClientGapMs)
          && (this.activeContext !== null
            || Date.now() - this.lastSpokeAt < 2000
            || Date.now() - this.lastInterimAt < TalkBilling.graceMs),
        (code) => {
          // Out of minutes: say WHICH wall (the client shows the paywall for
          // a spent free pool, "see you tomorrow" for a subscriber's day)
          // and put the call down. Mid-sentence audio is allowed to finish
          // client-side; nothing new is generated.
          this.emit({ type: "error", code, message: "talk allowance spent" })
          this.teardown()
        },
      )
      // Preflight 1 s — an empty allowance must surface BEFORE the greeting
      // speaks, not a free minute later (same rule as the classic path).
      const wall = await this.billing.preflight()
      if (wall) {
        this.emit({ type: "error", code: wall, message: "talk allowance spent" })
        return this.teardown()
      }
      this.billing.start()
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
          // Play-out clock: the DO SENDS a reply's audio in a burst, but the
          // phone plays it for its real duration — the echo of a long line's
          // TAIL lands seconds after `lastSpokeAt`, outside any window
          // anchored to send time (build 31, speakerphone, 2026-09-03: the
          // same "sent is not heard" gap the client's gate had). Model the
          // speaker instead: each chunk extends the projected end of
          // playback by its own duration.
          const ms = pcm.byteLength / 2 / (this.eleven?.sampleRate ?? 22050) * 1000
          this.playoutEndAt = Math.max(this.playoutEndAt, Date.now()) + ms
          this.client.send(pcm)
        },
        onContextDone: (contextId) => {
          console.log(`tts: context ${contextId} final (active=${this.activeContext})`)
          this.endLine(contextId)
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
          if (this.pendingUtterance !== null) {
            // The held line is not over: the next final merges into it, so
            // the hold waits for that final instead of its own clock. The
            // clock is re-armed, not cleared — an interim the transcriber
            // never finalizes must still let the held text go out alone.
            // And the screen keeps the held words in front of the new ones:
            // a fresh interim replacing the whole bubble is what the learner
            // saw as their sentence vanishing mid-thought ("I don't know
            // why it's overwriting what I said", 2026-09-04).
            this.armPending(CallSession.pendingHoldMs)
            this.emit({ type: "user_partial", text: this.pendingUtterance + " " + text })
          } else {
            this.emit({ type: "user_partial", text })
          }
          // The learner is audibly speaking. If the fluent self is mid-reply,
          // that's a barge-in: cut the voice and the generation NOW — the
          // pending utterance will arrive as its own turn and get a fresh
          // reply grounded in what was actually heard. Unless the "speech"
          // is our own line coming back through the speaker: an interim
          // that reads as a fragment of the playing reply must not cut it.
          if (this.activeContext && !this.isLikelyEcho(text)) this.interrupt()
          // A changed interim invalidates any speculation answering older
          // words (matching the app's rule: only the TEXT moving on cancels,
          // never audio energy). A settled one re-arms the fire timer — on
          // the MERGED line while a hold is open, which is the text the
          // commit will compare against.
          const specText = this.pendingUtterance !== null
            ? this.pendingUtterance + " " + text
            : text
          if (this.spec && this.spec.text !== specText) this.dropSpec()
          if (this.specTimer !== null) clearTimeout(this.specTimer)
          this.specTimer = setTimeout(() => this.fireSpec(specText),
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
    this.sessionStartedAt = Date.now()
    this.armIdleHangUp()
    this.startWatchdog()
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
    this.finishVoice(context)
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
    // The speaker heard itself: an utterance that is a verbatim fragment of
    // the line just played is the microphone, not the learner — drop it
    // before it becomes a turn the fluent self answers on its own
    // ("Apple Watch", speakerphone, 2026-09-03). The client's level gate
    // can't catch this case: it learns the echo's own average level, so the
    // loud syllables of the same echo sail over its margin.
    if (this.pendingUtterance === null && this.isLikelyEcho(text)) {
      console.log(`echo-drop: "${text.slice(0, 60)}"`)
      return
    }
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
    // Held, always. A hanging word says "still composing" and earns the
    // long hold; anything else gets the continuation window, because a
    // final alone never proved the learner stopped (see `continuationMs`).
    const hanging = CallSession.endsHanging(merged)
    this.pendingUtterance = merged
    this.emit({ type: "user_partial", text: merged })
    console.log(`holding (${hanging ? "ends hanging" : "continuation"}): "${merged.slice(-30)}"`)
    this.armPending(hanging ? CallSession.pendingHoldMs : CallSession.continuationMs)
  }

  /** (Re)start the clock on the held utterance. When it fires the pause was
   *  real — a learner who trails off on "but" still deserves an answer to
   *  what they DID say. */
  private armPending(ms: number): void {
    if (this.pendingTimer !== null) clearTimeout(this.pendingTimer)
    this.pendingTimer = setTimeout(() => {
      const held = this.pendingUtterance
      this.clearPending()
      if (held) this.commitTurn(held)
    }, ms) as unknown as number
  }

  private clearPending(): void {
    if (this.pendingTimer !== null) { clearTimeout(this.pendingTimer); this.pendingTimer = null }
    this.pendingUtterance = null
  }

  /** A turn is settled. Commit it and speak the reply. */
  private commitTurn(text: string): void {
    console.log(`commit: "${text.slice(0, 80)}"`)
    this.learnerSpoke = true
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
    // Echo reference: everything routed to the voice is what the room can
    // hear. Sliding window — echo only ever quotes the last few seconds.
    this.recentReplyText = (this.recentReplyText + " " + delta).slice(-600)
    this.emit({ type: "reply_delta", context, text: delta })
    const pending = (this.voiceBuffer.get(context) ?? "") + delta
    const [sentences, rest] = CallSession.splitCompleteSentences(pending)
    this.voiceBuffer.set(context, rest)
    if (sentences.length > 0) this.voice(context, sentences)
  }

  /** Send one piece of text to the voice. ElevenLabs asks that every chunk
   *  end in a single space — it is the word boundary the synthesizer keys
   *  on, and the next chunk is glued straight onto it. */
  private voice(context: string, text: string): void {
    const chunk = text.replace(/\s+$/, "") + " "
    if (chunk.trim().length === 0) return
    this.eleven?.sendText(context, chunk)
      .catch((e) => this.emit({ type: "error", code: "tts", message: String(e) }))
  }

  /** The reply is fully written: voice whatever sentence tail is still
   *  buffered (a final line without a terminator, or the terminator with
   *  nothing after it), then flush the context. */
  private finishVoice(context: string): void {
    const rest = this.voiceBuffer.get(context) ?? ""
    this.voiceBuffer.delete(context)
    if (rest.trim().length > 0) this.voice(context, rest)
    this.eleven?.flush(context)
    this.armLineEndFallback(context)
  }

  /** The line is over: tell the client, and free the turn. Idempotent —
   *  the TTS final and the play-out fallback below can both land. */
  private endLine(context: string): void {
    if (context !== this.activeContext) return
    if (this.lineEndTimer !== null) { clearInterval(this.lineEndTimer); this.lineEndTimer = null }
    this.emit({ type: "audio_end", context })
    this.activeContext = null
  }

  /** `audio_end` used to ride on ElevenLabs' `isFinal` alone, and on
   *  2026-09-11 (device, opener line) it never came: the client sat on
   *  "speaking", its echo gate never opened, and — with the first line
   *  half-duplex — the learner talked into a muted mic for the rest of the
   *  call. The play-out clock already knows when the phone will have gone
   *  quiet, so once it has, plus a beat for a straggling chunk, the line is
   *  declared over from here. A `isFinal` that arrives first wins and
   *  clears this. */
  private lineEndTimer: number | null = null
  private static readonly lineEndGraceMs = 1500

  private armLineEndFallback(context: string): void {
    if (this.lineEndTimer !== null) clearInterval(this.lineEndTimer)
    this.lineEndTimer = setInterval(() => {
      if (this.ended || this.activeContext !== context) {
        if (this.lineEndTimer !== null) { clearInterval(this.lineEndTimer); this.lineEndTimer = null }
        return
      }
      if (Date.now() > this.playoutEndAt + CallSession.lineEndGraceMs) {
        console.log(`tts: no final for ${context} — play-out over, ending line`)
        this.endLine(context)
      }
    }, 500) as unknown as number
  }

  /** Split off every complete sentence — a terminator (.!?… and CJK
   *  equivalents, optionally followed by a closing quote/bracket) that is
   *  FOLLOWED by whitespace, which is what tells "Mr." apart from a sentence
   *  end mid-stream as well as a tokenizer can. Returns the complete
   *  sentences joined (they go out as ONE chunk — the more of the reply a
   *  generation sees, the better its prosody) and the unfinished remainder.
   *  A terminator at the very end of the text is NOT taken: the next delta
   *  could start with a closing quote, and the tail is drained at finish
   *  anyway. */
  static splitCompleteSentences(text: string): [string, string] {
    let cut = -1
    const re = /[.!?…。！？][)"'”’」』]*\s+/g
    let m: RegExpExecArray | null
    while ((m = re.exec(text)) !== null) cut = m.index + m[0].length
    if (cut < 0) return ["", text]
    return [text.slice(0, cut), text.slice(cut)]
  }

  private finishReply(context: string, full: string): void {
    if (this.ended) return
    if (full.trim().length === 0) {
      this.voiceBuffer.delete(context)
      this.activeContext = null
      return
    }
    this.history.push({ role: "model", text: full })
    this.finishVoice(context)
    this.emit({ type: "reply", context, text: full })
  }

  /** Barge-in: stop the voice and the generation for the active turn. */
  private interrupt(): void {
    const context = this.activeContext
    if (!context) return
    this.activeContext = null
    // The client stops playback NOW — the projected play-out is void, and
    // leaving it running would hold the echo window open over the learner's
    // own next words.
    this.playoutEndAt = Date.now()
    this.activeReplyAbort?.abort()
    this.voiceBuffer.delete(context)
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

  private clientPresent(withinMs: number): boolean {
    return Date.now() - this.lastClientFrameAt < withinMs
  }

  /** The one clock that does not trust the session's own state: it watches
   *  the PHONE. See `lastClientFrameAt` for why the idle clock is not
   *  enough. */
  private startWatchdog(): void {
    if (this.watchTimer !== null) return
    this.watchTimer = setInterval(() => {
      if (this.ended) return
      if (!this.clientPresent(CallSession.clientGoneMs)) {
        console.log("watchdog: no client frames — hanging up")
        this.teardown()
        return
      }
      if (Date.now() - this.sessionStartedAt > CallSession.maxSessionMs) {
        console.log("watchdog: session ceiling reached — hanging up")
        this.emit({ type: "error", code: "idle", message: "Call ended." })
        this.teardown()
        return
      }
      // A context that never reported done is a lost TTS context. Left set
      // it reads as "the fluent self is speaking" to the meter, forever.
      const context = this.activeContext
      if (context === null) { this.watchSeenContext = null; return }
      if (this.watchSeenContext?.context !== context) {
        this.watchSeenContext = { context, at: Date.now() }
      } else if (Date.now() - this.watchSeenContext.at > CallSession.maxContextMs) {
        console.log(`watchdog: dropping stale context ${context}`)
        this.activeContext = null
        this.watchSeenContext = null
      }
    }, 5000) as unknown as number
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
    this.billing?.stop()   // final flush — the last partial batch still bills
    if (this.statsTimer !== null) clearInterval(this.statsTimer)
    if (this.idleTimer !== null) clearTimeout(this.idleTimer)
    if (this.watchTimer !== null) clearInterval(this.watchTimer)
    this.clearPending()
    this.dropSpec()
    this.activeReplyAbort?.abort()
    this.transcriber?.close()
    this.eleven?.close()
    try { this.client?.close(1000, "session ended") } catch { /* gone */ }
    this.client = null
  }
}
