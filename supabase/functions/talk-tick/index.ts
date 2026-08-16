// Wall-clock talk metering — the in-call timer IS the price.
//
// Body: { seconds: number (1–600), session_id: string }
// Required header: X-Idempotency-Key (e.g. "tick:<session>:<n>" — one key
// per tick so a retried request can't double-bill).
//
// The app calls this every 30 s while a call is active (plus a 1-second
// preflight tick at call start, so an empty allowance surfaces BEFORE the
// greeting speaks instead of granting a free minute per fresh session).
// Seconds pool per (user, day) server-side; subscribers consume their
// plan's daily allowance and free users' seconds balance is debited 1:1
// (`charge_talk_seconds` → consume_metered_seconds). Two 402s, told apart
// by the body's `error` field:
//   * insufficient_credits — free user's one-time pool is spent → paywall.
//   * daily_cap_reached   — subscriber used today's minutes → "see you
//     tomorrow", never a paywall.
//
// Turn/opener TTS is free under a chars-per-minute floor tied to the
// seconds pooled here (see charge_turn_tts_floored) — that floor is what
// makes under-reporting call time pointless.

import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { requireUser, handlePreflight, errorResponse, cors } from "../_shared/auth.ts"
import { insufficientCreditsResponse, dailyCapResponse, billingClient } from "../_shared/credits.ts"

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

  let body: { seconds?: number; session_id?: string; language?: string }
  try { body = await req.json() } catch { return errorResponse(400, "invalid json body") }
  const seconds = body.seconds
  if (typeof seconds !== "number" || !Number.isInteger(seconds) ||
      seconds < 1 || seconds > 600) {
    return errorResponse(400, "seconds must be an integer in 1...600")
  }

  const { data, error } = await billingClient().rpc("charge_talk_seconds", {
    p_user_id: user.id,
    p_seconds: seconds,
    p_source_fn: SOURCE_FN,
    p_idempotency_key: idemKey,
    p_metadata: { session_id: body.session_id ?? null },
    // The Core is one club per target language and this tick is the only
    // place the server hears which language was spoken. Absent on older
    // builds — those seconds bill normally and count toward no club, which
    // is correct: a client that can't say what was spoken shouldn't be
    // guessed at.
    p_language: body.language ?? null,
  })
  if (error) {
    if (error.message?.includes("INSUFFICIENT_CREDITS")) {
      return insufficientCreditsResponse(cors())
    }
    if (error.message?.includes("DAILY_CAP_REACHED")) {
      return dailyCapResponse(cors())
    }
    return errorResponse(500, "talk tick failed", error.message)
  }

  const parsed = data as {
    balance?: number; charged?: number; seconds_today?: number; daily_cap?: number
  }
  return new Response(
    JSON.stringify({
      balance: parsed?.balance ?? 0,
      charged: parsed?.charged ?? 0,
      seconds_today: parsed?.seconds_today ?? 0,
      daily_cap: parsed?.daily_cap ?? null,
    }),
    { status: 200, headers: { "Content-Type": "application/json", ...cors() } },
  )
})
