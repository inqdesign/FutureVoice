// Add a word or expression to the SHARED library of a target language.
//
// Body: { text, kind: "word" | "expression", target_lang, native_lang }
// Returns (200):
//   { status: "ok", term, level, existed }        — in the library now
//   { status: "typo", suggestion }                — misspelt; nothing added
//   { status: "rejected", reason }                — not a term; nothing added
//     reason: not_real | proper_name | not_target | wrong_kind | offensive
//
// One library for every learner of a language (20261022140000_shared_library):
// whatever passes here is a row every learner of that language gets, with a
// CEFR level. So nothing goes in unread. One model call reads what was typed
// and answers whether it is a real, standard term of the language, spelled
// right, and not a name; the TERM is stored as its dictionary form. Refusals
// are cached by what was typed, so the same typo is never paid for twice.
//
// The level is the TERM's, never the learner's: the model is not told who
// asked (told the learner's level, a rating drifts toward it — measured on
// the quick quiz's rater, 2026-10-21).

import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { requireUser, handlePreflight, errorResponse, cors } from "../_shared/auth.ts"
import {
  serviceRoleClient, recordFreeUsage, recordProviderUsage, geminiUsageFields, background,
} from "../_shared/credits.ts"

type Kind = "word" | "expression"
const MAX_LEN: Record<Kind, number> = { word: 40, expression: 80 }
// New terms read per learner per day (hits on the library or on a cached
// refusal are free). A learner building a notebook adds a few a day.
const MAX_NEW_PER_DAY = 80
const MODEL = "gemini-3.6-flash"
const LEVELS = new Set(["a1", "a2", "b1", "b2", "c1", "c2"])
const REASONS = new Set(["not_real", "proper_name", "not_target", "wrong_kind", "offensive"])

Deno.serve(async (req) => {
  const pre = handlePreflight(req)
  if (pre) return pre
  if (req.method !== "POST") return errorResponse(405, "method not allowed")

  const authed = await requireUser(req)
  if (authed instanceof Response) return authed
  const { user } = authed

  let body: { text?: string; kind?: string; target_lang?: string; native_lang?: string }
  try { body = await req.json() } catch { return errorResponse(400, "invalid json body") }

  const text = (body.text ?? "").trim().replace(/\s+/g, " ")
  const kind: Kind = body.kind === "expression" ? "expression" : "word"
  const target = (body.target_lang ?? "").trim()
  const native = (body.native_lang ?? "").trim() || "en"
  if (!text || !target) return errorResponse(400, "text and target_lang required")
  if (!isLanguageTag(target) || !isLanguageTag(native)) {
    return errorResponse(400, "language codes required")
  }
  if (text.length > MAX_LEN[kind]) return errorResponse(400, "too long")
  const key = text.toLowerCase()

  const svc = serviceRoleClient()

  // 1. Already in the library: count it and hand it back.
  {
    const hit = await findTerm(svc, target, kind, key)
    if (hit) {
      background(svc.rpc("library_term_bump", { p_id: hit.id }))
      return json({ status: "ok", term: hit.term, level: hit.level, existed: true })
    }
  }
  // 2. Read before and refused: the same answer, free.
  {
    const { data } = await svc.from("library_rejects")
      .select("verdict, suggestion")
      .eq("target_lang", target).eq("kind", kind).eq("key", key)
      .maybeSingle()
    if (data) return refusal(data.verdict, data.suggestion)
  }
  // 3. A new read: bounded per learner per day.
  {
    const since = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString()
    const [a, b] = await Promise.all([
      svc.from("library_terms").select("id", { count: "exact", head: true })
        .eq("created_by", user.id).gte("created_at", since),
      svc.from("library_rejects").select("key", { count: "exact", head: true })
        .eq("created_by", user.id).gte("created_at", since),
    ])
    if ((a.count ?? 0) + (b.count ?? 0) >= MAX_NEW_PER_DAY) {
      return errorResponse(429, "too many new terms today")
    }
  }

  const apiKey = Deno.env.get("GEMINI_API_KEY")
  if (!apiKey) return errorResponse(500, "server missing GEMINI_API_KEY")

  const { verdict, usage } = await judge(text, kind, target, apiKey)
  if (usage) record(usage)
  if (!verdict) return errorResponse(502, "could not read the term")

  if (verdict.verdict === "typo" && verdict.suggestion && inTargetScript(verdict.suggestion, target)) {
    await remember("typo", verdict.suggestion)
    return refusal("typo", verdict.suggestion)
  }
  const term = (verdict.headword ?? "").trim()
  const level = (verdict.level ?? "").toLowerCase()
  // "ok" on a respelled entry is a typo the model filed as fine: say so
  // rather than quietly storing a different word.
  if (verdict.verdict === "ok" && verdict.form === "respelled" && term && inTargetScript(term, target)) {
    await remember("typo", term)
    return refusal("typo", term)
  }
  // A word is one headword: a space in it means a phrase, whatever the
  // model said (it accepted "give up" as a word on the probe).
  if (verdict.verdict === "ok" && kind === "word" && /\s/.test(term) && !/^(ja|zh)/.test(target)) {
    await remember("wrong_kind", null)
    return refusal("wrong_kind", null)
  }
  if (verdict.verdict !== "ok" || !term || !LEVELS.has(level) || !inTargetScript(term, target)) {
    const reason = REASONS.has(verdict.verdict) ? verdict.verdict : "not_real"
    await remember(reason, null)
    return refusal(reason, null)
  }

  // The dictionary form may already be in the library under another
  // spelling of what was typed ("went" → go).
  const termKey = term.toLowerCase()
  const existing = await findTerm(svc, target, kind, termKey)
  if (existing) {
    background(svc.rpc("library_term_bump", { p_id: existing.id }))
    return json({ status: "ok", term: existing.term, level: existing.level, existed: true })
  }
  const { error } = await svc.from("library_terms").upsert(
    { target_lang: target, kind, term, key: termKey, level, created_by: user.id },
    { onConflict: "target_lang,kind,key", ignoreDuplicates: true },
  )
  if (error) console.error("library_terms insert failed", error.message)
  return json({ status: "ok", term, level, existed: false })

  async function remember(v: string, suggestion: string | null) {
    const { error } = await svc.from("library_rejects").upsert(
      { target_lang: target, kind, key, verdict: v, suggestion, created_by: user.id },
      { onConflict: "target_lang,kind,key", ignoreDuplicates: true },
    )
    if (error) console.error("library_rejects insert failed", error.message)
  }

  function record(usage: Record<string, number>) {
    const idempotencyKey = `library-add:${crypto.randomUUID()}`
    background(recordFreeUsage({
      supabase: svc, userId: user.id, action: "gemini", purpose: "library",
      dailyCap: 1_000_000, sourceFn: "library-add", idempotencyKey,
      metadata: { model: MODEL, purpose: "library", kind, target_lang: target },
    }).then(() => recordProviderUsage({ idempotencyKey, usage })))
  }
})

