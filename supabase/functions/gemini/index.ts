// Gemini generateContent proxy + credit gate.
//
// Body: { model, system_instruction?, contents, generationConfig?, purpose?, stream? }
// `purpose` (optional) lets the client tag the call as one of:
//   "summary" | "weekly" | "enrichment" | undefined (= generic)
// so usage_ledger groups by intent and pricing can differ per intent.
// `stream: true` switches the upstream call to `streamGenerateContent?alt=sse`
// and pipes the SSE body straight through, so a conversation turn can start
// speaking on the first complete JSON field instead of the whole body.
// Billing is unchanged — one charge per idempotency key either way.

import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { requireUser, handlePreflight, errorResponse, cors } from "../_shared/auth.ts"
import { priceFor, charge, refund, insufficientCreditsResponse,
         type ChargeableAction } from "../_shared/credits.ts"

const SOURCE_FN = "gemini"

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

  const action: ChargeableAction =
    purpose === "summary"    ? "gemini_summary" :
    purpose === "weekly"     ? "gemini_weekly"  :
    purpose === "enrichment" ? "gemini_enrichment" :
    "gemini"
  const amount = priceFor(action)

  const ch = await charge({
    supabase, userId: user.id, action, amount,
    sourceFn: SOURCE_FN, idempotencyKey: idemKey,
    metadata: { model, purpose: purpose ?? null },
  })
  if (!ch.ok) {
    if (ch.reason === "insufficient_credits" || ch.reason === "no_credit_row") {
      return insufficientCreditsResponse(cors())
    }
    return errorResponse(500, "charge failed", ch.detail)
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
    await refund({
      supabase, userId: user.id, amount, action,
      sourceFn: SOURCE_FN, originalIdempotencyKey: idemKey,
      metadata: { reason: "upstream_error", status: upstream.status },
    })
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
        "X-Credits-Balance": String(ch.balanceAfter),
        ...cors(),
      },
    })
  }

  const text = await upstream.text()
  return new Response(text, {
    status: 200,
    headers: {
      "Content-Type": "application/json",
      "X-Credits-Balance": String(ch.balanceAfter),
      ...cors(),
    },
  })
})
