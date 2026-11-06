// The per-turn correction on Claude (2026-10-21) — the gateway moved the
// call's REPLY to Claude Haiku 5.5 the same day (gateway/src/claude-reply.ts),
// and after that the app's correction call (one 3.6-flash request per learner
// turn) was the larger cost of a call. It is routed here, on the server, so
// every build already installed — iOS and Android — moves without a release.
//
// Only the correction calls move: `purpose: "turn"`, buffered, with the
// idempotency prefix the app gives exactly those ("rt-suggest:" for the live
// call, "say-again-fill:" for Say it again's rewrites). The reply pipeline
// and the TTS calls share `purpose: "turn"` but stream or carry other keys.
//
// The answer goes back in Gemini's shape (`candidates[0].content.parts`),
// which is all the app reads, so the client cannot tell. A Claude failure of
// any kind is the old Gemini request, never a failed turn.
//
// Measured with scripts/correction-probe.py (MODEL=claude-haiku-5-5, EXTRA =
// CORRECTION_ADDENDUM) on 2026-10-21: false corrections ko 0/86, ja 1/72,
// de 0/70, en 1/8 (3.6-flash: 1/86, 0/72, 0/70, 0/8); missed errors 1/84
// (3.6-flash 0/84). Without the addendum Haiku re-added dropped Japanese
// particles and Korean subjects (7/236). Re-run the probe before touching it.

export const CORRECTION_ADDENDUM = `

BEFORE YOU ANSWER — what is and is not a mistake in speech:
- Dropped words are NOT mistakes. Casual speech leaves out what the context makes clear: particles (Japanese を・に・が・は, Korean 을/를·이/가·에·은/는), subjects, objects. Never add one back, and never list its absence as a fix.
- Word order that is one of several natural orders is NOT a mistake. Change the order only when the sentence is ungrammatical as said (a German verb not at the end of a dass/weil clause, for example).
- A word that IS there but wrong IS a mistake, and always gets its own entry in "fixes": a wrong particle (not a missing one), a wrong ending or conjugation, a wrong tense, a wrong connector between clauses. If your "alternative" changes any of these, the change must also appear in "fixes".

Answer with the JSON object only.`

/** Appended on Claude to a JSON purpose that has no addendum of its own:
 *  Gemini was asked for JSON at the API level, Claude is asked here. */
const JSON_ONLY = `

Answer with the JSON object only.`

const CORRECTION_KEY_PREFIXES = ["rt-suggest:", "say-again-fill:"]

/** Unset/"off" = nobody, "all" = everyone, else comma-separated user ids —
 *  the gateway's CLAUDE_REPLY shape, so it can ride one account first. */
export function onForUser(setting: string | undefined, userId: string): boolean {
  const v = (setting ?? "").trim().toLowerCase()
  if (!v || v === "off") return false
  if (v === "all") return true
  return v.split(",").map((x) => x.trim()).includes(userId.toLowerCase())
}

type GeminiPart = { text?: string; inlineData?: unknown }
type GeminiBody = {
  system_instruction?: { parts?: GeminiPart[] }
  systemInstruction?: { parts?: GeminiPart[] }
  contents?: { role?: string; parts?: GeminiPart[] }[]
  generationConfig?: { maxOutputTokens?: number }
  tools?: unknown
}

/** Is this request a correction Claude can answer? Text only, no tools. */
export function isCorrectionRequest(purpose: string | undefined, stream: boolean,
                                    idemKey: string, body: GeminiBody): boolean {
  if (purpose !== "turn" || stream) return false
  if (!CORRECTION_KEY_PREFIXES.some((p) => idemKey.startsWith(p))) return false
  if (body.tools) return false
  return (body.contents ?? []).every((c) => (c.parts ?? []).every((p) => p.inlineData === undefined))
}

export interface ClaudeAnswer {
  /** Gemini-shaped response body, ready to hand to the app. */
  json: string
  usage: Record<string, number>
}

