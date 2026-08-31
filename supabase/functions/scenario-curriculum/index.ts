// scenario-curriculum — the Watch scene + its study content, prompt held
// SERVER-SIDE (brain-lift #3; `android-launch-roadmap.md` §1.13). The system
// prompt was EXTRACTED from `ScenarioCurriculumEngine.swift` by script, never
// retyped; iOS still builds it client-side and calls `gemini` until switched.
//
// Body: { scenario: { environment, role?, notes?, is_topic? },
//         cast_identity?, persona?, proficiency?, target_language?,
//         weak_vocab_areas?, recurring_mistakes?, avoid_titles?, stream? }
// Returns Gemini's own body (SSE with the X-Gemini-Stream handshake when
// `stream`) — `turns` FIRST in the schema so playback can start while the
// study tail is still being written. Purpose "scenario-curriculum".

import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { requireUser, handlePreflight, errorResponse, cors } from "../_shared/auth.ts"
import { recordFreeUsage, enforceRequestRate, rateLimitedResponse,
         recordProviderUsage, background, geminiUsageFields } from "../_shared/credits.ts"

const SOURCE_FN = "scenario-curriculum"
const MODEL = "gemini-3.6-flash"
const HOURLY_REQUEST_LIMIT = 120
const DAILY_CAP = 60             // = gemini's "scenario-curriculum" cap

const ENGLISH_NAMES: Record<string, string> = {
  en: "English", es: "Spanish", de: "German", fr: "French", it: "Italian",
  pt: "Portuguese", ja: "Japanese", ko: "Korean", zh: "Chinese",
}

/** `ScenarioCurriculumEngine.sceneScale` — size follows the learner's level. */
function sceneScale(prof: string): { turnRange: string; turnStyle: string; maxTokens: number } {
  if (prof === "A1" || prof === "A2") return {
    turnRange: "8 to 10",
    turnStyle: "Each turn is ONE short, simple sentence (roughly 5–10 words) —\nclear everyday phrasing the learner can fully own.",
    maxTokens: 2200,
  }
  if (prof === "C1" || prof === "C2") return {
    turnRange: "10 to 14",
    turnStyle: "Each turn is 1–3 full sentences at natural native pacing —\nsubordinate clauses, nuance, and follow-up questions welcome.\nGo deeper into the substance of the situation; an advanced\nlearner should hear a conversation with real depth.",
    maxTokens: 3600,
  }
  return {
    turnRange: "8 to 12",
    turnStyle: "Each turn is 1–2 sentences, as long as the moment naturally\ncalls for — never padded, never artificially clipped.",
    maxTokens: 2800,
  }
}

