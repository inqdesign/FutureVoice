// session-summary — the post-talk analysis, prompt held SERVER-SIDE.
//
// The first engine of the brain-lift (`docs/android-launch-roadmap.md` §1.13):
// the summary prompt from `ConversationEngine.summarySystemPrompt` +
// `CoachingLanguage.contract`, GENERATED into `prompt.ts` from the Swift
// source at the Android baseline ref by `scripts/android/gen-summary-prompt.py`
// (never retyped, never hand-edited), so a client that
// has no prompt of its own — Android — gets byte-for-byte the same analysis
// iOS produces. iOS still builds this prompt client-side and calls `gemini`
// directly; it is NOT switched to this function (that is a separate, owner-
// approved step). Keep the two texts identical: when the Swift prompt
// changes, re-run the generator, never hand-edit.
//
// Body: { target_language, native_language, profile, known_about_user?,
//         remembered_notes?, share_corrections?, expression_budget?,
//         transcript, metrics, stream? }
// Every field after `profile` but `transcript` is OPTIONAL: a build that
// predates one still gets a valid prompt ("(nothing yet)" in its place).
//   known_about_user   — what the learner TYPED (`UserPersona.knownFacts`)
//   remembered_notes   — [{ text, kind: "fact"|"now", learned_at: ISO }], the
//                        notebook in the client's order; `about_user.replaces`
//                        is a 1-based index into THIS list
//   share_corrections  — [{ text, from, to }], rungs "nothing"|"gist"|"all"
// `transcript` is the `[USER] … / [FLUENT_SELF] …` block the client formats
// (`ConversationEngine.formatTranscript`); `metrics` is the deterministic
// ScorecardMetrics JSON the client computed (`behavior.md` §5) — the server
// never invents a number. Response: Gemini's own body, SSE when `stream`
// (same `X-Gemini-Stream: sse` handshake as `gemini`), so the client's
// streaming parser is shared. Free, capped like purpose "summary".

import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { requireUser, handlePreflight, errorResponse, cors } from "../_shared/auth.ts"
import { recordFreeUsage, enforceRequestRate, rateLimitedResponse,
         recordProviderUsage, background, geminiUsageFields } from "../_shared/credits.ts"
import { summarySystemPrompt, type RememberedNote, type ShareCorrection } from "./prompt.ts"

const SOURCE_FN = "session-summary"
const MODEL = "gemini-3.6-flash"
const HOURLY_REQUEST_LIMIT = 120
const DAILY_CAP = 60            // = gemini's "summary" cap
const MAX_TOKENS = 8192         // see SessionSummarizer.swift for why this large