/** One buffered correction on Claude, or null when it could not answer (the
 *  caller then makes the Gemini request it was going to make anyway). */
export function claudeCorrection(apiKey: string, model: string,
                                 body: GeminiBody): Promise<ClaudeAnswer | null> {
  return claudeAnswer(apiKey, model, body, CORRECTION_ADDENDUM)
}

/** Purposes the `CLAUDE_PURPOSES` secret moves to Claude (2026-10-21), each
 *  measured first against 3.6-flash on its live prompt:
 *  - coach (scripts/coach-probe.py): blind judge preferred Haiku 131/160 vs
 *    26, no format failures in 5 languages; ~3 s vs ~1.3 s, which the fluent
 *    self's own line covers. Only its 3.6-flash call moves (the two
 *    flash-lite coach calls were not measured).
 *  A purpose may only be listed here after its probe. */
export const CLAUDE_PURPOSE_ADDENDA: Record<string, string> = {
  coach: JSON_ONLY,
  // The tutor bot's chat ({reply, action}), founder's call 2026-10-28:
  // everything but the live call moves to Haiku. ~1/8 the cost per question.
  "tutor-bot": JSON_ONLY,
  "tutor-judge": JSON_ONLY,
  "tutor-next": JSON_ONLY,
  "tutor-check": JSON_ONLY,
}

/** A move named by the request's idempotency-key prefix, for a purpose that
 *  other, unmeasured calls share ("tutor" is also the planner, the next-step
 *  read and the final check). Both apps send these prefixes. */
const KEYED_MOVES: { name: string; purpose: string; keyPrefix: string; model: string }[] = [
  // TutorJudge.read (2026-11-06, scripts/tutor-lesson-probe.py
  // JUDGE_MODEL=haiku, 35 lines × 3 in five languages): Haiku with thinking
  // off 105/105, flash-lite 102/105 (a bare "Ingeniero." read as done every
  // time). Median 0.94 s vs 0.70 s.
  { name: "tutor-judge", purpose: "tutor", keyPrefix: "tutor-judge:", model: "gemini-3.1-flash-lite" },
  // TutorNext.read and TutorFinalCheck.read (scripts/tutor-calls-probe.py,
  // five languages × 3 runs, thinking off): next 116/120 vs flash-lite
  // 120/120, every miss "unclear" (the tutor asks again); check 90/90 on
  // both, median 1.00 s vs 1.06 s. The planner ("tutor-plan:") stays on
  // Gemini: without thinking Haiku wrote the German examples in English
  // (24/24), with it the plan took 4–6 s against 1.7 s.
  { name: "tutor-next", purpose: "tutor", keyPrefix: "tutor-next:", model: "gemini-3.1-flash-lite" },
  { name: "tutor-check", purpose: "tutor", keyPrefix: "tutor-check:", model: "gemini-3.6-flash" },
]

/** Calls asked with Claude's thinking OFF. Haiku 5.5 thinks by default, and
 *  on the judge that spent the app's 160-token ceiling before any JSON
 *  (an empty answer, 22/105), and with room to think it passed one-word
 *  answers as done (96/105). */
const NO_THINKING = new Set(["tutor-judge", "tutor-next", "tutor-check"])

/** How long a moved call waits on Claude before the Gemini fallthrough. The
 *  judge is on the tutor's reply path and the app gives up at 10 s, so a
 *  stalled Claude must leave time for Gemini (0.7 s median). */
const CLAUDE_TIMEOUT_MS: Record<string, number> = {
  "tutor-judge": 4_000,
  "tutor-next": 4_000,   // the app gives up at 10 s
  "tutor-check": 6_000,  // the app gives up at 15 s
}

/** The name `CLAUDE_PURPOSES` lists a request under: its keyed move, else
 *  its purpose. */
export function claudeMoveName(purpose: string | undefined, idemKey: string): string | undefined {
  return KEYED_MOVES.find((m) => m.purpose === purpose && idemKey.startsWith(m.keyPrefix))?.name ?? purpose
}

