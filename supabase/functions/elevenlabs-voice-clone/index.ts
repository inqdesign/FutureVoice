// ElevenLabs voice-clone proxy + credit gate.
//
// Multipart pass-through, then mirrors the new voice_id into voice_clones.
// Charges 5 credits (priceFor("voice_clone")) — voice slot management is
// expensive enough that we don't want users churning clones.

import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { requireUser, handlePreflight, errorResponse, cors } from "../_shared/auth.ts"
import { priceFor, charge, refund, insufficientCreditsResponse } from "../_shared/credits.ts"

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
  // The FIRST clone is free — it's the product's entry ticket, not usage.
  // Re-records pay. "First" = no voice_clone row in the ledger yet (the free
  // clone stamps a 0-credit row AFTER upstream success, so a failed first
  // attempt stays free on retry).
  const { data: priorClone } = await supabase
    .from("usage_ledger")
    .select("id")
    .eq("user_id", user.id)
    .eq("action", action)
    .limit(1)
  const isFirstClone = (priorClone?.length ?? 0) === 0
  const amount = isFirstClone ? 0 : priceFor(action)
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
    return errorResponse(upstream.status, "elevenlabs upstream error", detail.slice(0, 500))
  }

  const json = await upstream.json() as { voice_id: string }

  // Free first clone: stamp a 0-credit ledger row NOW (post-success) so the
  // next clone reads as a re-record and pays. Idempotent per user.
  if (isFirstClone) {
    await supabase.rpc("charge_credits", {
      p_user_id: user.id,
      p_credits: 0,
      p_action: action,
      p_source_fn: SOURCE_FN,
      p_idempotency_key: `first-clone:${user.id}`,
      p_metadata: { free_first_clone: true },
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

  return new Response(JSON.stringify(json), {
    status: 200,
    headers: {
      "Content-Type": "application/json",
      "X-Credits-Balance": String(balanceAfter),
      ...cors(),
    },
  })
})
