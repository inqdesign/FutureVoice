// Reply engine — the conversation brain of the gateway cascade.
//
// One streaming generateContent call per turn, direct to Gemini with the
// server-held key on a warm HTTPS connection: no per-turn auth, no charge
// RPC, no edge hop — the pre-work that made the old pipeline's gemini_first
// slow is structurally gone here. Text deltas stream out via callback and
// the whole call is abortable, which is what barge-in needs.
//
// Plain prose out, NOT the {reply, suggestion} JSON of the HTTP pipeline:
// the suggestion is display-deferred in the app anyway and moves to its own
// async call in Phase 2 — the voice must never wait on coaching.

const API_HOST = "https://generativelanguage.googleapis.com"

export interface ReplyConfig {
  apiKey: string
  /** e.g. "gemini-3.6-flash" — mirror GeminiClient.Model's default. */
  model: string
  /** Hedge target when `model` is slow or failing ("" / same = no hedge). */
  fallbackModel?: string
  system: string
}

/** Isolate-wide: calls on the same isolate share what the last race taught. */
let primaryDegradedUntil = 0

export class ReplyEngine {
  /** Coach mode's per-turn steer (`SetMessage.steer`), appended to the
   *  system instruction of every generation while it is set. Empty = none. */
  steer = ""

  /** How long the primary gets to write its first token before the
   *  fallback joins. Healthy 3.6-flash at minimal thinking starts in
   *  ~0.5–1.5 s, so 2.5 s only fires on a real stall. */
  hedgeAfterMs = 2500
  /** After a fallback win, skip the primary for this long. */
  degradedForMs = 60_000
  /** Called once per generation the fallback answered. */
  onFallback?: (detail: string) => void

  constructor(private config: ReplyConfig) {}