/** A buffered request a listed purpose can move: not streamed, no tools, no
 *  audio or files, and asking for the model it was measured against. */
export function isMovableRequest(name: string | undefined, model: string, stream: boolean,
                                 body: GeminiBody): boolean {
  if (!name || !(name in CLAUDE_PURPOSE_ADDENDA)) return false
  const measured = KEYED_MOVES.find((m) => m.name === name)?.model ?? "gemini-3.6-flash"
  if (stream || model !== measured || body.tools) return false
  return (body.contents ?? []).every((c) => (c.parts ?? []).every((p) => p.inlineData === undefined))
}

export function claudePurpose(apiKey: string, model: string, name: string,
                              body: GeminiBody): Promise<ClaudeAnswer | null> {
  return claudeAnswer(apiKey, model, body, CLAUDE_PURPOSE_ADDENDA[name] ?? JSON_ONLY, NO_THINKING.has(name),
                      CLAUDE_TIMEOUT_MS[name])
}

async function claudeAnswer(apiKey: string, model: string, body: GeminiBody,
                            addendum: string, noThinking = false,
                            timeoutMs = 12_000): Promise<ClaudeAnswer | null> {
  const system = (body.system_instruction ?? body.systemInstruction)?.parts
    ?.map((p) => p.text ?? "").join("") ?? ""
  const messages: { role: "user" | "assistant"; content: string }[] = []
  for (const c of body.contents ?? []) {
    const role = c.role === "model" ? "assistant" : "user"
    const text = (c.parts ?? []).map((p) => p.text ?? "").join("")
    const prev = messages[messages.length - 1]
    if (prev && prev.role === role) prev.content += `\n${text}`
    else messages.push({ role, content: text })
  }
  if (messages.length === 0 || messages[0].role !== "user") return null

  try {
    const resp = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-api-key": apiKey,
        "anthropic-version": "2023-06-01",
      },
      body: JSON.stringify({
        model,
        max_tokens: body.generationConfig?.maxOutputTokens ?? 2048,
        // The prompt is the same for every turn of a call (language, level,
        // register), so it is cached: a read is a tenth of the input price.
        system: [{ type: "text", text: system + addendum, cache_control: { type: "ephemeral" } }],
        messages,
        ...(noThinking ? { thinking: { type: "disabled" } } : {}),
      }),
      signal: AbortSignal.timeout(timeoutMs),
    })
    if (!resp.ok) {
      console.warn(`claude correction ${resp.status}: ${(await resp.text()).slice(0, 200)}`)
      return null
    }
    const j = await resp.json()
    const raw = (j.content ?? []).map((b: { text?: string }) => b.text ?? "").join("")
    // The app asked Gemini for JSON at the API level; here it is asked in the
    // prompt, so a stray sentence or a code fence around it is cut away.
    const start = raw.indexOf("{"), end = raw.lastIndexOf("}")
    if (start < 0 || end <= start) {
      console.warn(`claude correction: no JSON in "${raw.slice(0, 120)}"`)
      return null
    }
    const text = raw.slice(start, end + 1)
    try { JSON.parse(text) } catch {
      console.warn(`claude correction: unparseable JSON "${text.slice(0, 120)}"`)
      return null
    }
    const u = j.usage ?? {}
    const input = (u.input_tokens ?? 0) + (u.cache_creation_input_tokens ?? 0)
    const cached = u.cache_read_input_tokens ?? 0
    const output = u.output_tokens ?? 0
    return {
      json: JSON.stringify({
        candidates: [{
          content: { role: "model", parts: [{ text }] },
          finishReason: j.stop_reason === "max_tokens" ? "MAX_TOKENS" : "STOP",
        }],
      }),
      usage: {
        prompt_tokens: input,
        ...(cached > 0 ? { cached_input_tokens: cached } : {}),
        output_tokens: output,
        total_tokens: input + cached + output,
      },
    }
  } catch (e) {
    console.warn(`claude correction failed: ${String(e).slice(0, 160)}`)
    return null
  }
}