Deno.serve(async (req) => {
  const pre = handlePreflight(req)
  if (pre) return pre
  if (req.method !== "POST") return errorResponse(405, "method not allowed")

  const authed = await requireUser(req)
  if (authed instanceof Response) return authed
  const { user, supabase } = authed

  const idemKey = req.headers.get("X-Idempotency-Key")
  if (!idemKey) return errorResponse(400, "missing X-Idempotency-Key header")

  const apiKey = Deno.env.get("GEMINI_API_KEY")
  if (!apiKey) return errorResponse(500, "server missing GEMINI_API_KEY")

  const rate = await enforceRequestRate({
    userId: user.id, sourceFn: SOURCE_FN, limit: HOURLY_REQUEST_LIMIT,
  })
  if (!rate.ok) return rateLimitedResponse(cors())

  let body: {
    target_language?: string; native_language?: string; profile?: unknown
    known_about_user?: unknown; expression_budget?: unknown
    remembered_notes?: unknown; share_corrections?: unknown
    transcript?: unknown; metrics?: unknown; stream?: unknown
  }
  try { body = await req.json() } catch { return errorResponse(400, "invalid json body") }
  const targetLanguage = typeof body.target_language === "string" ? body.target_language : "en"
  const nativeLanguage = typeof body.native_language === "string" ? body.native_language : "ko"
  const transcript = typeof body.transcript === "string" ? body.transcript.trim() : ""
  if (!transcript) return errorResponse(400, "missing transcript")
  const knownAboutUser = Array.isArray(body.known_about_user)
    ? (body.known_about_user as unknown[]).filter((k): k is string => typeof k === "string").slice(0, 60)
    : []
  const rememberedNotes = parseRememberedNotes(body.remembered_notes)
  const shareCorrections = parseShareCorrections(body.share_corrections)
  const expressionBudget = typeof body.expression_budget === "number"
    ? Math.min(14, Math.max(6, Math.round(body.expression_budget))) : 6
  const metricsJSON = typeof body.metrics === "string"
    ? body.metrics : JSON.stringify(body.metrics ?? {})
  const stream = body.stream === true

  const rec = await recordFreeUsage({
    supabase, userId: user.id, action: "gemini_summary", purpose: "summary",
    dailyCap: DAILY_CAP, sourceFn: SOURCE_FN, idempotencyKey: idemKey,
    metadata: { model: MODEL, purpose: "summary", client: "session-summary" },
  })
  if (!rec.ok) {
    if (rec.reason === "rate_limited") return rateLimitedResponse(cors())
    return errorResponse(500, "usage record failed", rec.detail)
  }

  const system = summarySystemPrompt({
    targetLanguage, nativeLanguage, profile: body.profile ?? {},
    knownAboutUser, rememberedNotes, shareCorrections, expressionBudget,
  })
  // Same user message SessionSummarizer.swift builds.
  const userMessage = `transcript:\n${transcript}\n\nmetrics:\n${metricsJSON}`
  const geminiBody = {
    system_instruction: { parts: [{ text: system }] },
    contents: [{ role: "user", parts: [{ text: userMessage }] }],
    generationConfig: {
      maxOutputTokens: MAX_TOKENS,
      thinkingConfig: { thinkingLevel: "low" },
      responseMimeType: "application/json",
    },
  }

  const endpoint = stream
    ? `${MODEL}:streamGenerateContent?alt=sse&key=${apiKey}`
    : `${MODEL}:generateContent?key=${apiKey}`
  const upstream = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${endpoint}`,
    { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(geminiBody) },
  )
  if (!upstream.ok) {
    const detail = await upstream.text()
    return errorResponse(upstream.status, "gemini upstream error", detail.slice(0, 500))
  }

  if (stream && upstream.body) {
    const [toClient, toMeter] = upstream.body.tee()
    background(meterStream(toMeter, idemKey))
    return new Response(toClient, {
      status: 200,
      headers: {
        "Content-Type": "text/event-stream",
        "Cache-Control": "no-cache",
        "X-Gemini-Stream": "sse",
        ...cors(),
      },
    })
  }

  const text = await upstream.text()
  try {
    const usage = geminiUsageFields(JSON.parse(text)?.usageMetadata)
    if (usage) background(recordProviderUsage({ idempotencyKey: idemKey, usage }))
  } catch { /* unparseable body is the client's problem, not the meter's */ }
  return new Response(text, { status: 200, headers: { "Content-Type": "application/json", ...cors() } })
})

const SHARES = new Set(["nothing", "gist", "all"])
const obj = (v: unknown): Record<string, unknown> | null =>
  v && typeof v === "object" && !Array.isArray(v) ? v as Record<string, unknown> : null

/**
 * The numbered notebook. An element that can't be read is DROPPED, never
 * defaulted — but dropping renumbers the list, and `replaces` is an index
 * into the list as the CLIENT holds it. So one bad element voids the whole
 * list: the model then sees "(nothing yet)" and can only add lines, which is
 * the safe failure (a wrong number would overwrite the wrong memory).
 */
function parseRememberedNotes(raw: unknown): RememberedNote[] {
  if (!Array.isArray(raw)) return []
  const out: RememberedNote[] = []
  for (const e of raw.slice(0, 60)) {
    const o = obj(e)
    const text = typeof o?.text === "string" ? o.text.trim() : ""
    const kind = o?.kind === "now" ? "now" : "fact"
    const learnedAt = typeof o?.learned_at === "string" ? new Date(o.learned_at) : null
    if (!text || !learnedAt || isNaN(learnedAt.getTime())) return []
    out.push({ text: text.slice(0, 280), kind, learnedAt })
  }
  return out
}

/** The learner's last hand moves between share rungs (iOS keeps 8). */
function parseShareCorrections(raw: unknown): ShareCorrection[] {
  if (!Array.isArray(raw)) return []
  return raw.slice(-8).flatMap((e) => {
    const o = obj(e)
    const text = typeof o?.text === "string" ? o.text.trim() : ""
    const from = o?.from, to = o?.to
    if (!text || typeof from !== "string" || typeof to !== "string" ||
        !SHARES.has(from) || !SHARES.has(to)) return []
    return [{ text: text.slice(0, 280), from, to }]
  })
}

// Copy of gemini/index.ts's meterStream (that file is iOS-called and is not
// edited for Android work). Gemini's usageMetadata is cumulative — keep the last.
async function meterStream(body: ReadableStream<Uint8Array>, idempotencyKey: string): Promise<void> {
  const reader = body.getReader()
  const decoder = new TextDecoder()
  let buffer = ""
  let last: Record<string, unknown> | null = null
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
        try {
          const um = JSON.parse(payload)?.usageMetadata
          if (um) last = um
        } catch { /* partial or non-JSON event */ }
      }
    }
  } catch (e) {
    console.error("meterStream read failed", e)
  } finally {
    try { reader.releaseLock() } catch { /* already released */ }
  }
  const usage = geminiUsageFields(last)
  if (usage) await recordProviderUsage({ idempotencyKey, usage })
}
