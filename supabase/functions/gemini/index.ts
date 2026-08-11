// Gemini generateContent proxy — FREE since 2026-08, rate-capped per purpose.
//
// Body: { model, system_instruction?, contents, generationConfig?, purpose?, stream? }
// `purpose` (optional) tags the call's intent ("turn" | "summary" | "weekly" |
// "enrichment" | "transcribe" | "topics" | "scene" | …) so usage_ledger groups
// by feature and each purpose gets its own daily request cap.
// `stream: true` switches the upstream call to `streamGenerateContent?alt=sse`
// and pipes the SSE body straight through, so a conversation turn can start
// speaking on the first complete JSON field instead of the whole body.
//
// Why free: the 1-credit charge (~$0.04) sat on calls costing ~$0.002
// upstream, and beta users reported per-click credit anxiety killing review
// and exploration. Money is metered where cost actually lives (TTS chars →
// talk minutes); Gemini is defended by invisible per-purpose daily caps that
// a real learner can never hit. A 0-delta ledger row is still written per
// call (record_free_usage), so per-feature attribution and abuse detection
// keep working.

import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { requireUser, handlePreflight, errorResponse, cors } from "../_shared/auth.ts"
import { recordFreeUsage, rateLimitedResponse,
         type ChargeableAction } from "../_shared/credits.ts"

const SOURCE_FN = "gemini"

// Requests per user per day, by purpose. Sized ~5-10x above a very heavy real
// user so only scripts ever collide with them. Unknown purposes get DEFAULT.
const DAILY_CAPS: Record<string, number> = {
  "turn": 800,                 // ≥60 min of talking plus retries
  "transcribe": 800,           // paired 1:1 with turns
  "opener": 120,
  "freetalk-openers": 30,      // one pool per language/persona change
  "topics": 200,
  "scene": 60,
  "scenario-curriculum": 60,
  "shadow": 400,               // per-attempt coach bullets
  "summary": 60,
  "weekly": 10,
  "enrichment": 200,
  "parse": 60,
  "daily-call-script": 20,
  "clone-script": 20,
}
const DEFAULT_DAILY_CAP = 300

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

  let body: { model?: string; purpose?: string; [k: string]: unknown }
  try { body = await req.json() } catch { return errorResponse(400, "invalid json body") }
  const model = body.model ?? "gemini-2.5-flash"
  const purpose = body.purpose
  const stream = body.stream === true
  const { model: _m, purpose: _p, stream: _s, ...geminiBody } = body

  // Ledger action keys stay split for the historically-priced purposes so
  // spend dashboards keep their series; everything else lands on "gemini".
  const action: ChargeableAction =
    purpose === "summary"    ? "gemini_summary" :
    purpose === "weekly"     ? "gemini_weekly"  :
    purpose === "enrichment" ? "gemini_enrichment" :
    purpose === "transcribe" ? "gemini_transcribe" :
    "gemini"

  const purposeKey = purpose ?? "generic"
  const rec = await recordFreeUsage({
    supabase, userId: user.id, action, purpose: purposeKey,
    dailyCap: DAILY_CAPS[purposeKey] ?? DEFAULT_DAILY_CAP,
    sourceFn: SOURCE_FN, idempotencyKey: idemKey,
    metadata: { model, purpose: purpose ?? null },
  })
  if (!rec.ok) {
    if (rec.reason === "rate_limited") return rateLimitedResponse(cors())
    return errorResponse(500, "usage record failed", rec.detail)
  }

  const endpoint = stream
    ? `${model}:streamGenerateContent?alt=sse&key=${apiKey}`
    : `${model}:generateContent?key=${apiKey}`
  const upstream = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${endpoint}`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(geminiBody),
    },
  )

  if (!upstream.ok) {
    // Nothing was charged, so there is nothing to refund. The 0-delta ledger
    // row stays — a failed upstream call is still a call worth counting.
    const detail = await upstream.text()
    return errorResponse(upstream.status, "gemini upstream error", detail.slice(0, 500))
  }

  // `X-Gemini-Stream` is the protocol handshake: a client that asked for SSE
  // but talks to an older deploy sees no header and buffers the plain JSON
  // body instead of waiting for events that will never come.
  if (stream && upstream.body) {
    return new Response(upstream.body, {
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
  return new Response(text, {
    status: 200,
    headers: {
      "Content-Type": "application/json",
      ...cors(),
    },
  })
})