// deno-lint-ignore no-explicit-any
async function findTerm(svc: any, target: string, kind: Kind, key: string) {
  const { data } = await svc.from("library_terms")
    .select("id, term, level")
    .eq("target_lang", target).eq("kind", kind).eq("key", key)
    .maybeSingle()
  return data as { id: number; term: string; level: string } | null
}

function refusal(verdict: string, suggestion: string | null): Response {
  return verdict === "typo" && suggestion
    ? json({ status: "typo", suggestion })
    : json({ status: "rejected", reason: verdict })
}

type Verdict = { verdict: string; headword?: string; form?: string; suggestion?: string; level?: string }

async function judge(text: string, kind: Kind, target: string, apiKey: string):
  Promise<{ verdict: Verdict | null; usage: Record<string, number> | null }> {
  const lang = languageName(target)
  const what = kind === "word"
    ? `a WORD: one dictionary headword of ${lang} (a compound the language writes as one unit counts)`
    : `an EXPRESSION: a fixed, reusable multi-word chunk of ${lang} that speakers really use — an idiom, a collocation, a phrasal verb, a set phrase. Not a free sentence someone made up`
  const system = `You keep the shared graded dictionary of a ${lang} learning app. \
A learner typed something to add as ${what}. Every learner of ${lang} will see what you accept, \
so accept only real, standard ${lang}.

Answer with ONE JSON object, keys in this order:
{"verdict": "...", "headword": "...", "form": "...", "suggestion": "...", "level": "..."}

verdict is one of:
- "ok": what they typed is itself a real, standard ${lang} ${kind}, spelled correctly (an inflected form is fine — give its dictionary form as headword). Never "ok" with a different ${kind} in headword: if what they typed is not itself spelled right, it is "typo" or "not_real".
- "typo": a misspelling of a real ${lang} ${kind}. Put the correct dictionary form in "suggestion". Use this only when the intended ${kind} is clear.
- "not_real": invented, gibberish, random letters, a keyboard slip with no clear intent, chat shorthand or letter runs that no dictionary lists as a ${kind} (laughter like ㅋㅋㅋ or ｗｗｗ, bare consonants), or (for an expression) a whole free sentence rather than a fixed chunk.
- "proper_name": a person, brand, product, place or organization name.
- "not_target": not ${lang}.
- "wrong_kind": ${kind === "word" ? "it is several words — a phrase, a phrasal verb or an idiom, not one headword (\"give up\" is an expression, not a word)" : "it is one single word, not a multi-word expression"}.
- "offensive": a slur or hate term.
Slang and informal words that speakers really use are "ok".

headword (only for "ok"): the dictionary form in ${lang}, as a dictionary prints it — lowercase unless ${lang} capitalizes it (German nouns); an expression in its base form (verbs not conjugated, generic "someone"/"something" where the phrase takes an object), no sentence punctuation.
form (only for "ok"): how what they typed relates to headword — "same" (identical apart from capitalization), "inflected" (a conjugated, plural or otherwise inflected form of it), or "respelled" (you had to change letters to get a real ${kind}; then the verdict is "typo", not "ok"). Capitalization alone is never a typo.
level (only for "ok"): the CEFR level (a1, a2, b1, b2, c1, c2) at which a learner of ${lang} typically learns this ${kind}, as graded learner vocabulary lists rate it. Rate the ${kind} itself.
Leave fields that don't apply as "".`

  try {
    const upstream = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent?key=${apiKey}`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          system_instruction: { parts: [{ text: system }] },
          contents: [{ role: "user", parts: [{ text }] }],
          generationConfig: {
            maxOutputTokens: 2048,
            // Rare (once per new term per language) and it guards a list every
            // learner reads: "low" let a made-up word through on the probe.
            thinkingConfig: { thinkingLevel: "medium" },
            responseMimeType: "application/json",
          },
        }),
      },
    )
    if (!upstream.ok) {
      console.error("gemini upstream error", upstream.status, (await upstream.text()).slice(0, 300))
      return { verdict: null, usage: null }
    }
    const payload = await upstream.json()
    const usage = geminiUsageFields(payload?.usageMetadata)
    const out: string = payload?.candidates?.[0]?.content?.parts
      ?.map((p: { text?: string }) => p.text ?? "").join("") ?? ""
    const start = out.indexOf("{"), end = out.lastIndexOf("}")
    if (start < 0 || end < start) return { verdict: null, usage }
    try {
      return { verdict: JSON.parse(out.slice(start, end + 1)), usage }
    } catch {
      return { verdict: null, usage }
    }
  } catch (e) {
    console.error("library-add judge failed", e)
    return { verdict: null, usage: null }
  }
}

function languageName(code: string): string {
  const names: Record<string, string> = {
    en: "English", ko: "Korean", ja: "Japanese", de: "German", es: "Spanish",
    fr: "French", zh: "Chinese", it: "Italian", pt: "Portuguese",
  }
  return names[code.split("-")[0].toLowerCase()] ?? code
}

function json(payload: unknown, status = 200): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { "Content-Type": "application/json", ...cors() },
  })
}

function isLanguageTag(code: string): boolean {
  return /^[a-zA-Z]{2,3}(-[a-zA-Z0-9]{2,8}){0,3}$/.test(code)
}

// The app's `TextScript.isInTargetScript`, as word-entry carries it.
function inTargetScript(text: string, target: string): boolean {
  const base = target.split("-")[0].toLowerCase()
  const matches = (ch: string): boolean => {
    const v = ch.codePointAt(0)!
    const hangul = (v >= 0xAC00 && v <= 0xD7A3) || (v >= 0x1100 && v <= 0x11FF) || (v >= 0x3130 && v <= 0x318F)
    const kana = (v >= 0x3040 && v <= 0x30FF) || (v >= 0x31F0 && v <= 0x31FF) || (v >= 0xFF66 && v <= 0xFF9F)
    const han = (v >= 0x4E00 && v <= 0x9FFF) || (v >= 0x3400 && v <= 0x4DBF) || (v >= 0x20000 && v <= 0x2A6DF)
    const latin = v < 0x0250 || (v >= 0x1E00 && v <= 0x1EFF)
    switch (base) {
      case "ko": return hangul
      case "ja": return kana || han
      case "zh": return han
      default: return latin
    }
  }
  const isLetter = (ch: string) => /\p{L}/u.test(ch)
  if (base !== "ja" && base !== "zh") {
    const words = text.split(/\s+/).filter((w) => [...w].some(isLetter))
    if (words.length === 0) return false
    const ok = words.filter((w) => {
      const letters = [...w].filter(isLetter)
      return letters.filter(matches).length * 2 > letters.length
    }).length
    return ok / words.length >= 0.75
  }
  const letters = [...text].filter(isLetter)
  if (letters.length === 0) return false
  return letters.filter(matches).length / letters.length > 0.5
}
