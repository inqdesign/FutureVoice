// ElevenLabs voice-clone proxy.
//
// Multipart pass-through, then mirrors the new voice_id into voice_clones.
// Clones cost NOTHING (minutes-native model: the meter is talk minutes and
// nothing else) — churn is bounded by a daily re-clone cap instead, with the
// onboarding window fully exempt: getting a voice the user believes is
// theirs is the entry ticket.

import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { requireUser, handlePreflight, errorResponse, cors } from "../_shared/auth.ts"
import { recordFreeUsage, rateLimitedResponse, billingClient } from "../_shared/credits.ts"

const SOURCE_FN = "elevenlabs-voice-clone"

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

  // Minutes-native model: clones are never PRICED — the meter is talk
  // minutes and nothing else. Re-clones past the onboarding window are
  // bounded by a daily cap instead: the accent/retake flow needs a handful,
  // a faucet needs more. (The cap row stamps this attempt's idempotency key
  // BEFORE upstream, so a failed upstream burns one slot — acceptable for
  // an abuse bound.)
  if (!isFree) {
    const rec = await recordFreeUsage({
      supabase, userId: user.id, action, purpose: "voice_clone",
      dailyCap: 5, sourceFn: SOURCE_FN, idempotencyKey: idemKey,
      metadata: { reclone: true },
    })
    if (!rec.ok) {
      if (rec.reason === "rate_limited") return rateLimitedResponse(cors())
      return errorResponse(500, "usage record failed", rec.detail)
    }
  }
  let balanceAfter = -1
  {
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

  // Mirrored into voice_clones below. The name is otherwise known only to
  // ElevenLabs and to the device that chose it, so nothing on our side can
  // say which user a voice in the library belongs to.
  const voiceName = ((incoming.get("name") as string | null) ?? "").trim() || null

  const upstream = await fetch("https://api.elevenlabs.io/v1/voices/add", {
    method: "POST",
    headers: { "xi-api-key": apiKey },
    body: outgoing,
  })

  if (!upstream.ok) {
    const detail = await upstream.text()
    return errorResponse(upstream.status, "elevenlabs upstream error", detail.slice(0, 500))
  }

  const json = await upstream.json() as { voice_id: string }

  // Free clone: stamp a 0-credit ledger row NOW (post-success) — the first
  // one anchors the grace window, the rest keep usage analytics honest about
  // what actually ran. Keyed per user for the first (idempotent), per
  // attempt for retakes.
  if (isFree) {
    await billingClient().rpc("charge_credits", {
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
      name: voiceName,
    })
  if (insErr) console.error("voice_clones insert failed", insErr)

  return new Response(JSON.stringify(json), {
    status: 200,
    headers: {
      "Content-Type": "application/json",
      "X-Credits-Balance": String(balanceAfter),
      ...cors(),
    },
  })
})
