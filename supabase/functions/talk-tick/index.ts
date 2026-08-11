// Wall-clock talk metering — the in-call timer IS the price.
//
// Body: { seconds: number (1–600), session_id: string }
// Required header: X-Idempotency-Key (e.g. "tick:<session>:<n>" — one key
// per tick so a retried request can't double-bill).
//
// The app calls this every 30 s while a call is active (plus a 1-second
// preflight tick at call start, so an empty balance surfaces BEFORE the
// greeting speaks instead of granting a free minute per fresh session).
// Seconds pool per (user, day) server-side and debit the credit balance at
// 4.5 credits/minute on boundary crossings (`charge_talk_seconds`), so the
// long-run price is exact regardless of tick cadence. 402 when the balance
// is spent — the app ends the call gracefully on that.
//
// Turn/opener TTS is free under a chars-per-minute floor tied to the
// seconds pooled here (see charge_turn_tts_floored) — that floor is what
// makes under-reporting call time pointless.

import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { requireUser, handlePreflight, errorResponse, cors } from "../_shared/auth.ts"
import { insufficientCreditsResponse } from "../_shared/credits.ts"

const SOURCE_FN = "talk-tick"

Deno.serve(async (req) => {
  const pre = handlePreflight(req)
  if (pre) return pre
  if (req.method !== "POST") return errorResponse(405, "method not allowed")

  const authed = await requireUser(req)
  if (authed instanceof Response) return authed
  const { user, supabase } = authed

  const idemKey = req.headers.get("X-Idempotency-Key")
  if (!idemKey) return errorResponse(400, "missing X-Idempotency-Key header")

  let body: { seconds?: number; session_id?: string }
  try { body = await req.json() } catch { return errorResponse(400, "invalid json body") }
  const seconds = body.seconds
  if (typeof seconds !== "number" || !Number.isInteger(seconds) ||
      seconds < 1 || seconds > 600) {
    return errorResponse(400, "seconds must be an integer in 1...600")
  }

  const { data, error } = await supabase.rpc("charge_talk_seconds", {
    p_user_id: user.id,
    p_seconds: seconds,
    p_source_fn: SOURCE_FN,
    p_idempotency_key: idemKey,
    p_metadata: { session_id: body.session_id ?? null },
  })
  if (error) {
    if (error.message?.includes("INSUFFICIENT_CREDITS")) {
      return insufficientCreditsResponse(cors())
    }
    return errorResponse(500, "talk tick failed", error.message)
  }

  const parsed = data as { balance?: number; charged?: number; seconds_today?: number }
  return new Response(
    JSON.stringify({
      balance: parsed?.balance ?? 0,
      charged: parsed?.charged ?? 0,
      seconds_today: parsed?.seconds_today ?? 0,
    }),
    { status: 200, headers: { "Content-Type": "application/json", ...cors() } },
  )
})
