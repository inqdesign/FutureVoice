// "Study" notes for a speech CHALLENGE — cache-or-generate, shared by every
// learner (2026-10-15).
//
// Body: { challenge_id, native, level }
// Returns: { highlights: [{text, kind, lemma?, note, example?}],
//            paragraph_notes: [string], shared: boolean }
// — the model's raw answer. Each app places the spans itself
// (`ScriptStudy.locate`), exactly as it does for a study made on the phone.
//
// A challenge is the same text for everyone learning its language, so the
// notes for one (native language, level) pair are the same for all of them.
// Until now each phone made its own copy. A learner's OWN script never comes
// here: it is private and nobody else would read the notes.
//
// Why the prompt lives here and the text is read from the database, never
// taken from the request: the result is served to every learner, so the
// caller must not be able to put anything into it but its native-language
// code and level — both checked against fixed lists. Same reasoning as
// `word-entry`.
//
// KEEP THE PROMPT IN STEP with `ScriptStudyEngine.generate`
// (FutureVoice/Services/Speech/ScriptStudy.swift) and `PROMPT_VERSION` with
// `ScriptStudy.promptVersion`. A learner's own scripts still use the app's copy.

import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { requireUser, handlePreflight, errorResponse, cors } from "../_shared/auth.ts"
import {
  serviceRoleClient, recordFreeUsage, recordProviderUsage, geminiUsageFields, background,
} from "../_shared/credits.ts"

const MODEL = "gemini-3.6-flash"
const PROMPT_VERSION = 2
// New studies per learner per hour. A learner opens one challenge at a time;
// cache hits are unlimited.
const MAX_NEW_PER_HOUR = 20

const LEVELS = new Set(["a1", "a2", "b1", "b2", "c1", "c2"])

// `LanguageCatalog.nativeLanguages` — the only codes a learner can pick.
const NATIVE_LANGUAGES = new Set([
  "ko", "ja", "zh-Hant", "zh-Hans", "vi", "th", "id", "ms", "fil", "km", "my", "lo", "mn",
  "hi", "bn", "ur", "ta", "te", "mr", "gu", "kn", "ml", "pa", "ne", "si",
  "ar", "fa", "tr", "he", "kk", "uz", "az", "ka", "hy", "ps",
  "en", "es", "pt", "fr", "de", "it", "ru", "pl", "uk", "nl", "ro", "el", "cs",
  "hu", "sv", "da", "fi", "no", "sk", "bg", "hr", "sr", "lt", "lv", "et",
  "sl", "ca",
  "sw", "am", "af", "ha", "yo", "zu",
])

