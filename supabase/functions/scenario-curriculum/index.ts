// scenario-curriculum — the Watch scene + its study content, prompt held
// SERVER-SIDE (brain-lift #3; `android-launch-roadmap.md` §1.13). The system
// prompt is GENERATED into `prompt.ts` from `ScenarioCurriculumEngine.swift`
// by `scripts/android/gen-scenario-prompt.py`, never retyped. iOS builds it
// client-side and calls `gemini` (purpose "scenario-curriculum"); it never
// calls this function.
//
// Body: { scenario: { environment, role?, notes?, is_topic? },
//         counterpart_lines?, cast_identity?, persona?, proficiency?,
//         target_language?,
//         weak_vocab_areas?, recurring_mistakes?, avoid_titles?,
//         common_ground?, brief?, stream? }
// Returns Gemini's own body (SSE with the X-Gemini-Stream handshake when
// `stream`) — `turns` FIRST in the schema so playback can start while the
// study tail is still being written. Purpose "scenario-curriculum".

import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { requireUser, handlePreflight, errorResponse, cors } from "../_shared/auth.ts"
import { recordFreeUsage, enforceRequestRate, rateLimitedResponse,
         recordProviderUsage, background, geminiUsageFields } from "../_shared/credits.ts"
import { SCENE_MAX_TOKENS, systemPrompt } from "./prompt.ts"

const SOURCE_FN = "scenario-curriculum"
const MODEL = "gemini-3.6-flash"
const HOURLY_REQUEST_LIMIT = 120
const DAILY_CAP = 60             // = gemini's "scenario-curriculum" cap

type Brief = {
  summary: string
  counterpart_facts: string[]
  likely_questions: string[]
  learner_facts: string[]
  key_expressions: string[]
}

type Persona = {
  city?: string; country?: string; occupation?: string; household?: string
  interests?: string[]; situations?: string[]; free_notes?: string
}

/** `ScenarioCurriculumEngine.userMessage`, the branches Android sends. */
function userMessage(opts: {
  scenario: { environment: string; role?: string; notes?: string; is_topic?: boolean }
  /** iOS's block for a real person (own, stranger or public figure):
   *  "- the other person is …" with its indented detail lines, built on the
   *  client (Android `CurriculumClient.counterpartLines`). When present it
   *  stands where iOS puts it and `castIdentity` is not used. */
  counterpartLines?: string
  castIdentity?: string
  persona?: Persona
  weakVocabAreas: string[]
  recurringMistakes: Array<{ mistake: string; correction: string }>
  avoidTitles: string[]
  /** `CommonGround.block` for this pair, computed on the client (it has both
   *  sides). Absent for a scene with no counterpart, and for iOS, which
   *  sends its whole message already assembled. */
  commonGround?: string
  /** The learner's attached material, read once on the client
   *  (`ScenarioBrief`), already sorted by side. Optional: absent for every
   *  scene without material and for older clients. */
  brief?: Brief
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
  // The learner's attached material (iOS `ScenarioCurriculumEngine.userMessage`,
  // `59c6481`). Two sides, and they must stay on their sides: the other
  // side's facts and questions belong to the counterpart, the learner's facts
  // to the USER's lines. Handing the CV to the interviewer is the failure
  // this ordering exists to prevent.
  const b = opts.brief
  if (b && (b.counterpart_facts.length || b.likely_questions.length ||
            b.learner_facts.length || b.key_expressions.length)) {
    lines.push("")
    lines.push("material the learner attached for THIS situation (read once — facts only, never invent beyond them):")
    if (b.summary) lines.push(`- about: ${b.summary}`)
    if (b.counterpart_facts.length) {
      lines.push("- the OTHER side (this is who the counterpart is and what they want):")
      b.counterpart_facts.forEach((f) => lines.push(`    · ${f}`))
    }
    if (b.likely_questions.length) {
      lines.push("- what the other side is likely to say or ask — use SOME of these, not all, and not in this order; a fresh take picks different ones:")
      b.likely_questions.forEach((q) => lines.push(`    · ${q}`))
    }
    if (b.learner_facts.length) {
      lines.push("- the LEARNER's own side (the user's lines draw on these; the counterpart may only know what such a person would plausibly have been sent):")
      b.learner_facts.forEach((f) => lines.push(`    · ${f}`))
    }
    if (b.key_expressions.length) {
      lines.push(`- expressions this situation calls for — work several into the dialogue naturally where they fit, and prefer them for the study lists: ${b.key_expressions.join(" · ")}`)
    }
    lines.push("  (the notes above may be in the learner's native language — context only, never let it change the language you write in)")
  }
  if (opts.counterpartLines?.trim()) {
    lines.push(...opts.counterpartLines.split("\n"))
  } else if (opts.castIdentity) {
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
  // The learner and the counterpart went in as two separate blocks with
  // nothing telling the model to cross them, so the scene's subject came off
  // one side at random. What two people who just met actually talk about is
  // the overlap.
  if (opts.commonGround?.trim()) {
    lines.push("")
    lines.push(opts.commonGround.trim())
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
    counterpartLines: typeof body.counterpart_lines === "string" ? body.counterpart_lines : undefined,
    castIdentity: typeof body.cast_identity === "string" ? body.cast_identity : undefined,
    persona: (body.persona ?? undefined) as Persona | undefined,
    weakVocabAreas: strs(body.weak_vocab_areas),
    recurringMistakes: Array.isArray(body.recurring_mistakes)
      ? (body.recurring_mistakes as Array<{ mistake?: string; correction?: string }>)
          .filter((m) => m?.mistake && m?.correction)
          .map((m) => ({ mistake: m.mistake!, correction: m.correction! }))
      : [],
    avoidTitles: strs(body.avoid_titles),
    commonGround: typeof body.common_ground === "string" ? body.common_ground : undefined,
    brief: (() => {
      const raw = body.brief as Record<string, unknown> | undefined
      if (!raw || typeof raw !== "object") return undefined
      return {
        summary: typeof raw.summary === "string" ? raw.summary.trim() : "",
        counterpart_facts: strs(raw.counterpart_facts).slice(0, 8),
        likely_questions: strs(raw.likely_questions).slice(0, 10),
        learner_facts: strs(raw.learner_facts).slice(0, 8),
        key_expressions: strs(raw.key_expressions).slice(0, 14),
      }
    })(),
  })

  const geminiBody = {
    system_instruction: { parts: [{ text: systemPrompt(targetLanguage, prof) }] },
    contents: [{ role: "user", parts: [{ text: message }] }],
    generationConfig: {
      maxOutputTokens: SCENE_MAX_TOKENS,
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
