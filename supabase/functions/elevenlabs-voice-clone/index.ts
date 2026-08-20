// ElevenLabs voice-clone proxy + credit gate.
//
// Multipart pass-through, then mirrors the new voice_id into voice_clones.
// Charges 5 credits (priceFor("voice_clone")) — voice slot management is
// expensive enough that we don't want users churning clones — EXCEPT during
// onboarding, where getting a voice the user believes is theirs is the entry
// ticket: see the allowance below.

import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { requireUser, handlePreflight, errorResponse, cors } from "../_shared/auth.ts"
import { priceFor, charge, refund, insufficientCreditsResponse } from "../_shared/credits.ts"
import { alertVoiceCapacity, alertVoiceHeadroom } from "../_shared/ops_alert.ts"

const SOURCE_FN = "elevenlabs-voice-clone"

// Upstream failures that mean "OUR account has no room", not "this user did
// something wrong": the plan's custom-voice slots are full, or ElevenLabs is
// throttling us. The user cannot act on any of them — only a plan upgrade
// can — so they get a wait-and-retry sheet and the owner gets a Telegram
// ping. Everything else keeps the raw upstream error.
const CAPACITY_MARKERS = [
  "voice_limit_reached",
  "voice_add_edit_limit_reached",
  "max_voice_limit_reached",
  "professional_voice_limit_reached",
  "quota_exceeded",
]

function isCapacityFailure(status: number, body: string): boolean {
  const lower = body.toLowerCase()
  if (CAPACITY_MARKERS.some((marker) => lower.includes(marker))) return true
  return status === 429   // upstream rate limit is our ceiling too
}

/**
 * 429, deliberately, not 503: the iOS client auto-retries 5xx three times
 * (NetworkSupport.withRetry) and this failure will not clear in 500ms — it
 * clears when a human upgrades the plan. Re-uploading the sample twice more
 * would only make the user wait longer for the same sheet.
 *
 * `error: "voice_capacity"` is the contract the app matches on
 * (ElevenLabsError.capacityLimited).
 */
/**
 * Heads-up BEFORE the ceiling. Reading the slot count costs one free upstream
 * GET on a request that already took seconds, and it buys the only thing that
 * actually prevents the blocked-signup incident: the owner upgrading the plan
 * while there's still room. Best-effort — a failed check never touches the
 * clone the user just got.
 */
async function warnIfVoiceSlotsLow(apiKey: string): Promise<void> {
  try {
    const res = await fetch("https://api.elevenlabs.io/v1/user/subscription", {
      headers: { "xi-api-key": apiKey },
    })
    if (!res.ok) return
    const sub = await res.json() as { voice_limit?: number; voice_slots_used?: number }
    const limit = sub.voice_limit
    const used = sub.voice_slots_used
    if (typeof limit !== "number" || typeof used !== "number" || limit <= 0) return
    // Last 10% of the plan, and never less than a 3-slot warning — on a small
    // plan 10% rounds down to "no warning at all".
    const cushion = Math.max(3, Math.ceil(limit * 0.1))
    if (limit - used > cushion) return
    await alertVoiceHeadroom({ used, limit, sourceFn: SOURCE_FN })
  } catch (e) {
    console.error("voice headroom check failed (non-fatal)", e)
  }
}

