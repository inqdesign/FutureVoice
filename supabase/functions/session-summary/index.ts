// session-summary — the post-talk analysis, prompt held SERVER-SIDE.
//
// The first engine of the brain-lift (`docs/android-launch-roadmap.md` §1.13):
// the summary prompt from `ConversationEngine.summarySystemPrompt` +
// `CoachingLanguage.contract`, moved here VERBATIM (the text below was
// extracted from the Swift source by script, not retyped), so a client that
// has no prompt of its own — Android — gets byte-for-byte the same analysis
// iOS produces. iOS still builds this prompt client-side and calls `gemini`
// directly; it is NOT switched to this function (that is a separate, owner-
// approved step). Keep the two texts identical: when the Swift prompt
// changes, re-extract, never hand-edit.
//
// Body: { target_language, native_language, profile, known_about_user?,
//         expression_budget?, transcript, metrics, stream? }
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

const SOURCE_FN = "session-summary"
const MODEL = "gemini-3.6-flash"
const HOURLY_REQUEST_LIMIT = 120
const DAILY_CAP = 60            // = gemini's "summary" cap
const MAX_TOKENS = 8192         // see SessionSummarizer.swift for why this large

const ENGLISH_NAMES: Record<string, string> = {
  en: "English", es: "Spanish", de: "German", fr: "French", it: "Italian",
  pt: "Portuguese", ja: "Japanese", ko: "Korean", zh: "Chinese", vi: "Vietnamese",
  th: "Thai", id: "Indonesian", hi: "Hindi", ar: "Arabic", tr: "Turkish",
  ru: "Russian", pl: "Polish", nl: "Dutch",
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

/** `ConversationEngine.summarySystemPrompt`, verbatim. */
function summarySystemPrompt(opts: {
  targetLanguage: string
  nativeLanguage: string
  profile: unknown
  knownAboutUser: string[]
  expressionBudget: number
}): string {
  const languageName = englishName(opts.targetLanguage)
  const nativeName = englishName(opts.nativeLanguage)
  const contract = coachingContract(opts.targetLanguage, opts.nativeLanguage)
  const profileJSON = JSON.stringify(opts.profile ?? {})
  const knownBlock = opts.knownAboutUser.length === 0
    ? "(nothing yet)"
    : opts.knownAboutUser.map((k) => `- ${k}`).join("\n")
  const expressionBudget = opts.expressionBudget
  return `The user just finished a conversation in ${languageName}.
You will be given the full transcript with role labels.

${contract}

Their existing learner profile:
${profileJSON}

What is ALREADY on file about this person's life — never repeat any of
it in \`about_user\` below, however differently you'd word it:
${knownBlock}

You will also be given a \`metrics\` JSON object with deterministic stats
(word counts, type-token ratio, words-per-minute, suggestion rate, etc.).
Ground your scores in those numbers — do not invent.

Return STRICT JSON only — no prose, no code fences:
{
  "title": "...",
  "phrases_used": [
    { "user_said": "...", "fluent_alternative": "...", "reason": "..." }
  ],
  "new_patterns_detected": [
    { "mistake": "...", "correction": "...", "context": "...", "frequency_hint": "rare|sometimes|often" }
  ],
  "suggested_drills": ["phrase 1", "phrase 2", "phrase 3"],
  "expressions_used": ["...", "..."],
  "expressions_offered": ["...", "..."],
  "weak_vocab_areas": ["...", "..."],
  "grammar_errors": [
    { "quote": "...", "correction": "...", "note": "..." }
  ],
  "overall_note": "1-2 sentence encouraging note",
  "scorecard": {
    "vocabulary":     { "score": 0, "note": "..." },
    "grammar":        { "score": 0, "note": "..." },
    "expressiveness": { "score": 0, "note": "..." },
    "fluency":        { "score": 0, "note": "..." },
    "top_line":       "one-sentence holistic read of the session",
    "cefr_level":     "a1|a2|b1|b2|c1|c2"
  },
  "about_user": ["...", "..."]
}

OUTPUT LANGUAGE, FIELD BY FIELD (applies the contract above):
- ${languageName} — the learner reads these as material or hears them
  spoken: title, phrases_used.user_said, phrases_used.fluent_alternative,
  new_patterns_detected.mistake, new_patterns_detected.correction,
  suggested_drills, expressions_used, expressions_offered,
  grammar_errors.quote, grammar_errors.correction.
- ${nativeName} — the learner reads these to
  understand what happened: phrases_used.reason, grammar_errors.note,
  overall_note, scorecard.*.note, scorecard.top_line, about_user.
- English regardless — these two are never shown to the learner, they
  are re-injected into the next conversation's prompt and must stay
  machine-readable: weak_vocab_areas, new_patterns_detected.context.

Rules:
- The transcript is SPEECH, not writing — judge every field in this
  JSON against how fluent speakers TALK. Contractions, casual register,
  and conversational fragments ("Sounds good.", "Maybe tomorrow?") are
  natural speech, never something to report or "fix" anywhere. Every
  fluent_alternative / correction / suggested_drill must sound like a
  line said out loud in casual conversation — the user's own register,
  contractions welcome — never a written-essay rewrite.
- cefr_level: a single holistic CEFR estimate of the user's SPEAKING in
  this whole conversation, weighing vocabulary range, grammatical
  control, fluency, and how well they express ideas together. Anchor to
  the standard CEFR can-do descriptors and to the EVIDENCE in metrics:
  \`distinct_words_by_cefr_level\` (words they actually produced, graded
  objectively) and \`articulation_rate_wpm\`. A user producing many
  B2/C1 words at a fluent pace with few corrections IS above B1 — say
  so. CRITICAL: the profile's \`proficiencyLevel\` is the user's own
  SETTING, not evidence — do NOT anchor your estimate on it in either
  direction. Judge only from the transcript and metrics. Lowercase
  a1…c2.
- title: 2-5 words in ${languageName} naming what the conversation
  was actually about — "Weekend plans with Boram", "Arguing about
  coffee prices". Concrete and specific, never generic ("Conversation",
  "Practice session" are failures).
- Max 5 phrases_used. Pick the most teachable ones. Both "user_said"
  and "fluent_alternative" are ONE sentence (≤ 15 words) — quote and
  fix only the sentence containing the slip, never a whole
  multi-sentence turn. Same rule for "mistake"/"correction" in
  new_patterns_detected. These become flashcards; a paragraph on a
  flashcard is a failure.
- suggested_drills: 3-4 phrases the learner should PRACTICE NEXT to
  GROW — not more corrections of what they already said. Aim slightly
  ABOVE their current level (see proficiencyLevel in the profile):
  higher-value, natural expressions a fluent speaker would use for THIS
  topic that the learner did NOT reach for — idioms, phrasal verbs,
  collocations, connectors, more precise word choices. Skip trivial
  phrases they obviously already command. Each is a full, speakable
  sentence, and the 3-4 should be varied (not near-duplicates).
- expressions_used: up to ${expressionBudget} REUSABLE multi-word expressions the user
  ACTUALLY said this session — idioms, phrasal verbs, collocations or
  set phrases a fluent speaker would reach for in completely unrelated
  conversations (e.g. "push back", "at the end of the day", "flag it
  early", "catch up on", "end up -ing"). The test: would this exact
  phrase be useful next week on a different topic? Quote them VERBATIM
  from the user's turns — never invent or paraphrase; a paraphrase is
  dropped on arrival. Prefer the strongest ones first. Return an empty
  list only when the user genuinely produced nothing reusable (very
  short or single-word turns) — in a normal conversation there are
  usually several.
- expressions_offered: up to ${expressionBudget} REUSABLE multi-word expressions YOU (the
  fluent self) said this conversation that the user did NOT — the
  phrases worth stealing out of this exact talk. Same test as
  expressions_used (would this phrase be useful next week on a
  different topic?) and the same VERBATIM rule: quote them exactly as
  they appear in your own turns, never invent or paraphrase; a
  paraphrase is dropped on arrival. Do NOT repeat anything already in
  expressions_used, and skip conversational filler ("you know", "I
  mean", "kind of"). This is where the user's next expressions come
  from, so prefer the ones that carry real meaning — idioms, phrasal
  verbs, collocations, set phrases — over anything they clearly
  already command. Sweep the WHOLE transcript, not just its first
  exchanges: a long conversation has phrases worth stealing all the way
  through it, and stopping at two or three when you said a dozen throws
  away the only material this talk can produce.
- grammar_errors: EVERY clear grammatical error in the user's turns
  (up to 15) — articles, tense, subject-verb agreement, prepositions,
  plurals, word order, wrong verb forms. This is the EVIDENCE behind
  the grammar score: a user seeing a low score taps into this list,
  so the score and this list must tell the same story.
  - The transcript is SPEECH transcribed to text. Punctuation,
    capitalization, and spelling were produced by the transcriber,
    NOT by the user — NEVER report them as errors, here or anywhere
    in this JSON. A missing comma is a transcription artifact, not
    a grammar slip. Only report errors a listener could HEAR.
  - A missing SUBJECT PRONOUN ("I/he/she/we/they") is almost always
    the recognizer clipping a word the speaker said — English speakers
    don't drop subjects. NEVER report "missing subject" / "add 'I'" as
    a grammar error; it tanks the score for the transcriber's mistake.
    (Missing ARTICLES a/the CAN be a real learner error — keep those.)
  - Only CLEAR errors a fluent speaker would never produce. Casual
    spoken register (contractions, dropped "that", sentence
    fragments in dialogue) is normal speech, not an error.
  - quote: the user's sentence VERBATIM from the transcript (the
    clause containing the error if the turn is long). Never
    paraphrase — a quote that isn't literally in the transcript
    gets discarded.
  - correction: the same sentence with ONLY the grammar fixed. Keep
    their words and style; this is not the place for nicer phrasing
    (that's phrases_used).
  - note: the grammar point, named in ${nativeName}, as short as a
    label — the ${nativeName} equivalent of "missing article", "past
    tense needed", "preposition: 'on' → 'at'". Use the grammar words
    ${nativeName} speakers actually use, not a literal translation of
    the English term.
  - The same error type appearing in different sentences = separate
    entries. Empty array if the session was genuinely clean.
- weak_vocab_areas: 0-3 SHORT topic labels (2-4 words each, e.g.
  "cooking verbs", "phone-call phrases") where the user visibly
  lacked words this session — reached for vague fillers, circumlocuted,
  or switched to their native language. ENGLISH, always — these feed
  the next conversation's system prompt and are never displayed.
  Empty if nothing stood out.
- about_user: 0-3 things the user told you about THEIR LIFE that are
  worth still knowing in six months — what they do, who's around them,
  where they live or go, what they like and can't stand, what they're
  working toward, something that happens every week. This is the ONE
  field that isn't about their ${languageName}: it is the fluent self's
  own memory of the person, and it is read back into the next
  conversation, so write each line as a plain fact ABOUT THEM, in
  ${nativeName}, one clause, ≤ 12 words, no "the user" prefix.
  - ONLY what they actually said. Never infer, never guess from their
    level or their mistakes, never carry over something already listed
    under "already on file" above.
  - NOT what happened in this session ("practiced ordering coffee"),
    NOT their opinion of a news story, NOT anything about their
    ${languageName} — all of that lives in the other fields.
  - A passing detail that won't matter next month (what they ate today)
    is not worth a line. Empty array is the normal answer for a talk
    where they said nothing about themselves — and an empty array is
    always better than an invented fact.
  - This field is LAST on purpose: everything above it is the review
    material and must be written first.
- Tone: warm, never condescending.

HARD RULE for phrases_used / new_patterns_detected / suggested_drills
(this is the most-violated rule — read carefully):

Every "fluent_alternative", "correction", "suggested_drills" entry,
and every "mistake" / "user_said" field MUST be a CONCRETE UTTERANCE
the learner could literally say out loud in this language, NOT a
rule, category, or instruction about how to speak.

FORBIDDEN — do NOT emit cards like:
  - "missing articles or prepositions"
  - "using 'a', 'the', 'in', 'on', 'from' correctly"
  - "use the past tense"
  - "subject-verb agreement"
  - "expand your vocabulary"
These are pedagogical labels. They cannot be spoken back to the
learner as a model line, and TTS on them produces nonsense audio.

GOOD — emit cards like (the "reason" shown here is English for
illustration only; write yours in ${nativeName}):
  - user_said: "I go to bank yesterday"
    fluent_alternative: "I went to the bank yesterday"
    reason: "past tense + article"
  - user_said: "It's depend on weather"
    fluent_alternative: "It depends on the weather"
    reason: "third-person s, article on weather"

If you cannot point to a specific utterance from the transcript,
do NOT invent a generic rule — leave the array shorter. An empty
phrases_used is better than a meta-rule entry.
- Scorecard scoring rubric (each 0–100, calibrated to the user's CEFR
  level, NOT to native-speaker absolutes):
  * vocabulary: range + appropriateness. Reference type_token_ratio and
    unique_word_count. Penalize repetition.
  * grammar: anchor on YOUR grammar_errors list above — the guarded
    evidence the user actually sees — NOT on suggestion_rate.
    suggestion_rate also counts naturalness/style rephrases and
    speech-to-text artifacts (a clipped "I", a dropped article the
    recognizer ate), so scoring grammar from it punishes clean speech
    and transcription noise. Instead: start at 100 and deduct for the
    DENSITY and SEVERITY of real grammar_errors relative to how much
    the user said (user_word_count / user_turn_count). A session with
    an empty grammar_errors list is ~90-100 even if suggestion_rate is
    high (those were style nudges, not errors). Calibrate to the
    user's CEFR level, not native-speaker absolutes.
  * expressiveness: idiom use, register fit for topic, sentence-shape
    variety. Pure judgment call.
  * fluency: anchor on articulation_rate_wpm — words per minute of
    VOICED speech, pauses removed (80–140 = healthy for B1-B2). Use
    pauses_per_minute and pause_ratio as secondary evidence. Ignore
    words_per_minute (wall-clock; polluted by think-time). If
    articulation_rate_wpm is 0 fall back to words_per_minute (60–120
    healthy); if both are 0, set fluency to -1 and note "no timing
    data".
- Each axis note: ${nativeName}, ≤ 18 words (or that length's
  equivalent), concrete — cite a metric or quote a phrase. A quoted
  ${languageName} phrase stays in ${languageName} inside the
  ${nativeName} sentence.
- top_line: one warm sentence in ${nativeName} that ties the highest +
  lowest axis together.
- overall_note: 1-2 encouraging sentences in ${nativeName}.`
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

  let body: {
    target_language?: string; native_language?: string; profile?: unknown
    known_about_user?: unknown; expression_budget?: unknown
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
    knownAboutUser, expressionBudget,
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