Deno.serve(async (req) => {
  const pre = handlePreflight(req)
  if (pre) return pre
  if (req.method !== "POST") return errorResponse(405, "method not allowed")

  const authed = await requireUser(req)
  if (authed instanceof Response) return authed
  const { user } = authed

  let body: { challenge_id?: string; native?: string; level?: string }
  try { body = await req.json() } catch { return errorResponse(400, "invalid json body") }
  const challengeId = (body.challenge_id ?? "").trim()
  const native = (body.native ?? "").trim()
  const level = (body.level ?? "").trim().toLowerCase()
  if (!/^[0-9a-f-]{36}$/i.test(challengeId)) return errorResponse(400, "challenge_id required")
  if (!NATIVE_LANGUAGES.has(native)) return errorResponse(400, "unknown native language")
  if (!LEVELS.has(level)) return errorResponse(400, "unknown level")

  const svc = serviceRoleClient()

  const { data: challenge, error: chErr } = await svc
    .from("speech_challenges")
    .select("body, language")
    .eq("id", challengeId).eq("is_active", true)
    .maybeSingle()
  if (chErr) return errorResponse(500, "challenge read failed", chErr.message)
  if (!challenge) return errorResponse(404, "no such challenge")

  const text = (challenge.body as string).trim()
  const bodyHash = await sha256(text)
  const key = {
    challenge_id: challengeId, body_hash: bodyHash, native, level, prompt_version: PROMPT_VERSION,
  }

  // 1. Shared cache.
  {
    const { data, error } = await svc
      .from("speech_challenge_study").select("payload").match(key).maybeSingle()
    if (error) return errorResponse(500, "cache read failed", error.message)
    if (data) return json({ ...(data.payload as object), shared: true })
  }

  // 2. Bound NEW generations per learner.
  {
    const since = new Date(Date.now() - 60 * 60 * 1000).toISOString()
    const { count, error } = await svc
      .from("speech_challenge_study")
      .select("challenge_id", { count: "exact", head: true })
      .eq("created_by", user.id).gte("created_at", since)
    if (error) return errorResponse(500, "rate check failed", error.message)
    if ((count ?? 0) >= MAX_NEW_PER_HOUR) return errorResponse(429, "too many new studies this hour")
  }

  const apiKey = Deno.env.get("GEMINI_API_KEY")
  if (!apiKey) return errorResponse(500, "server missing GEMINI_API_KEY")

  const target = challenge.language as string
  const paragraphs = splitParagraphs(text)
  if (paragraphs.length === 0) return errorResponse(422, "empty script")

  let { payload, usage } = await generate(paragraphs, target, native, level, apiKey)
  if (usage) record(usage)
  // A translation that slips a word of ANOTHER language into a non-Latin
  // script (measured on the first row: "sprechen할 수 있는" in a Korean
  // translation of an English script) is one learner's annoyance on a phone
  // and everyone's in a shared row. One retry; a second slip is served to
  // this learner and not cached.
  let cacheable = payload != null && !strayWords(payload, text)
  if (payload && !cacheable) {
    console.warn("script-study: stray word in a translation, retrying", challengeId, native, level)
    ;({ payload, usage } = await generate(paragraphs, target, native, level, apiKey))
    if (usage) record(usage)
    cacheable = payload != null && !strayWords(payload, text)
  }
  if (!payload) return errorResponse(502, "generation failed")

  // Only what can be checked here is checked: a highlight must occur in the
  // script (the app's `locate` places it, but a span that isn't there at all
  // has no business in a shared row), and the notes are trimmed to the
  // paragraph count.
  const lower = text.toLowerCase()
  const highlights = (Array.isArray(payload.highlights) ? payload.highlights : [])
    .filter((h: Record<string, unknown>) =>
      typeof h?.text === "string" && h.text.trim() !== "" && lower.includes(h.text.trim().toLowerCase()))
    .slice(0, 12)
  const notes = (Array.isArray(payload.paragraph_notes) ? payload.paragraph_notes : [])
    .map((n: unknown) => typeof n === "string" ? n.trim() : "")
    .slice(0, paragraphs.length)
  const clean = { highlights, paragraph_notes: notes }
  if (highlights.length === 0 && !notes.some((n: string) => n !== "")) {
    return errorResponse(502, "empty study")
  }

  if (!cacheable) return json({ ...clean, shared: false })

  const { error: upErr } = await svc
    .from("speech_challenge_study")
    .upsert({ ...key, payload: clean, created_by: user.id },
            { onConflict: "challenge_id,body_hash,native,level,prompt_version", ignoreDuplicates: true })
  if (upErr) console.error("speech_challenge_study upsert failed (non-fatal)", upErr.message)

  return json({ ...clean, shared: false })

  function record(usage: Record<string, number>) {
    const idempotencyKey = `script-study:${crypto.randomUUID()}`
    background(recordFreeUsage({
      supabase: svc, userId: user.id, action: "gemini", purpose: "script-study",
      dailyCap: 1_000_000, sourceFn: "script-study", idempotencyKey,
      metadata: { model: MODEL, purpose: "script-study", challenge_id: challengeId, native, level, shared: true },
    }).then(() => recordProviderUsage({ idempotencyKey, usage })))
  }
})

/**
 * True when a paragraph translation written mostly in a non-Latin script
 * carries a Latin word (4+ letters) that is not in the script itself — a
 * name or term kept from the original is fine, a word from a third language
 * is not. Translations into a Latin-script language can't be checked this way.
 */
function strayWords(payload: Record<string, unknown>, script: string): boolean {
  const body = script.toLowerCase()
  const notes = Array.isArray(payload.paragraph_notes) ? payload.paragraph_notes : []
  for (const n of notes) {
    if (typeof n !== "string") continue
    const letters = [...n].filter((c) => /\p{L}/u.test(c))
    if (letters.length === 0) continue
    const latin = letters.filter((c) => /\p{Script=Latin}/u.test(c)).length
    if (latin / letters.length >= 0.5) continue
    for (const w of n.match(/\p{Script=Latin}{4,}/gu) ?? []) {
      if (!body.includes(w.toLowerCase())) return true
    }
  }
  return false
}