function voiceCapacityResponse(): Response {
  return new Response(
    JSON.stringify({
      error: "voice_capacity",
      message: "Voice creation is temporarily at capacity. Your recording is safe — please try again shortly.",
      retry_after_seconds: 600,
    }),
    {
      status: 429,
      headers: { "Content-Type": "application/json", "Retry-After": "600", ...cors() },
    },
  )
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

  const apiKey = Deno.env.get("ELEVENLABS_API_KEY")
  if (!apiKey) return errorResponse(500, "server missing ELEVENLABS_API_KEY")

  const contentType = req.headers.get("Content-Type") ?? ""
  if (!contentType.includes("multipart/form-data")) {
    return errorResponse(400, "expected multipart/form-data")
  }

  const action = "voice_clone" as const
  // The FIRST clone is free — it's the product's entry ticket, not usage —
  // and so are the retakes that immediately follow it. The user only learns
  // whether the clone sounds like THEM one screen later, when they first
  // hear it speak; charging for "that isn't my voice, let me read it again"
  // would price the entry ticket after the fact. Bounded by TIME only —
  // deliberately no attempt cap: the user who needs six takes before the
  // voice sounds like them is exactly the user we can least afford to
  // charge, and the window alone keeps this from being a free-clone faucet.
  // Re-records after it (Me → Voice) pay the full price.
  //
  // "First" = no voice_clone row in the ledger yet. Every free clone stamps
  // a 0-credit row AFTER upstream success, so a failed attempt stays free on
  // retry and the window is anchored to a clone the user actually got.
  const ONBOARDING_GRACE_MS = 24 * 60 * 60 * 1000
  const { data: priorClones } = await supabase
    .from("usage_ledger")
    .select("created_at")
    .eq("user_id", user.id)
    .eq("action", action)
    // Debits only — a refunded failed clone also writes a voice_clone row,
    // and it must not move the anchor.
    .eq("kind", "debit")
    .order("created_at", { ascending: true })
    .limit(1)
  const firstCloneAt = priorClones?.[0]?.created_at
    ? Date.parse(priorClones[0].created_at as string)
    : null
  const isFirstClone = firstCloneAt === null
  const withinOnboardingGrace =
    firstCloneAt !== null && Number.isFinite(firstCloneAt) &&
    Date.now() - firstCloneAt < ONBOARDING_GRACE_MS
  const isFree = isFirstClone || withinOnboardingGrace
  const amount = isFree ? 0 : priceFor(action)
  let balanceAfter = -1
  if (amount > 0) {
    const ch = await charge({
      supabase, userId: user.id, action, amount,
      sourceFn: SOURCE_FN, idempotencyKey: idemKey,
    })
    if (!ch.ok) {
      if (ch.reason === "insufficient_credits" || ch.reason === "no_credit_row") {
        return insufficientCreditsResponse(cors())
      }
      return errorResponse(500, "charge failed", ch.detail)
    }
    balanceAfter = ch.balanceAfter ?? -1
  } else {
    const { data: row } = await supabase
      .from("user_credits").select("balance").eq("user_id", user.id).maybeSingle()
    balanceAfter = row?.balance ?? -1
  }

  const incoming = await req.formData()
  const outgoing = new FormData()
  for (const [key, value] of incoming.entries()) {
    if (value instanceof File) outgoing.append(key, value, value.name)
    else outgoing.append(key, value)
  }

  const upstream = await fetch("https://api.elevenlabs.io/v1/voices/add", {
    method: "POST",
    headers: { "xi-api-key": apiKey },
    body: outgoing,
  })

  if (!upstream.ok) {
    if (amount > 0) {
      await refund({
        supabase, userId: user.id, amount, action,
        sourceFn: SOURCE_FN, originalIdempotencyKey: idemKey,
        metadata: { reason: "upstream_error", status: upstream.status },
      })
    }
    const detail = await upstream.text()
    if (isCapacityFailure(upstream.status, detail)) {
      // Straight to the owner's phone: every signup behind this one fails the
      // same way until the plan grows.
      await alertVoiceCapacity({
        userId: user.id, sourceFn: SOURCE_FN, status: upstream.status, detail,
      })
      return voiceCapacityResponse()
    }
    return errorResponse(upstream.status, "elevenlabs upstream error", detail.slice(0, 500))
  }

  const json = await upstream.json() as { voice_id: string }

  // Free clone: stamp a 0-credit ledger row NOW (post-success) — the first
  // one anchors the grace window, the rest keep usage analytics honest about
  // what actually ran. Keyed per user for the first (idempotent), per
  // attempt for retakes.
  if (isFree) {
    await supabase.rpc("charge_credits", {
      p_user_id: user.id,
      p_credits: 0,
      p_action: action,
      p_source_fn: SOURCE_FN,
      p_idempotency_key: isFirstClone ? `first-clone:${user.id}` : `free-clone:${idemKey}`,
      p_metadata: isFirstClone
        ? { free_first_clone: true }
        : { free_onboarding_retake: true },
    })
  }

  // Deactivate prior active clones so the partial unique index accepts
  // the new row.
  await supabase
    .from("voice_clones")
    .update({ is_active: false })
    .eq("user_id", user.id)
    .eq("is_active", true)

  const { error: insErr } = await supabase
    .from("voice_clones")
    .insert({
      user_id: user.id,
      elevenlabs_voice_id: json.voice_id,
      is_active: true,
    })
  if (insErr) console.error("voice_clones insert failed", insErr)

  await warnIfVoiceSlotsLow(apiKey)

  return new Response(JSON.stringify(json), {
    status: 200,
    headers: {
      "Content-Type": "application/json",
      "X-Credits-Balance": String(balanceAfter),
      ...cors(),
    },
  })
})
