// voicemail-script — the daily call's opening words, prompt SERVER-SIDE
// (brain-lift; `VoicemailEngine.swift`, extracted by script). The caller has
// a MEMORY: the grounding block states the last call's outcome as the
// caller's own recollection, never as app telemetry — and it never scolds,
// because guilt is what makes people stop picking up.
//
// Body: { target_language, native_language, proficiency, persona_name?,
//         last_topic?, last_phrases?, days_since_last_talk?, due_count?,
//         last_outcome?: "answered"|"declined"|"missed", last_callbacks?,
//         consecutive_unanswered?, max_callbacks? }
// Returns Gemini's own body; the JSON inside is { "script": "..." }.
// flash-lite, purpose "daily-call-script".

import { BREATH_PUNCTUATION } from "../_shared/breath.ts"
import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { requireUser, handlePreflight, errorResponse, cors } from "../_shared/auth.ts"
import { recordFreeUsage, enforceRequestRate, rateLimitedResponse,
         recordProviderUsage, background, geminiUsageFields } from "../_shared/credits.ts"

const SOURCE_FN = "voicemail-script"
const MODEL = "gemini-3.1-flash-lite"
const HOURLY_REQUEST_LIMIT = 60
const DAILY_CAP = 20             // = gemini's "daily-call-script" cap
const MAX_SCRIPT_CHARACTERS = 260

