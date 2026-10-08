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

import { steerTurnText } from "./steer-turn"

const API_HOST = "https://generativelanguage.googleapis.com"

/** What a call's generations cost, summed (2026-10-08). The reply calls go
 *  straight to Gemini, so no ledger row ever saw them, and they were most of
 *  the Gemini bill before anyone looked. Logged once per call. */
export interface ReplyUsage {
  calls: number
  promptTokens: number
  cachedTokens: number
  outputTokens: number
  thoughtTokens: number
}

export interface ReplyConfig {
  apiKey: string
  /** e.g. "gemini-3.6-flash" — mirror GeminiClient.Model's default. */
  model: string
  /** Hedge target when `model` is slow or failing ("" / same = no hedge). */
  fallbackModel?: string
  system: string
}

/** One generation request, and whether it reads the cached system prompt. */
type Body = { json: string; cached: boolean }

/** Isolate-wide: calls on the same isolate share what the last race taught. */
let primaryDegradedUntil = 0

export class ReplyEngine {
  /** Coach mode's per-turn steer (`SetMessage.steer`), carried as a note on
   *  the learner's last turn of every generation while it is set (it was the
   *  system instruction's tail until the system instruction became a cache —
   *  see `steer-turn.ts`). Empty = none. */
  steer = ""

  readonly usage: ReplyUsage = { calls: 0, promptTokens: 0, cachedTokens: 0, outputTokens: 0, thoughtTokens: 0 }

