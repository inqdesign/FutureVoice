// topic-engine — scenario categorization, prompt held SERVER-SIDE
// (brain-lift #3's first slice; `android-launch-roadmap.md` §1.13).
//
// v1 serves ONE action, the composer's: sort a typed scenario into a
// category + icon + tidy card summary. The prompt below was EXTRACTED from
// `TopicEngine.categorize` in Swift by script, never retyped; iOS still
// builds it client-side and calls `gemini` — switching iOS over is a
// separate, owner-approved step. Suggestion/path actions extend this same
// function later.
//
// Body: { action: "categorize", text, existing?: string[],
//         icon_options?: string[], target_language? }
// Returns Gemini's own body (client parses candidates[0] as on `/gemini`).
// Utility tier (flash-lite), purpose "topics", free under the daily cap.

import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { requireUser, handlePreflight, errorResponse, cors } from "../_shared/auth.ts"
import { recordFreeUsage, enforceRequestRate, rateLimitedResponse,
         recordProviderUsage, background, geminiUsageFields } from "../_shared/credits.ts"

const SOURCE_FN = "topic-engine"
const MODEL = "gemini-3.1-flash-lite"
const HOURLY_REQUEST_LIMIT = 300
const DAILY_CAP = 200            // = gemini's "topics" cap

function categorizePrompt(existing: string[], iconOptions: string[]): string {
  const existingBlock = existing.length === 0 ? "(none)" : existing.join(", ")
  const iconBlock = iconOptions.join(", ")
  return `You sort a language-practice SCENARIO into a CATEGORY — a short place/theme
bucket the app groups scenarios by — and give it a tidy title.

Existing categories: ${existingBlock}.

Rules:
- category: if one existing category clearly fits, return it EXACTLY,
  isNew=false. Otherwise invent a SHORT new one, 1–2 words, Title Case
  ("Interview", "Landlord", "Doctor", "Dating"), isNew=true.
- icon: best-fitting SF Symbol name from THIS list only:
  ${iconBlock}. If nothing fits, "sparkles".
- summary: a clean ≤6-word title of the SITUATION for a card
  ("Job interview practice", "Returning a jacket, no receipt"). NOT the
  user's raw words — a tidy paraphrase.

Return STRICT JSON only — no prose, no code fences:
{ "category": "...", "icon": "...", "isNew": true, "summary": "..." }`
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

  let body: { action?: unknown; text?: unknown; existing?: unknown
              icon_options?: unknown; target_language?: unknown }
  try { body = await req.json() } catch { return errorResponse(400, "invalid json body") }
  if (body.action !== "categorize") return errorResponse(400, "unsupported action")
  const text = typeof body.text === "string" ? body.text.trim().slice(0, 2000) : ""
  if (!text) return errorResponse(400, "missing text")
  const existing = Array.isArray(body.existing)
    ? (body.existing as unknown[]).filter((x): x is string => typeof x === "string").slice(0, 60)
    : []
  const iconOptions = Array.isArray(body.icon_options)
    ? (body.icon_options as unknown[]).filter((x): x is string => typeof x === "string").slice(0, 60)
    : ["sparkles"]

  const rec = await recordFreeUsage({
    supabase, userId: user.id, action: "gemini", purpose: "topics",
    dailyCap: DAILY_CAP, sourceFn: SOURCE_FN, idempotencyKey: idemKey,
    metadata: { model: MODEL, purpose: "topics", client: "topic-engine" },
  })
  if (!rec.ok) {
    if (rec.reason === "rate_limited") return rateLimitedResponse(cors())
    return errorResponse(500, "usage record failed", rec.detail)
  }

  const geminiBody = {
    system_instruction: { parts: [{ text: categorizePrompt(existing, iconOptions) }] },
    contents: [{ role: "user", parts: [{ text: `scenario: ${text}` }] }],
    generationConfig: {
      // 512, like the Swift call: 160 left nothing for thinking, and this is
      // the only thing standing between a typed scenario and a category.
      maxOutputTokens: 512,
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