  /** Stream one reply for the given history. Resolves to the full text.
   *  Aborting mid-stream resolves with what was written so far.
   *
   *  HEDGED (2026-09-29): the primary model gets `hedgeAfterMs` to write
   *  its first token; past that — or the moment it errors (a 503 is how an
   *  overloaded model says so) — the same request goes to `fallbackModel`
   *  as well, and whichever writes FIRST answers the turn. The loser is
   *  aborted at that token, so exactly one voice ever reaches the learner.
   *  Measured the day it was written: gemini-3.6-flash took 7–10 s to say
   *  "hi" for hours while flash-lite answered in 0.6 s, and every call on
   *  every build waited the 7 s — dead air on a phone call is worse than a
   *  plainer sentence. A fallback win marks the primary degraded for
   *  `degradedForMs`, and generations in that window go straight to the
   *  fallback; after it the primary is tried (hedged) again, so recovery
   *  needs no deploy. */
  async generate(
    history: { role: "user" | "model"; text: string }[],
    signal: AbortSignal,
    onDelta: (text: string) => void,
  ): Promise<string> {
    const body = JSON.stringify({
      systemInstruction: {
        parts: [{ text: this.steer ? `${this.config.system}\n\n${this.steer}` : this.config.system }],
      },
      contents: history.map((t) => ({ role: t.role, parts: [{ text: t.text }] })),
      generationConfig: {
        maxOutputTokens: 1024,   // thinking tokens bill against this too
        // "minimal" halves TTFT vs "low" (~1.5 s vs ~2.9 s, measured
        // 2026-08-31 in test/probe-reply-ttft.mjs) and a spoken reply is
        // still MORE deliberation than the 2.5-era pipeline ran with
        // (thinkingBudget 0). Latency is the product here.
        thinkingConfig: { thinkingLevel: "minimal" },
      },
    })

    const primary = this.config.model
    const fallback = this.config.fallbackModel
    if (!fallback || fallback === primary) {
      return this.stream(primary, body, signal, onDelta)
    }
    if (Date.now() < primaryDegradedUntil) {
      return this.stream(fallback, body, signal, onDelta)
    }

    // The race. The first attempt to produce text (or to finish) is the
    // answer: only its deltas are forwarded, the other is aborted. A loser's
    // failure is ignored; the winner's failure is the generation's failure
    // (the session's `recoverReply` retries it).
    return new Promise<string>((resolve, reject) => {
      type Attempt = { model: string; abort: AbortController }
      const attempts: Attempt[] = []
      let winner: Attempt | null = null
      let settled = false
      let failed = 0
      let hedgeTimer: ReturnType<typeof setTimeout> | null = null

      const settle = (fn: () => void) => {
        if (settled) return
        settled = true
        if (hedgeTimer !== null) clearTimeout(hedgeTimer)
        signal.removeEventListener("abort", onOuterAbort)
        fn()
      }
      const claim = (attempt: Attempt) => {
        if (winner !== null) return
        winner = attempt
        if (hedgeTimer !== null) { clearTimeout(hedgeTimer); hedgeTimer = null }
        for (const other of attempts) if (other !== attempt) other.abort.abort()
        if (attempt.model !== primary) {
          primaryDegradedUntil = Date.now() + this.degradedForMs
          this.onFallback?.(`${primary} → ${attempt.model}`)
        }
      }
      const launch = (model: string) => {
        const attempt: Attempt = { model, abort: new AbortController() }
        attempts.push(attempt)
        this.stream(model, body, attempt.abort.signal, (delta) => {
          claim(attempt)
          if (winner === attempt && !signal.aborted) onDelta(delta)
        }).then((full) => {
          // Aborted as the loser: its (empty) result means nothing.
          if (winner !== null && winner !== attempt) return
          claim(attempt)
          settle(() => resolve(full))
        }, (e) => {
          if (signal.aborted) return settle(() => resolve(""))
          if (winner === attempt) return settle(() => reject(e))
          if (winner !== null) return            // lost anyway
          failed += 1
          // The primary erroring is a reason to hedge NOW, not in 2.5 s.
          if (attempts.length === 1) {
            if (hedgeTimer !== null) { clearTimeout(hedgeTimer); hedgeTimer = null }
            launch(fallback)
          } else if (failed === attempts.length) {
            settle(() => reject(e))
          }
        })
      }
      const onOuterAbort = () => {
        for (const a of attempts) a.abort.abort()
        // A winner resolves with what it wrote (the stream returns its text
        // on abort); with no winner there is nothing to keep.
        if (winner === null) settle(() => resolve(""))
      }
      signal.addEventListener("abort", onOuterAbort)

      launch(primary)
      hedgeTimer = setTimeout(() => {
        hedgeTimer = null
        if (winner === null && !settled && attempts.length === 1) launch(fallback)
      }, this.hedgeAfterMs)
    })
  }

  /** One streaming generation against one model. */
  private async stream(
    model: string,
    body: string,
    signal: AbortSignal,
    onDelta: (text: string) => void,
  ): Promise<string> {
    const resp = await fetch(
      `${API_HOST}/v1beta/models/${model}:streamGenerateContent?alt=sse&key=${this.config.apiKey}`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body,
        signal,
      },
    )
    if (!resp.ok || !resp.body) {
      throw new Error(`reply upstream ${model} ${resp.status}: ${(await resp.text()).slice(0, 300)}`)
    }

    let full = ""
    const reader = resp.body.getReader()
    const decoder = new TextDecoder()
    let buffer = ""
    try {
      for (;;) {
        const { done, value } = await reader.read()
        if (done) break
        buffer += decoder.decode(value, { stream: true })
        const lines = buffer.split("\n")
        buffer = lines.pop() ?? ""
        for (const line of lines) {
          if (!line.startsWith("data:")) continue
          const payload = line.slice(5).trim()
          if (!payload || payload === "[DONE]") continue
          let chunk: any
          try { chunk = JSON.parse(payload) } catch { continue }
          const parts = chunk?.candidates?.[0]?.content?.parts
          if (!Array.isArray(parts)) continue
          for (const part of parts) {
            if (typeof part?.text === "string" && part.text.length > 0) {
              full += part.text
              onDelta(part.text)
            }
          }
        }
      }
    } catch (e) {
      if (signal.aborted) return full   // barge-in: keep what was voiced
      throw e
    } finally {
      try { reader.releaseLock() } catch { /* released */ }
    }
    return full
  }
}