  /** The system prompt as an explicit Gemini cache (2026-10-08).
   *
   *  Every generation used to send the whole system prompt (~4–6k tokens)
   *  plus the call so far, and speculation sends it again for a turn the
   *  learner hasn't finished — 33M input tokens in the first eight days of
   *  October, 60% of the Gemini bill. Implicit caching should have caught a
   *  prefix that never changes inside a call, and measured, it didn't (7% of
   *  input tokens cached; test/probe-reply-cache.mjs: 0 cached on identical
   *  back-to-back requests). An explicit cache bills those tokens at a tenth.
   *  The model reads the same bytes, so the reply is the same reply.
   *
   *  Made LAZILY, on the first generation — a call opened and abandoned costs
   *  nothing — and that first generation runs uncached beside it. Kept alive
   *  with a short TTL that each generation stretches, deleted on `dispose`;
   *  a DO that dies without disposing loses at most one TTL of storage. Any
   *  failure here — creating, extending, a generation the cache refuses — is
   *  the old uncached request, never a failed turn. Primary model only: the
   *  hedge's fallback runs uncached (a cache belongs to one model). */
  private cache: { name: string; model: string; expiresAt: number } | null = null
  private cacheState: "none" | "creating" | "ready" | "off" = "none"
  static readonly cacheTtlSeconds = 600
  /** Stretch the TTL when less than this is left. */
  static readonly cacheRefreshBelowMs = 240_000

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
    this.ensureCache()
    const contents = history.map((t) => ({ role: t.role, parts: [{ text: t.text }] }))
    const last = contents[contents.length - 1]
    if (this.steer && last?.role === "user") {
      last.parts = [{ text: steerTurnText(last.parts[0].text, this.steer) }]
    }
    const generationConfig = {
      maxOutputTokens: 1024,   // thinking tokens bill against this too
      // "minimal" halves TTFT vs "low" (~1.5 s vs ~2.9 s, measured
      // 2026-08-31 in test/probe-reply-ttft.mjs) and a spoken reply is
      // still MORE deliberation than the 2.5-era pipeline ran with
      // (thinkingBudget 0). Latency is the product here.
      thinkingConfig: { thinkingLevel: "minimal" },
    }
    // A steer with no learner turn to ride on (never, in practice: every
    // generation answers one) keeps the old place, uncached.
    const steerInSystem = this.steer && last?.role !== "user"
    const body = (model: string, useCache: boolean): Body => {
      const cache = useCache && !steerInSystem && this.cache?.model === model ? this.cache : null
      return { cached: cache !== null, json: JSON.stringify(cache
        ? { cachedContent: cache.name, contents, generationConfig }
        : {
            systemInstruction: {
              parts: [{ text: steerInSystem ? `${this.config.system}\n\n${this.steer}` : this.config.system }],
            },
            contents, generationConfig,
          }) }
    }

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
    body: (model: string, useCache: boolean) => Body,
    signal: AbortSignal,
    onDelta: (text: string) => void,
  ): Promise<string> {
    const post = (b: string) => fetch(
      `${API_HOST}/v1beta/models/${model}:streamGenerateContent?alt=sse&key=${this.config.apiKey}`,
      { method: "POST", headers: { "Content-Type": "application/json" }, body: b, signal },
    )
    const first = body(model, true)
    let resp = await post(first.json)
    if (first.cached && !resp.ok && resp.status >= 400 && resp.status < 500) {
      // The cache expired or was refused: drop it and answer this turn the
      // old way. The next generation makes a new one.
      const detail = (await resp.text()).slice(0, 200)
      console.log(`reply cache refused (${resp.status}): ${detail}`)
      this.cache = null
      this.cacheState = "none"
      resp = await post(body(model, false).json)
    }
    if (!resp.ok || !resp.body) {
      throw new Error(`reply upstream ${model} ${resp.status}: ${(await resp.text()).slice(0, 300)}`)
    }
    this.usage.calls += 1

    let full = ""
    let lastUsage: any = null
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
          // Cumulative per stream; the last chunk carries the totals. An
          // aborted speculation never gets one, which undercounts it.
          if (chunk?.usageMetadata) lastUsage = chunk.usageMetadata
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
      if (lastUsage) {
        this.usage.promptTokens += lastUsage.promptTokenCount ?? 0
        this.usage.cachedTokens += lastUsage.cachedContentTokenCount ?? 0
        this.usage.outputTokens += lastUsage.candidatesTokenCount ?? 0
        this.usage.thoughtTokens += lastUsage.thoughtsTokenCount ?? 0
      }
    }
    return full
  }

  /** Make the cache if there is none, stretch it if it is running out. Never
   *  awaited: a generation never waits on its cache. */
  private ensureCache(): void {
    if (this.cacheState === "off" || this.cacheState === "creating") return
    const model = this.config.model
    if (this.cacheState === "ready" && this.cache) {
      if (this.cache.expiresAt - Date.now() > ReplyEngine.cacheRefreshBelowMs) return
      const cache = this.cache
      cache.expiresAt = Date.now() + ReplyEngine.cacheTtlSeconds * 1000   // one stretch in flight
      void fetch(`${API_HOST}/v1beta/${cache.name}?updateMask=ttl&key=${this.config.apiKey}`, {
        method: "PATCH", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ ttl: `${ReplyEngine.cacheTtlSeconds}s` }),
      }).then(async (r) => {
        if (!r.ok) {
          console.log(`reply cache extend failed (${r.status}): ${(await r.text()).slice(0, 200)}`)
          if (this.cache === cache) { this.cache = null; this.cacheState = "none" }
        }
      }).catch(() => { if (this.cache === cache) { this.cache = null; this.cacheState = "none" } })
      return
    }
    this.cacheState = "creating"
    const startedAt = Date.now()
    void fetch(`${API_HOST}/v1beta/cachedContents?key=${this.config.apiKey}`, {
      method: "POST", headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        model: `models/${model}`,
        systemInstruction: { parts: [{ text: this.config.system }] },
        ttl: `${ReplyEngine.cacheTtlSeconds}s`,
      }),
    }).then(async (r) => {
      const j: any = await r.json().catch(() => null)
      if (this.disposed) {
        if (j?.name) void this.deleteCache(j.name)
        return
      }
      if (!r.ok || typeof j?.name !== "string") {
        // 400 = the model won't cache this (too short, unsupported). Don't
        // ask again for the rest of the call.
        console.log(`reply cache create failed (${r.status}): ${JSON.stringify(j?.error ?? j).slice(0, 200)}`)
        this.cacheState = r.status === 400 ? "off" : "none"
        return
      }
      this.cache = { name: j.name, model, expiresAt: startedAt + ReplyEngine.cacheTtlSeconds * 1000 }
      this.cacheState = "ready"
      console.log(`reply cache ready ${Date.now() - startedAt}ms, ${j.usageMetadata?.totalTokenCount ?? "?"} tokens`)
    }).catch((e) => {
      this.cacheState = "none"
      console.log(`reply cache create error: ${String(e).slice(0, 120)}`)
    })
  }

  private disposed = false

  /** The call is over: delete the cache rather than pay storage until its
   *  TTL runs out. */
  dispose(): void {
    this.disposed = true
    if (this.cache) void this.deleteCache(this.cache.name)
    this.cache = null
    this.cacheState = "off"
  }

  private deleteCache(name: string): Promise<void> {
    return fetch(`${API_HOST}/v1beta/${name}?key=${this.config.apiKey}`, { method: "DELETE" })
      .then(() => undefined, () => undefined)
  }
}
