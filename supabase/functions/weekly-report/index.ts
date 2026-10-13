// weekly-report — the learner's periodic assessment, prompt held SERVER-SIDE
// (brain-lift; `android-launch-roadmap.md`). The system prompt is EXTRACTED
// (with the user prompt) from `WeeklyReportEngine.swift` by
// `scripts/android/gen-weekly-prompt.py`,
// never retyped; iOS still builds it client-side and calls `gemini` until
// switched.
//
// Body: { target_language, native_language, prior_corpus[], window[],
//         vocab_profile, delivery_evidence, suggestion_pairs[],
//         previous_summary? }
// Returns Gemini's own body (buffered — nothing here can be used before the
// payload closes). Purpose "weekly".

import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { requireUser, handlePreflight, errorResponse, cors } from "../_shared/auth.ts"
import { recordFreeUsage, enforceRequestRate, rateLimitedResponse,
         recordProviderUsage, background, geminiUsageFields } from "../_shared/credits.ts"
import { coachingContract, englishName, systemPrompt, userPrompt } from "./prompt.ts"

const SOURCE_FN = "weekly-report"
const MODEL = "gemini-3.6-flash"
const HOURLY_REQUEST_LIMIT = 20
// A report covers a whole PERIOD of talking, so nobody needs many in a day —
// and the call is the most expensive one the app makes (the window's entire
// transcript goes in). Same "weekly" pool the client-side path already uses.
const DAILY_CAP = 10

interface WeeklyBody {
  target_language?: unknown
  native_language?: unknown
  previous_summary?: unknown
  prior_corpus?: string[]
  window?: string[]
  vocab_profile?: string
  delivery_evidence?: string
  suggestion_pairs?: { said: string; alt: string }[]
}

const strings = (v: unknown): string[] =>
  Array.isArray(v) ? (v as unknown[]).filter((x): x is string => typeof x === "string") : []

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

  let body: WeeklyBody
  try { body = await req.json() } catch { return errorResponse(400, "invalid json body") }
  const target = typeof body.target_language === "string" ? body.target_language : "en"
  const native = typeof body.native_language === "string" ? body.native_language : "en"
  if (!Array.isArray(body.window) || body.window.length === 0) {
    return errorResponse(400, "no window utterances")
  }

  const rec = await recordFreeUsage({
    supabase, userId: user.id, action: "gemini", purpose: "weekly",
    dailyCap: DAILY_CAP, sourceFn: SOURCE_FN, idempotencyKey: idemKey,
    metadata: { model: MODEL, purpose: "weekly", client: "weekly-report" },
  })
  if (!rec.ok) {
    if (rec.reason === "rate_limited") return rateLimitedResponse(cors())
    return errorResponse(500, "usage record failed", rec.detail)
  }

  const system = systemPrompt(
    englishName(target),
    englishName(native),
    coachingContract(target, native),
    typeof body.previous_summary === "string" ? body.previous_summary : null,
  )

  const geminiBody = {
    system_instruction: { parts: [{ text: system }] },
    contents: [{ role: "user", parts: [{ text: userPrompt(
      strings(body.prior_corpus), strings(body.window),
      (Array.isArray(body.suggestion_pairs) ? body.suggestion_pairs : [])
        .filter((p) => p && typeof p.said === "string" && typeof p.alt === "string"),
      typeof body.vocab_profile === "string" ? body.vocab_profile : "(none)",
      typeof body.delivery_evidence === "string" ? body.delivery_evidence : "(none)",
    ) }] }],
    generationConfig: {
      // The report has six sections and three arrays of up to five items
      // each; a tight ceiling truncates the JSON and loses the whole call.
      maxOutputTokens: 4096,
      thinkingConfig: { thinkingLevel: "low" },
      responseMimeType: "application/json",
    },
  }
  const upstream = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent?key=${apiKey}`,
    { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(geminiBody) },
  )
  if (!upstream.ok) {
    const detail = await upstream.text()
    return errorResponse(upstream.status, "gemini upstream error", detail.slice(0, 500))
  }
  const responseText = await upstream.text()
  try {
    const usage = geminiUsageFields(JSON.parse(responseText)?.usageMetadata)
    if (usage) background(recordProviderUsage({ idempotencyKey: idemKey, usage }))
  } catch { /* unparseable body is the client's problem, not the meter's */ }
  return new Response(responseText, {
    status: 200, headers: { "Content-Type": "application/json", ...cors() },
  })
})
