// Free translation + correction-explanation lookup — no credit charge.
//
// Body: { kind: "translate", text: string, to_lang: string }
//     | { kind: "explain", original: string, alternative: string, to_lang: string }
// Returns: { text: string } (200)
//
// Why this is its own function instead of a "free purpose" on `gemini`:
// same reason as `word-entry` — the prompts here are fixed server-side, so a
// user CAN'T tag arbitrary generations (conversation turns, summaries) as
// "translate" to dodge charges. The abuse surface left is volume, capped by a
// per-user hourly limit (translation_log).
//
// Why free at all: these ran through the credit-gated `gemini` function at
// priceFor("gemini") = 1 credit — the same price as a full conversation turn —
// while the upstream cost on flash-lite is fractions of a cent. Users reviewing
// their talks burned more credits on meaning-taps than on the talk itself.
// Unlike word_entry there is NO shared cache: the inputs are the user's own
// conversation lines, which must not become globally readable. The client
// caches per-device instead (Translator.swift, memory + disk).

import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { requireUser, handlePreflight, errorResponse, cors } from "../_shared/auth.ts"
import { serviceRoleClient } from "../_shared/credits.ts"

// A heavy review session is dozens of taps; the client's disk cache means a
// line is only ever requested once per device. This cap only bites scripted
// volume abuse — and even then the upstream cost is negligible.
const MAX_CALLS_PER_HOUR = 300
const MAX_TEXT_LEN = 600

// Pure translation is mechanical → flash-lite. The correction explanation is
// learner-facing coaching text → stays on the default model (see CLAUDE.md
// "Model defaults"). Both are gen-3: thinkingLevel "low", default sampling.
const TRANSLATE_MODEL = "gemini-3.1-flash-lite"
const EXPLAIN_MODEL = "gemini-3.6-flash"

Deno.serve(async (req) => {
  const pre = handlePreflight(req)
  if (pre) return pre
  if (req.method !== "POST") return errorResponse(405, "method not allowed")

  const authed = await requireUser(req)
  if (authed instanceof Response) return authed
  const { user } = authed

  let body: {
    kind?: string
    text?: string
    original?: string
    alternative?: string
    to_lang?: string
  }
  try { body = await req.json() } catch { return errorResponse(400, "invalid json body") }

  const kind = body.kind ?? "translate"
  const toLang = (body.to_lang ?? "").trim()
  if (!toLang) return errorResponse(400, "to_lang required")
  const langName = new Intl.DisplayNames(["en"], { type: "language" }).of(toLang) ?? toLang

  let system: string
  let userText: string
  let model: string
  let maxTokens: number

  if (kind === "explain") {
    const original = (body.original ?? "").trim()
    const alternative = (body.alternative ?? "").trim()
    if (!original || !alternative) return errorResponse(400, "original and alternative required")
    if (original.length > MAX_TEXT_LEN || alternative.length > MAX_TEXT_LEN) {
      return errorResponse(400, "text too long")
    }
    // Mirrors the (now-removed) client-side Translator.explainCorrection
    // prompt verbatim so output is indistinguishable across app versions.
    system = `You are a language coach. The learner said something; a more natural \
version follows. Explain in ${langName}, in 2–3 short sentences, \
what was changed and why the natural version is better — quote the \
specific words that changed. Output only the explanation.`
    userText = `Learner said: ${original}\nMore natural: ${alternative}`
    model = EXPLAIN_MODEL
    maxTokens = 500
  } else if (kind === "translate") {
    const text = (body.text ?? "").trim()
    if (!text) return errorResponse(400, "text required")
    if (text.length > MAX_TEXT_LEN) return errorResponse(400, "text too long")
    // Mirrors the (now-removed) client-side Translator.translate prompt.
    system = `You are a translator. Translate the user's text into ${langName}. \
Output ONLY the translation — no quotes, no romanization, no notes, no original text.`
    userText = text
    model = TRANSLATE_MODEL
    maxTokens = 400
  } else {
    return errorResponse(400, "unknown kind")
  }

  const svc = serviceRoleClient()

  // Rate limit BEFORE spending upstream cost.
  {
    const since = new Date(Date.now() - 60 * 60 * 1000).toISOString()
    const { count, error } = await svc
      .from("translation_log")
      .select("id", { count: "exact", head: true })
      .eq("user_id", user.id)
      .gte("created_at", since)
    if (error) return errorResponse(500, "rate check failed", error.message)
    if ((count ?? 0) >= MAX_CALLS_PER_HOUR) {
      return errorResponse(429, "too many translations this hour")
    }
  }

  const apiKey = Deno.env.get("GEMINI_API_KEY")
  if (!apiKey) return errorResponse(500, "server missing GEMINI_API_KEY")

  const out = await generate(system, userText, model, maxTokens, apiKey)
  if (!out) return errorResponse(502, "generation failed")

  // Log AFTER success so failed upstream calls don't eat the user's quota.
  // Best-effort: the result is still valid if the log write fails.
  const { error: logErr } = await svc
    .from("translation_log")
    .insert({ user_id: user.id, kind, chars: userText.length })
  if (logErr) console.error("translation_log insert failed (non-fatal)", logErr.message)

  return new Response(JSON.stringify({ text: out }), {
    status: 200,
    headers: { "Content-Type": "application/json", ...cors() },
  })
})

async function generate(
  system: string,
  userText: string,
  model: string,
  maxTokens: number,
  apiKey: string,
): Promise<string | null> {
  try {
    const upstream = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${apiKey}`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          system_instruction: { parts: [{ text: system }] },
          contents: [{ role: "user", parts: [{ text: userText }] }],
          generationConfig: {
            maxOutputTokens: maxTokens,
            // Gen-3: default sampling (no temperature), minimum thinking.
            thinkingConfig: { thinkingLevel: "low" },
          },
        }),
      },
    )
    if (!upstream.ok) {
      console.error("gemini upstream error", upstream.status, (await upstream.text()).slice(0, 300))
      return null
    }
    const payload = await upstream.json()
    const text: string = payload?.candidates?.[0]?.content?.parts
      ?.map((p: { text?: string }) => p.text ?? "").join("") ?? ""
    const trimmed = text.trim()
    return trimmed.length > 0 ? trimmed : null
  } catch (e) {
    console.error("translate generate failed", e)
    return null
  }
}
