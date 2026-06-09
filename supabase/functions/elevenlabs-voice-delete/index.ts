// ElevenLabs voice-delete proxy.
//
// Body: { voice_id: string }
//
// Deletes the voice on ElevenLabs and marks the matching row in
// public.voice_clones as inactive (we don't hard-delete the row so we
// keep an audit trail of past voices for analytics).

import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { requireUser, handlePreflight, errorResponse, cors } from "../_shared/auth.ts"

Deno.serve(async (req) => {
  const pre = handlePreflight(req)
  if (pre) return pre
  if (req.method !== "POST") return errorResponse(405, "method not allowed")

  const authed = await requireUser(req)
  if (authed instanceof Response) return authed
  const { user, supabase } = authed

  const apiKey = Deno.env.get("ELEVENLABS_API_KEY")
  if (!apiKey) return errorResponse(500, "server missing ELEVENLABS_API_KEY")

  let body: { voice_id?: string }
  try {
    body = await req.json()
  } catch {
    return errorResponse(400, "invalid json body")
  }
  if (!body.voice_id) return errorResponse(400, "voice_id required")

  // Confirm this user actually owns the voice before deleting upstream —
  // RLS would block their voice_clones row update anyway, but checking up
  // front means we don't burn an ElevenLabs delete on someone else's voice.
  const { data: owned } = await supabase
    .from("voice_clones")
    .select("id")
    .eq("user_id", user.id)
    .eq("elevenlabs_voice_id", body.voice_id)
    .maybeSingle()
  if (!owned) return errorResponse(403, "voice not owned by caller")

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