function systemPrompt(targetLanguage: string, prof: string): string {
  const languageName = ENGLISH_NAMES[targetLanguage] ?? targetLanguage.toUpperCase()
  const scale = sceneScale(prof)
  return `You are a ${languageName} curriculum designer. Given ONE real-life
scenario a learner (CEFR ${prof}) wants to master, write the SCENE
for it: a naturalistic dialogue between the learner ("user") and the
other person ("counterpart"), then extract the study content FROM that
dialogue. The dialogue is the whole course — the learner watches it,
studies its words and expressions, and shadows their own lines.

WHOSE SITUATION IT IS — settle this before you write a line. The
scenario is the learner's own, in the learner's own words, about the
learner's own life. Whatever it names being done — thanking someone,
apologizing, asking for a raise, sending a dish back, breaking news to
a friend — the LEARNER ("user") is the one doing it, and the
counterpart is the person on the OTHER side of it. Never cast the
counterpart as the one performing the learner's move, and never swap
the two: in "thanking the beta testers" the user thanks and the
counterpart is thanked, not the reverse.

Content rules:
- turns: ${scale.turnRange}, alternating naturally. WHOEVER'S MOVE THE
  SCENARIO NAMES OPENS IT — when the learner is the one going in to do
  something, the FIRST turn is "user". The counterpart opens only when
  the situation is something that happens TO the learner (called in by
  the doctor, served at a counter, stopped by an official). When
  neither side owns the move (a catch-up, talking a story through),
  either may open.
  Real spoken ${languageName} — contractions, hedges, natural register.
  ${scale.turnStyle}
  The USER speaks as a confident, fluent version of the learner
  (slightly above ${prof}, never textbook-stiff). Every user turn must
  be a complete, speakable line — it will be shadowed ALOUD. No stage
  directions, brackets, or placeholders anywhere.
- words: 8 single words or short compounds that APPEAR in the dialogue
  and a ${prof} learner plausibly doesn't own yet. No filler like
  "hello" / "thanks". note = one short cue for when it comes up.
  example = the dialogue sentence that uses it (or a tight variant).
- expressions: 6 multi-word chunks (2–6 words) that APPEAR VERBATIM in
  the dialogue — collocations, softeners, transactional moves natives
  actually use here. note = one short cue for when to reach for it.
  example = the dialogue sentence that uses it.
- title: 2–5 words in ${languageName} naming what happens in THIS scene.
- Everything specific to THIS scenario and persona — never generic
  textbook content. All content in ${languageName}; notes in simple ${languageName}.

Return STRICT JSON only — no prose, no code fences:
{
  "turns": [ { "speaker": "user" | "counterpart", "text": "..." } ],
  "title": "...",
  "words": [ { "text": "...", "note": "...", "example": "..." } ],
  "expressions": [ { "text": "...", "note": "...", "example": "..." } ]
}

FIELD ORDER IS FIXED, and "turns" comes FIRST for a reason: playback
starts on the first turn the moment it closes, while you are still
writing the rest. Every character emitted before it — a title, a
preamble, anything — is silence the learner sits through. Write the
scene first and name it afterwards.`
}

type Persona = {
  city?: string; country?: string; occupation?: string; household?: string
  interests?: string[]; situations?: string[]; free_notes?: string
}

