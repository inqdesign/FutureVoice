// weekly-report — the learner's periodic assessment, prompt held SERVER-SIDE
// (brain-lift; `android-launch-roadmap.md`). The system prompt is EXTRACTED
// from `WeeklyReportEngine.swift` by `scripts/android/gen-weekly-prompt.py`,
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
import { systemPrompt } from "./prompt.ts"

const SOURCE_FN = "weekly-report"
const MODEL = "gemini-3.6-flash"
const HOURLY_REQUEST_LIMIT = 20
// A report covers a whole PERIOD of talking, so nobody needs many in a day —
// and the call is the most expensive one the app makes (the window's entire
// transcript goes in). Same "weekly" pool the client-side path already uses.
const DAILY_CAP = 10

const ENGLISH_NAMES: Record<string, string> = {
  en: "English", es: "Spanish", de: "German", fr: "French", it: "Italian",
  pt: "Portuguese", ja: "Japanese", ko: "Korean", zh: "Chinese",
}
const englishName = (code: string) => ENGLISH_NAMES[code] ?? code.toUpperCase()

/** `CoachingLanguage.contract` — empty when the two languages coincide. */
function coachingContract(target: string, native: string): string {
  const targetName = englishName(target)
  const nativeName = englishName(native)
  if (targetName === nativeName) return ""
  return `LANGUAGE CONTRACT — two languages are in play. Never mix them up:
- The learner is practicing ${targetName}. They think in ${nativeName}.
- MATERIAL stays in ${targetName}: anything the learner is meant to say
  out loud, drill, or memorize — quoted lines, corrected sentences,
  example utterances, vocabulary, expressions.
- COACHING is written in ${nativeName}: anything that explains, judges
  or frames that material — reasons, notes, rationales, summaries,
  hooks, commentary.
- Write ${nativeName} that a native speaker would actually write —
  natural and plain, never a stiff word-for-word translation of an
  English sentence, and never machine-translated grammar terminology
  nobody uses.
- When a ${nativeName} sentence refers to a ${targetName} word or
  phrase, QUOTE it in ${targetName} inside the ${nativeName} sentence
  and do not translate the quoted part. Example shape: 「"went to the
  bank"처럼 과거형으로」.
- The per-field rules below name a language for each field. Where they
  do, they win over this preamble.

`
}

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

/** `WeeklyReportEngine.userPrompt`, same sections and same caps. */
function userPrompt(body: WeeklyBody): string {
  const prior = (body.prior_corpus ?? []).slice(0, 500)
  const window = (body.window ?? []).slice(0, 500)
  const pairs = (body.suggestion_pairs ?? []).slice(0, 100)
  return `# PRIOR CORPUS (user utterances from earlier sessions, before this window)
${prior.length ? prior.join("\n") : "(none — first report)"}

# THIS WINDOW (user utterances during the period being analyzed)
${window.join("\n")}

# OBJECTIVE VOCAB PROFILE (distinct words in this window, graded against the CEFR word list — measured, not opinion)
${body.vocab_profile ?? "(none)"}

# MEASURED DELIVERY (deterministic, from the live mic + verified analysis — NOT visible in the text above)
${body.delivery_evidence ?? "(none)"}

# SUGGESTION PAIRS THIS WINDOW (the avatar's fluent rephrasings — includes purely stylistic upgrades, not only errors)
${pairs.length
    ? pairs.map((p) => `- user said: "${p.said}"\n  fluent: "${p.alt}"`).join("\n")
    : "(none)"}`
}

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
    contents: [{ role: "user", parts: [{ text: userPrompt(body) }] }],
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
