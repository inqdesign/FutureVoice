// ElevenLabs voice-delete proxy.
//
// Body: { voice_id: string }
// Charges 0 credits — delete is free, but we still write a ledger row for
// audit trail (handy when troubleshooting "where did my voice go").

import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { requireUser, handlePreflight, errorResponse, cors } from "../_shared/auth.ts"
import { priceFor, charge } from "../_shared/credits.ts"

const SOURCE_FN = "elevenlabs-voice-delete"

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

  let body: { voice_id?: string }
  try { body = await req.json() } catch { return errorResponse(400, "invalid json body") }
  if (!body.voice_id) return errorResponse(400, "voice_id required")

  const { data: owned } = await supabase
    .from("voice_clones")
    .select("id")
    .eq("user_id", user.id)
    .eq("elevenlabs_voice_id", body.voice_id)
    .maybeSingle()
  if (!owned) return errorResponse(403, "voice not owned by caller")

  // Free, but creates an audit row.
  await charge({
    supabase, userId: user.id,
    action: "voice_delete",
    amount: priceFor("voice_delete"),
    sourceFn: SOURCE_FN,
    idempotencyKey: idemKey,
    metadata: { voice_id: body.voice_id },
  })

  const upstream = await fetch(`https://api.elevenlabs.io/v1/voices/${body.voice_id}`, {
    method: "DELETE",
    headers: { "xi-api-key": apiKey },
  })
  if (!upstream.ok) {
    const detail = await upstream.text()
    return errorResponse(upstream.status, "elevenlabs upstream error", detail.slice(0, 500))
  }

  await supabase
    .from("voice_clones")
    .update({ is_active: false })
    .eq("id", owned.id)

  return new Response(JSON.stringify({ ok: true }), {
    status: 200,
    headers: { "Content-Type": "application/json", ...cors() },
  })
})