/** `ScenarioCurriculumEngine.userMessage`, the branches Android sends. */
function userMessage(opts: {
  scenario: { environment: string; role?: string; notes?: string; is_topic?: boolean }
  castIdentity?: string
  persona?: Persona
  weakVocabAreas: string[]
  recurringMistakes: Array<{ mistake: string; correction: string }>
  avoidTitles: string[]
}): string {
  const { scenario } = opts
  const lines: string[] = []
  if (scenario.is_topic === true) {
    lines.push("scenario: a casual conversation about a topic the learner follows")
    lines.push(`- topic: ${scenario.environment}`)
    lines.push(`- talking with: ${scenario.role ?? ""}`)
    if (scenario.notes?.trim()) {
      lines.push(`- story context (facts from coverage — keep the dialogue consistent with these): ${scenario.notes}`)
    }
  } else {
    lines.push("scenario:")
    lines.push(`- what the learner is going in to do (their own words): ${scenario.environment}`)
    const role = (scenario.role ?? "").trim()
    lines.push(role === ""
      ? "- talking to: infer the natural counterpart — the person on the OTHER side of what the learner is doing, never the one doing it"
      : `- talking to: ${role} — the other side of what the learner is doing, never the one doing it`)
    if (scenario.notes?.trim()) lines.push(`- context: ${scenario.notes}`)
  }
  if (opts.castIdentity) {
    lines.push(`- who PLAYS that counterpart: ${opts.castIdentity}. `
      + "Use this name and temperament; their role, job and knowledge come from the situation above.")
  }
  const p = opts.persona
  const minimallyComplete = p && (p.occupation || p.household ||
    (p.interests?.length ?? 0) > 0 || (p.situations?.length ?? 0) > 0)
  if (p && minimallyComplete) {
    lines.push("")
    lines.push("learner:")
    const place = [p.city, p.country].filter(Boolean).join(", ")
    if (place) lines.push(`- lives in: ${place}`)
    if (p.occupation) lines.push(`- work: ${p.occupation}`)
    if (p.household) lines.push(`- household: ${p.household}`)
    if (p.interests?.length) lines.push(`- interests: ${p.interests.join(", ")}`)
    if (p.situations?.length) lines.push(`- needs the language most for: ${p.situations.join(", ")}`)
    if (p.free_notes) lines.push(`- notes: ${p.free_notes}`)
  }
  const weak = opts.weakVocabAreas.filter((w) => w.trim() !== "")
  const mistakes = opts.recurringMistakes.slice(0, 3).map((m) => `${m.mistake} → ${m.correction}`)
  if (weak.length > 0 || mistakes.length > 0) {
    lines.push("")
    lines.push("learner focus (bias study picks here where the scene allows, never force it):")
    if (weak.length > 0) lines.push(`- weak vocab areas: ${weak.join(", ")}`)
    if (mistakes.length > 0) lines.push(`- recurring mistakes: ${mistakes.join("; ")}`)
  }
  const previous = opts.avoidTitles.filter((t) => t.trim() !== "")
  if (previous.length > 0) {
    lines.push("")
    lines.push(`The learner has already watched these takes of this scenario: ${previous.map((t) => `"${t}"`).join(", ")}. Write a FRESH take — a different opening, complication, or beat of the same situation, never a rephrase of a previous take.`)
  }
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

  let body: Record<string, unknown>
  try { body = await req.json() } catch { return errorResponse(400, "invalid json body") }
  const scenario = body.scenario as { environment?: string } | undefined
  if (!scenario?.environment || typeof scenario.environment !== "string") {
    return errorResponse(400, "missing scenario.environment")
  }
  const targetLanguage = typeof body.target_language === "string" ? body.target_language : "en"
  const prof = (typeof body.proficiency === "string" ? body.proficiency : "b1").toUpperCase()
  const stream = body.stream === true

  const rec = await recordFreeUsage({
    supabase, userId: user.id, action: "gemini", purpose: "scenario-curriculum",
    dailyCap: DAILY_CAP, sourceFn: SOURCE_FN, idempotencyKey: idemKey,
    metadata: { model: MODEL, purpose: "scenario-curriculum", client: SOURCE_FN },
  })
  if (!rec.ok) {
    if (rec.reason === "rate_limited") return rateLimitedResponse(cors())
    return errorResponse(500, "usage record failed", rec.detail)
  }

  const strs = (v: unknown) => Array.isArray(v)
    ? (v as unknown[]).filter((x): x is string => typeof x === "string") : []
  const message = userMessage({
    scenario: scenario as { environment: string; role?: string; notes?: string; is_topic?: boolean },
    castIdentity: typeof body.cast_identity === "string" ? body.cast_identity : undefined,
    persona: (body.persona ?? undefined) as Persona | undefined,
    weakVocabAreas: strs(body.weak_vocab_areas),
    recurringMistakes: Array.isArray(body.recurring_mistakes)
      ? (body.recurring_mistakes as Array<{ mistake?: string; correction?: string }>)
          .filter((m) => m?.mistake && m?.correction)
          .map((m) => ({ mistake: m.mistake!, correction: m.correction! }))
      : [],
    avoidTitles: strs(body.avoid_titles),
  })

  const geminiBody = {
    system_instruction: { parts: [{ text: systemPrompt(targetLanguage, prof) }] },
    contents: [{ role: "user", parts: [{ text: message }] }],
    generationConfig: {
      maxOutputTokens: sceneScale(prof).maxTokens,
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
      headers: { "Content-Type": "text/event-stream", "Cache-Control": "no-cache",
        "X-Gemini-Stream": "sse", ...cors() },
    })
  }
  const text = await upstream.text()
  try {
    const usage = geminiUsageFields(JSON.parse(text)?.usageMetadata)
    if (usage) background(recordProviderUsage({ idempotencyKey: idemKey, usage }))
  } catch { /* unparseable body is the client's problem */ }
  return new Response(text, { status: 200, headers: { "Content-Type": "application/json", ...cors() } })
})

// Copy of gemini/index.ts's meterStream (that file is iOS-called; not edited).
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
        } catch { /* partial event */ }
      }
    }
  } catch (e) {
    console.error("meterStream read failed", e)
  } finally {
    try { reader.releaseLock() } catch { /* released */ }
  }
  const usage = geminiUsageFields(last)
  if (usage) await recordProviderUsage({ idempotencyKey, usage })
}
