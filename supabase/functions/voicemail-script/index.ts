// voicemail-script — the daily call's opening words, prompt SERVER-SIDE
// (brain-lift). The prompt is GENERATED into `prompt.ts` from
// `VoicemailEngine.swift` by `scripts/android/gen-voicemail-prompt.py`. The caller has
// a MEMORY: the grounding block states the last call's outcome as the
// caller's own recollection, never as app telemetry — and it never scolds,
// because guilt is what makes people stop picking up.
//
// Body: { target_language, native_language, proficiency, persona_name?,
//         last_topic?, last_phrases?, days_since_last_talk?, due_count?,
//         last_outcome?: "answered"|"declined"|"missed", last_callbacks?,
//         consecutive_unanswered?, last_talk_at?, ring_dates?[],
//         utc_offset_minutes?, max_script_characters? }
// `days_since_last_talk` counts only when `last_talk_at` is absent (a build
// from before it); `last_callbacks` / `max_callbacks` are ignored — iOS's
// prompt has no callbacks line.
// Returns Gemini's own body; the JSON inside is { "script": "..." }.
// flash-lite, purpose "daily-call-script".

import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { requireUser, handlePreflight, errorResponse, cors } from "../_shared/auth.ts"
import { recordFreeUsage, enforceRequestRate, rateLimitedResponse,
         recordProviderUsage, background, geminiUsageFields } from "../_shared/credits.ts"
import { BASE_SCRIPT_CHARACTERS, systemPrompt } from "./prompt.ts"

const SOURCE_FN = "voicemail-script"
const MODEL = "gemini-3.1-flash-lite"
const HOURLY_REQUEST_LIMIT = 60
const DAILY_CAP = 20             // = gemini's "daily-call-script" cap

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

  let c: Record<string, unknown>
  try { c = await req.json() } catch { return errorResponse(400, "invalid json body") }
  const str = (k: string) => typeof c[k] === "string" ? c[k] as string : undefined
  const num = (k: string) => typeof c[k] === "number" ? c[k] as number : undefined
  const dateList = (v: unknown) => (Array.isArray(v) ? v as unknown[] : [])
    .filter((x): x is string => typeof x === "string" && !isNaN(Date.parse(x)))
    .map((x) => new Date(x))
  const lastTalkRaw = str("last_talk_at")
  const outcome = str("last_outcome")
  const maxChars = num("max_script_characters")
  const system = systemPrompt({
    targetLanguage: str("target_language") ?? "en",
    nativeLanguage: str("native_language") ?? "ko",
    proficiency: str("proficiency") ?? "b1",
    personaName: str("persona_name")?.trim() || undefined,
    lastTopic: str("last_topic")?.trim() || undefined,
    lastPhrases: Array.isArray(c.last_phrases)
      ? (c.last_phrases as unknown[]).filter((x): x is string => typeof x === "string")
      : [],
    lastTalkAt: lastTalkRaw && !isNaN(Date.parse(lastTalkRaw)) ? new Date(lastTalkRaw) : undefined,
    legacyDaysSinceLastTalk: num("days_since_last_talk"),
    dueCount: num("due_count") ?? 0,
    lastOutcome: outcome === "answered" || outcome === "declined" || outcome === "missed"
      ? outcome : undefined,
    consecutiveUnanswered: num("consecutive_unanswered") ?? 0,
    ringDates: dateList(c.ring_dates),
    utcOffsetMinutes: Math.max(-840, Math.min(840, Math.round(num("utc_offset_minutes") ?? 0))),
    // A build before `max_script_characters` gets the speed-1.0 budget.
    maxScriptCharacters: maxChars && maxChars > 0
      ? Math.min(2 * BASE_SCRIPT_CHARACTERS, Math.round(maxChars)) : BASE_SCRIPT_CHARACTERS,
  })

  const rec = await recordFreeUsage({
    supabase, userId: user.id, action: "gemini", purpose: "daily-call-script",
    dailyCap: DAILY_CAP, sourceFn: SOURCE_FN, idempotencyKey: idemKey,
    metadata: { model: MODEL, purpose: "daily-call-script", client: SOURCE_FN },
  })
  if (!rec.ok) {
    if (rec.reason === "rate_limited") return rateLimitedResponse(cors())
    return errorResponse(500, "usage record failed", rec.detail)
  }

  const upstream = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent?key=${apiKey}`,
    { method: "POST", headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        system_instruction: { parts: [{ text: system }] },
        contents: [{ role: "user", parts: [{ text: "Leave the voicemail." }] }],
        generationConfig: { maxOutputTokens: 400,
          thinkingConfig: { thinkingLevel: "low" },
          responseMimeType: "application/json" },
      }) },
  )
  if (!upstream.ok) {
    const detail = await upstream.text()
    return errorResponse(upstream.status, "gemini upstream error", detail.slice(0, 500))
  }
  const text = await upstream.text()
  try {
    const usage = geminiUsageFields(JSON.parse(text)?.usageMetadata)
    if (usage) background(recordProviderUsage({ idempotencyKey: idemKey, usage }))
  } catch { /* client's problem */ }
  return new Response(text, { status: 200, headers: { "Content-Type": "application/json", ...cors() } })
})