const ENGLISH_NAMES: Record<string, string> = {
  en: "English", es: "Spanish", de: "German", fr: "French", it: "Italian",
  pt: "Portuguese", ja: "Japanese", ko: "Korean", zh: "Chinese",
}
const englishName = (c: string) => ENGLISH_NAMES[c] ?? c.toUpperCase()

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
  const targetName = englishName(str("target_language") ?? "en")
  const nativeName = englishName(str("native_language") ?? "ko")
  const prof = (str("proficiency") ?? "b1").toUpperCase()
  const name = str("persona_name")?.trim() || "the learner"
  const maxCallbacks = num("max_callbacks") ?? 3

  const grounding: string[] = []
  const topic = str("last_topic")
  if (topic) grounding.push(`Their last talk was about: ${topic}`)
  const phrases = Array.isArray(c.last_phrases)
    ? (c.last_phrases as unknown[]).filter((x): x is string => typeof x === "string").slice(0, 4)
    : []
  if (phrases.length > 0) {
    grounding.push('Phrases that came up in it: ' + phrases.map((p) => `"${p}"`).join(", "))
  }
  // Dated to the RING, not the writing (iOS 632c2ce): the script is written
  // at a talk's end and heard at the next ring, usually the next morning, so
  // "0 days" at writing time announced last night's talk as "already
  // practiced today" at 8 a.m. A build that sends last_talk_at + ring_dates
  // gets calendar days in its own zone; an older build's day count is kept.
  const offset = Math.max(-840, Math.min(840, Math.round(num("utc_offset_minutes") ?? 0)))
  const localDay = (d: Date) => Math.floor((d.getTime() + offset * 60_000) / 86_400_000)
  const ringDates = (Array.isArray(c.ring_dates) ? c.ring_dates as unknown[] : [])
    .filter((x): x is string => typeof x === "string" && !isNaN(Date.parse(x)))
    .map((x) => new Date(x)).sort((a, b) => a.getTime() - b.getTime())
  const lastTalkAt = str("last_talk_at") && !isNaN(Date.parse(str("last_talk_at")!))
    ? new Date(str("last_talk_at")!) : undefined
  const ringDay = ringDates[0] ?? new Date()
  const days = lastTalkAt ? Math.max(0, localDay(ringDay) - localDay(lastTalkAt)) : num("days_since_last_talk")
  if (days !== undefined) {
    grounding.push(days === 0 ? (lastTalkAt ? "They already had a talk earlier today." : "They already practiced today.")
      : days === 1 ? "Their last talk was yesterday."
      : `It has been ${days} days since their last talk.`)
  }
  // When they hear it (iOS `whenHeard`): one ring names its part of the day;
  // several forbid a time-of-day greeting.
  const WD = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
  const MO = ["January", "February", "March", "April", "May", "June", "July", "August",
    "September", "October", "November", "December"]
  const local = (d: Date) => new Date(d.getTime() + offset * 60_000)
  const hhmm = (d: Date) => { const l = local(d); return `${String(l.getUTCHours()).padStart(2, "0")}:${String(l.getUTCMinutes()).padStart(2, "0")}` }
  const partOfDay = (h: number) => h >= 5 && h < 12 ? "morning" : h >= 12 && h < 17 ? "afternoon" : h >= 17 && h < 22 ? "evening" : "night"
  const dayLine = (d: Date) => { const l = local(d); return `${WD[l.getUTCDay()]}, ${l.getUTCDate()} ${MO[l.getUTCMonth()]} ${l.getUTCFullYear()}` }
  const whenHeard = ringDates.length === 0 ? ""
    : ringDates.length === 1
      ? `It rings on ${dayLine(ringDates[0])}, at ${hhmm(ringDates[0])} — ${partOfDay(local(ringDates[0]).getUTCHours())}.`
      : `It rings on ${dayLine(ringDates[0])}, at ${ringDates.map(hhmm).join(", ")} — the same message each time until they pick up, so you cannot know which part of the day they hear it in.`
  const due = num("due_count") ?? 0
  if (due > 0) grounding.push(`${due} review cards are waiting.`)
  const lastCallbacks = num("last_callbacks") ?? 0
  switch (str("last_outcome")) {
    case "answered": grounding.push("Last time you called, they picked up and you talked."); break
    case "declined": grounding.push(lastCallbacks >= maxCallbacks
      ? "Last time you called, they kept saying they couldn't talk, and you gave up for the day."
      : "Last time you called, they said they couldn't talk right then."); break
    case "missed": grounding.push("Last time you called, they never picked up."); break
  }
  const unanswered = num("consecutive_unanswered") ?? 0
  if (unanswered >= 2) grounding.push(`You haven't actually got hold of them in ${unanswered} calls.`)
  const groundingBlock = grounding.length === 0
    ? "You have no history with them yet — this is the first call."
    : grounding.map((g) => `- ${g}`).join("\n")

  const rec = await recordFreeUsage({
    supabase, userId: user.id, action: "gemini", purpose: "daily-call-script",
    dailyCap: DAILY_CAP, sourceFn: SOURCE_FN, idempotencyKey: idemKey,
    metadata: { model: MODEL, purpose: "daily-call-script", client: SOURCE_FN },
  })
  if (!rec.ok) {
    if (rec.reason === "rate_limited") return rateLimitedResponse(cors())
    return errorResponse(500, "usage record failed", rec.detail)
  }

  const system = `You are the learner's own FLUENT FUTURE SELF, leaving them a short
voicemail to start a practice call. Same person, same voice — you are
not a tutor, a coach, or an assistant, and you never sound like one.

WHAT YOU KNOW ABOUT THEM
${groundingBlock}
${whenHeard ? `
WHEN THEY HEAR IT
${whenHeard}
` : ""}
YOU ARE CALLING THEM, and that is not a figure of speech. You remember
how the last call went and you open like someone who does. If they
couldn't talk last time, acknowledge it lightly and move on. If you
haven't reached them in days, say so the way a friend would — mild,
curious, never wounded and never scolding. Guilt is the one thing that
makes people stop picking up.

WRITE ONE VOICEMAIL in ${targetName}:
- ${BREATH_PUNCTUATION}
- 2–3 sentences, UNDER ${MAX_SCRIPT_CHARACTERS} characters total. It is
  spoken aloud in under 25 seconds — that ceiling is hard.
- Sentence 1 picks up something CONCRETE from the grounding above —
  the last call's outcome first if there was one, otherwise the last
  talk. If there is nothing to pick up, say something specific about
  today instead — never a generic "ready to practice?" opener.
- The LAST sentence is a QUESTION they can answer out loud immediately,
  about their own life. This is the whole point of the call: they
  should feel a question waiting, not an invitation.
- Natural spoken ${targetName} a CEFR ${prof}
  learner follows at speed. Contractions, no literary phrasing.
- In a language that separates formal from informal address (Korean
  반말, Japanese plain form, German du, French tu, Spanish tú…), use the
  INFORMAL form — it is you talking to yourself.
- WARM MEANS INTERESTED, NOT AFFECTIONATE. You are them, not someone who longs for them: never say you miss them, missed them, want to see them or hear their voice, love them, or are so happy to hear from them (보고 싶어, 목소리 듣고 싶어서, 会いたい, I miss you, du fehlst mir). Warmth is a casual, specific interest in what is going on with them.
- Warm and casual, the way you'd talk to yourself. Never congratulate
  them, never mention streaks, goals, minutes, or the app.
- Address ${name} by name at most ONCE, and only if it sounds natural.
- No numbers read as statistics. If review cards are waiting, that is a
  reason to bring up a phrase, not a count to recite.

OUTPUT LANGUAGE: the script is MATERIAL — every word is in
${targetName}. Nothing in ${nativeName}
and nothing in English unless ${targetName} IS English.

Speakable as-is: no stage directions, no asterisks, no brackets, no
placeholders, no "[name]".

Return STRICT JSON only — no prose, no code fences:
{ "script": "..." }`
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
