// drill-enrichment — a thin drill card turned into something a learner can
// actually internalize: examples grounded in THEIR life, alternate phrasings,
// and a memory hook. Prompt held SERVER-SIDE, EXTRACTED from
// `DrillEnrichmentEngine.swift` by `scripts/android/gen-enrichment-prompt.py`
// and never retyped; iOS still builds it client-side and calls `gemini`.
//
// Body: { target_phrase, source_phrase?, reason?, persona?,
//         target_language?, native_language? }
// Returns Gemini's own body. Purpose "enrichment" — the same free pool the
// client-side path already records against.

import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { requireUser, handlePreflight, errorResponse, cors } from "../_shared/auth.ts"
import { recordFreeUsage, enforceRequestRate, rateLimitedResponse,
         recordProviderUsage, background, geminiUsageFields } from "../_shared/credits.ts"
import { systemPrompt } from "./prompt.ts"

const SOURCE_FN = "drill-enrichment"
const MODEL = "gemini-3.6-flash"
const HOURLY_REQUEST_LIMIT = 120
const DAILY_CAP = 60             // = gemini's "enrichment" cap

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

interface Body {
  target_phrase?: unknown
  source_phrase?: unknown
  reason?: unknown
  persona?: string[]
  target_language?: unknown
  native_language?: unknown
}

/** `DrillEnrichmentEngine.userMessage`, same shape and same order. */
function userMessage(b: Body): string {
  const lines: string[] = []
  const src = typeof b.source_phrase === "string" ? b.source_phrase : ""
  if (src) lines.push(`source_phrase: ${src}`)
  lines.push(`target_phrase: ${String(b.target_phrase ?? "")}`)
  const reason = typeof b.reason === "string" ? b.reason : ""
  if (reason) lines.push(`reason: ${reason}`)
  lines.push("")
  lines.push("persona:")
  const persona = Array.isArray(b.persona)
    ? b.persona.filter((x): x is string => typeof x === "string").slice(0, 12)
    : []
  if (persona.length) lines.push(...persona)
  else lines.push("- (sparse — pick neutral but believable scenarios)")
  return lines.join("\n")
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

  let body: Body
  try { body = await req.json() } catch { return errorResponse(400, "invalid json body") }
  const target = typeof body.target_language === "string" ? body.target_language : "en"
  const native = typeof body.native_language === "string" ? body.native_language : "en"
  if (typeof body.target_phrase !== "string" || !body.target_phrase.trim()) {
    return errorResponse(400, "missing target_phrase")
  }

  const rec = await recordFreeUsage({
    supabase, userId: user.id, action: "gemini", purpose: "enrichment",
    dailyCap: DAILY_CAP, sourceFn: SOURCE_FN, idempotencyKey: idemKey,
    metadata: { model: MODEL, purpose: "enrichment", client: "drill-enrichment" },
  })
  if (!rec.ok) {
    if (rec.reason === "rate_limited") return rateLimitedResponse(cors())
    return errorResponse(500, "usage record failed", rec.detail)
  }

  const geminiBody = {
    system_instruction: {
      parts: [{ text: systemPrompt(englishName(target), englishName(native),
                                   coachingContract(target, native)) }],
    },
    contents: [{ role: "user", parts: [{ text: userMessage(body) }] }],
    generationConfig: {
      // Three examples, three variants and a hook — each carrying a
      // native-language line. A tight ceiling truncates the JSON and loses
      // the whole call.
      maxOutputTokens: 2048,
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
