// ElevenLabs voice-rename proxy.
//
// Body: { voice_id: string, name: string }
// Renames an EXISTING clone in place (POST /v1/voices/{id}/edit). The name is
// otherwise only settable at creation time, so without this a user who renames
// their voice would see it stay "Future Self" upstream until their next
// re-record.
//
// Free — no credits, no ledger row. Nothing is generated; this is a metadata
// write on a voice the caller already owns.

import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { requireUser, handlePreflight, errorResponse, cors } from "../_shared/auth.ts"

const MAX_NAME_LENGTH = 100

Deno.serve(async (req) => {
  const pre = handlePreflight(req)
  if (pre) return pre
  if (req.method !== "POST") return errorResponse(405, "method not allowed")

  const authed = await requireUser(req)
  if (authed instanceof Response) return authed
  const { user, supabase } = authed

  const apiKey = Deno.env.get("ELEVENLABS_API_KEY")
  if (!apiKey) return errorResponse(500, "server missing ELEVENLABS_API_KEY")

  let body: { voice_id?: string; name?: string }
  try { body = await req.json() } catch { return errorResponse(400, "invalid json body") }
  if (!body.voice_id) return errorResponse(400, "voice_id required")

  const name = (body.name ?? "").trim()
  if (!name) return errorResponse(400, "name required")
  if (name.length > MAX_NAME_LENGTH) return errorResponse(400, "name too long")

  // Same ownership gate as voice-delete: a caller can only touch a voice that
  // is mapped to their own user row.
  const { data: owned } = await supabase
    .from("voice_clones")
    .select("id")
    .eq("user_id", user.id)
    .eq("elevenlabs_voice_id", body.voice_id)
    .maybeSingle()
  if (!owned) return errorResponse(403, "voice not owned by caller")

  // The edit endpoint is multipart even when only the name changes; omitting
  // `files` leaves the existing samples untouched.
  const form = new FormData()
  form.append("name", name)

  const upstream = await fetch(
    `https://api.elevenlabs.io/v1/voices/${body.voice_id}/edit`,
    { method: "POST", headers: { "xi-api-key": apiKey }, body: form },
  )
  if (!upstream.ok) {
    const detail = await upstream.text()
    return errorResponse(upstream.status, "elevenlabs upstream error", detail.slice(0, 500))
  }

  return new Response(JSON.stringify({ ok: true }), {
    status: 200,
    headers: { "Content-Type": "application/json", ...cors() },
  })
})
