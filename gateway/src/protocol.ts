// Client <-> gateway wire protocol, v1.
//
// One WebSocket per call. TEXT frames carry JSON control messages (below);
// BINARY frames carry raw audio, one direction each:
//   client -> gateway : 16 kHz mono s16le PCM mic audio, continuous, paced
//                       roughly realtime (the gateway forwards to Gemini Live,
//                       which runs its own VAD — there is no client-side turn
//                       logic in this protocol at all).
//   gateway -> client : mono s16le PCM reply audio at the sample rate the
//                       preceding `audio_start` announced. Exactly one reply
//                       stream is live at a time; `audio_start`/`audio_end`
//                       bracket it, `interrupted` cuts it short.

/** First message the client must send after the socket opens. */
export interface StartMessage {
  type: "start"
  /** Supabase access token (the same JWT the edge functions take). */
  token: string
  /** ElevenLabs voice id the reply audio speaks in — the learner's clone or
   *  a counterpart preset. Ownership is enforced server-side, same rule as
   *  the elevenlabs-tts edge function. */
  voiceId: string
  /** BCP-47-ish target language code ("en", "de", ...) — currently only
   *  recorded; Gemini Live infers the language from the audio itself. */
  language: string
  /** Full system prompt for the conversation. The client already builds this
   *  (ConversationEngine.conversationSystemPrompt); the gateway passes it to
   *  Gemini Live verbatim as the session's system instruction. */
  system: string
  /** Optional prior turns to resume a conversation ("user"/"model" + text). */
  history?: { role: "user" | "model"; text: string }[]
  /** The first line, spoken by the fluent self before the learner says
   *  anything. A call starts with the other side talking, and the app has
   *  its own rules for what that line is (canned pools, scenario openers,
   *  the daily call's voicemail). It is spoken HERE rather than by the
   *  app because the app would need a second audio engine to do it, and
   *  two engines fighting over one session is how the call goes silent. */
  opener?: string
}

/** Speak a line the app chose, after the call is already up.
 *
 *  `start.opener` covers the line the app HAS when it dials. A scenario or a
 *  Find-people call doesn't have one: its greeting is written by Gemini, and
 *  waiting for that before dialling put the model's 2–4 s in front of the
 *  gateway's own start-up instead of alongside it (measured 2026-09-13 —
 *  6–8 s of silence after the tap). So the call opens with no opener and the
 *  line arrives here when it is written.
 *
 *  `alreadySpoken` means the app played the line itself from its phrase
 *  cache: record it in history, say nothing. */
export interface SayMessage {
  type: "say"
  text: string
  alreadySpoken?: boolean
}

/** Polite hang-up; the gateway closes upstream sessions and then the socket. */
export interface EndMessage {
  type: "end"
}

export type ClientMessage = StartMessage | SayMessage | EndMessage

// ---------------------------------------------------------------------------
// Gateway -> client events.

export type ServerMessage =
  /** Auth + upstream sessions are up; start streaming mic audio. */
  | { type: "ready" }
  /** Live transcription of what the learner is saying, incremental. */
  | { type: "user_partial"; text: string }
  /** The turn's committed transcript (Gemini's audio-grounded text). */
  | { type: "user_turn"; text: string }
  /** Reply text, streamed as the model writes it. */
  | { type: "reply_delta"; context: string; text: string }
  /** The model finished writing this reply. */
  | { type: "reply"; context: string; text: string }
  /** Reply audio begins; binary frames that follow are PCM at `sampleRate`. */
  | { type: "audio_start"; context: string; sampleRate: number }
  /** All audio for this reply has been sent. */
  | { type: "audio_end"; context: string }
  /** The learner spoke over the reply — stop local playback NOW and drop any
   *  buffered audio for `context`. `heardText` is what was voiced before the
   *  cut, so the transcript can honestly show only what was heard. */
  | { type: "interrupted"; context: string }
  /** Periodic session stats (Phase 1: logged, not billed). */
  | { type: "stats"; speechSeconds: number; turns: number }
  /** The upstream session is being rotated (Gemini Live ~15 min cap);
   *  momentary — the gateway reconnects with the resumption handle itself. */
  | { type: "rotating" }
  /** Something went wrong and the call CONTINUES. A reply that failed and
   *  was retried, a TTS socket that dropped one line, a transcriber rotation
   *  that took longer than it should. The client logs it; nothing else. On
   *  2026-09-12 every one of these ended the call (`error` → teardown) and
   *  the learner saw the fluent self simply go quiet — no message, no way
   *  back, and nothing in telemetry either. */
  | { type: "warning"; code: string; message: string }
  /** The session's last word, sent right before the socket closes — why it
   *  ended and what happened in it. This is the ONLY per-session record
   *  this path produces (the reply and the voice go straight to their
   *  providers, so the usage ledger sees neither), which is why it exists:
   *  the client writes it to client_events and the console reads it. */
  | { type: "ended"; reason: string; turns: number; speechSeconds: number
      durationMs: number; voiceFirstMs: number[]; warnings: number }
  | { type: "error"; code: string; message: string }

export function send(ws: WebSocket, msg: ServerMessage): void {
  try {
    ws.send(JSON.stringify(msg))
  } catch {
    // Socket already gone — the close handler owns cleanup.
  }
}