/** `ScriptStudy.paragraphs`: one per non-empty line, spaces trimmed. */
function splitParagraphs(body: string): string[] {
  return body.split("\n").map((l) => l.replace(/^[ \t]+|[ \t]+$/g, "")).filter((l) => l !== "")
}

function languageName(code: string): string {
  const base = code.split("-")[0]
  if (base === "zh" && code.includes("Hant")) return "Traditional Chinese"
  if (base === "zh" && code.includes("Hans")) return "Simplified Chinese"
  try {
    return new Intl.DisplayNames(["en"], { type: "language" }).of(base) ?? code.toUpperCase()
  } catch {
    return code.toUpperCase()
  }
}

/** `CoachingLanguage.contract`. */
function contract(targetName: string, nativeName: string): string {
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

/** `ScriptStudyEngine.generate`'s system prompt. */
function systemPrompt(target: string, native: string, level: string): string {
  const t = languageName(target)
  const n = languageName(native)
  const same = target.split("-")[0] === native.split("-")[0]
  const paragraphRule = same
    ? `PARAGRAPH NOTES — return an empty list: the learner reads ${t} natively.`
    : `PARAGRAPH NOTES — exactly one per numbered paragraph, in order: that
paragraph TRANSLATED into ${n}. The whole paragraph, every
sentence, faithful to its meaning and tone, written the way a native
${n} speaker would say it — not word for word, not a summary,
nothing added or left out.`
  return `You are a language teacher preparing a script for a learner
(${level.toUpperCase()}) who will read it aloud in ${t}.
Output STRICT JSON only — no prose, no code fences:
{ "highlights": [ { "text": "...", "kind": "expression|grammar|word",
    "lemma": "...", "note": "...", "example": "..." } ],
  "paragraph_notes": ["...", "..."] }

${contract(t, n)}
HIGHLIGHTS — 7 or 8 in total, the ones most worth learning for THIS
learner: a little above their level, reusable outside this script.
Spread them over the paragraphs. Mostly expressions (fixed phrases,
phrasal verbs, collocations), then grammar patterns (a structure
like "only to", "tends to"), then single words.
- "text": copied EXACTLY from the script — same spelling, same case,
  one contiguous stretch, never rewritten, never a whole sentence.
  A grammar pattern is the few words that carry it.
- "kind": "expression", "grammar" or "word".
- "lemma": for a word, its dictionary form in ${t}; else omit.
- "note": ${n}. One or two short sentences: what it means and
  what it does HERE. For grammar, the pattern and when it is used.
- "example": ${t}. One new short sentence using it, not from the
  script. Omit when you have none.

${paragraphRule}`
}

async function generate(
  paragraphs: string[], target: string, native: string, level: string, apiKey: string,
): Promise<{ payload: Record<string, unknown> | null; usage: Record<string, number> | null }> {
  const user = `SCRIPT (${paragraphs.length} paragraphs):\n` +
    paragraphs.map((p, i) => `${i + 1}. ${p}`).join("\n")
  try {
    const upstream = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent?key=${apiKey}`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          system_instruction: { parts: [{ text: systemPrompt(target, native, level) }] },
          contents: [{ role: "user", parts: [{ text: user }] }],
          generationConfig: {
            maxOutputTokens: 8192,
            thinkingConfig: { thinkingLevel: "low" },
            responseMimeType: "application/json",
          },
        }),
      },
    )
    if (!upstream.ok) {
      console.error("gemini upstream error", upstream.status, (await upstream.text()).slice(0, 300))
      return { payload: null, usage: null }
    }
    const res = await upstream.json()
    const usage = geminiUsageFields(res?.usageMetadata)
    const out: string = res?.candidates?.[0]?.content?.parts
      ?.map((p: { text?: string }) => p.text ?? "").join("") ?? ""
    const start = out.indexOf("{"), end = out.lastIndexOf("}")
    if (start < 0 || end < start) return { payload: null, usage }
    try {
      return { payload: JSON.parse(out.slice(start, end + 1)), usage }
    } catch {
      return { payload: null, usage }
    }
  } catch (e) {
    console.error("script-study generate failed", e)
    return { payload: null, usage: null }
  }
}

async function sha256(s: string): Promise<string> {
  const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s))
  return Array.from(new Uint8Array(buf)).map((b) => b.toString(16).padStart(2, "0")).join("")
}

function json(payload: unknown, status = 200): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { "Content-Type": "application/json", ...cors() },
  })
}
