// ElevenLabs voice-clone proxy.
//
// Accepts the same multipart/form-data body the iOS app would send to
// ElevenLabs directly (name, description, remove_background_noise, files…)
// and forwards it upstream with the server-side `xi-api-key`.
//
// On success, also records the new voice_id in `public.voice_clones` so
// the user can recover it on reinstall.

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

  const contentType = req.headers.get("Content-Type") ?? ""
  if (!contentType.includes("multipart/form-data")) {
    return errorResponse(400, "expected multipart/form-data")
  }

  // Read incoming form data, then re-serialize it for the upstream call.
  // We can't pass `req.body` through directly because Deno's fetch
  // requires a fresh boundary on the outgoing multipart frame.
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
    const detail = await upstream.text()
    return errorResponse(upstream.status, "elevenlabs upstream error", detail.slice(0, 500))
  }

  const json = await upstream.json() as { voice_id: string }

  // Mirror to voice_clones — deactivate prior active row(s) for this user
  // first so the partial unique index voice_clones_user_active_idx accepts
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
  if (insErr) {
    // Don't fail the request — the voice exists in ElevenLabs already and
    // the user can still use it; we just lose cloud recovery for this one.
    console.error("voice_clones insert failed", insErr)
  }

  return new Response(JSON.stringify(json), {
    status: 200,
    headers: { "Content-Type": "application/json", ...cors() },
  })
})
