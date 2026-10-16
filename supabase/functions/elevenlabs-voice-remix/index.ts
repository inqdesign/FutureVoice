// The accent picker. (Named for the ElevenLabs remix it once proxied; every
// build in the store calls it by this name. ElevenLabs is gone since
// 2026-10-15 — every voice is a Cartesia voice, and an accent is something
// that one voice is TOLD to speak in, see _shared/cartesia.ts.)
//
// Two calls, distinguished by body shape, answered in the shape every build
// already reads:
//
//   { voice_id, voice_description, text }
//       → a TAKE of the line in the asked accent:
//         { previews: [{ audio_base_64, generated_voice_id: "<uuid>:<accent>" }] }
//   { generated_voice_id, voice_name, voice_description }
//       → SAVE: the accent goes onto the learner's live voice → { voice_id }
//
// Free (0 credits) — the accent pick is part of getting a voice the user
// believes is theirs — bounded by per-purpose daily caps instead of a price.

import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { requireUser, handlePreflight, errorResponse, cors } from "../_shared/auth.ts"
import { recordFreeUsage, rateLimitedResponse } from "../_shared/credits.ts"

import * as cartesia from "../_shared/cartesia.ts"
import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.45.0"

const SOURCE_FN = "elevenlabs-voice-remix"

Deno.serve(async (req) => {
  const pre = handlePreflight(req)
  if (pre) return pre
  if (req.method !== "POST") return errorResponse(405, "method not allowed")

  const authed = await requireUser(req)
  if (authed instanceof Response) return authed
  const { user, supabase } = authed

  const idemKey = req.headers.get("X-Idempotency-Key")
  if (!idemKey) return errorResponse(400, "missing X-Idempotency-Key header")

  let body: {
    voice_id?: string
    voice_description?: string
    text?: string
    generated_voice_id?: string
    voice_name?: string
    purpose?: string
  }
  try { body = await req.json() } catch { return errorResponse(400, "invalid json body") }
  if (!body.voice_description) return errorResponse(400, "voice_description required")
  return await cartesiaAccent(supabase, user.id, idemKey, body)
})

/** Accent takes and accent saves for a Cartesia voice.
 *  TAKES: the line spoken by the same voice in the asked accent, returned as
 *  one preview whose id is "<uuid>:<accent>".
 *  SAVE: that id becomes the learner's voice id — a new voice_clones row,
 *  the same Cartesia voice underneath. */
async function cartesiaAccent(
  supabase: SupabaseClient, userId: string, idemKey: string,
  body: { voice_id?: string; voice_description?: string; text?: string; generated_voice_id?: string; voice_name?: string },
): Promise<Response> {
  const json = (o: unknown, status = 200) => new Response(JSON.stringify(o), {
    status, headers: { "Content-Type": "application/json", ...cors() },
  })
  // Owns the Cartesia voice under any of its accent ids.
  const owns = async (uuid: string) => {
    const { data } = await supabase.from("voice_clones").select("id, name")
      .eq("user_id", userId).like("elevenlabs_voice_id", `${uuid}%`).limit(1)
    return (data ?? [])[0] as { id: string; name: string | null } | undefined
  }

  if (body.generated_voice_id) {
    // On Cartesia a take is only a sample of an ACCENT — what is saved is
    // "the learner's voice + this accent". So the take's own voice is ignored
    // and the accent goes onto the voice that is live NOW. The app keeps takes
    // per recording and offers ones made from a voice a rebuild has since
    // deleted; saving such a take as-is pointed the learner at a voice that no
    // longer exists (silent calls), and refusing it showed "couldn't remix"
    // (both 2026-10-12). The accent is read off the take id, or else the
    // description (a take cached by an older build carries none in its id).
    const fromTake = cartesia.isCartesiaVoice(body.generated_voice_id)
      ? cartesia.parseVoice(body.generated_voice_id).accent : null
    const accent = fromTake ?? cartesia.accentFromDescription(body.voice_description ?? "")
    const { data: active } = await supabase.from("voice_clones").select("elevenlabs_voice_id, name")
      .eq("user_id", userId).eq("is_active", true).limit(1)
    const current = (active ?? [])[0] as { elevenlabs_voice_id: string; name: string | null } | undefined
    if (!current || !cartesia.isCartesiaVoice(current.elevenlabs_voice_id)) {
      return errorResponse(409, "no Cartesia voice to apply the accent to")
    }
    const { uuid } = cartesia.parseVoice(current.elevenlabs_voice_id)
    if (accent) {
      const ready = await cartesia.ensureAccent(uuid, accent)
      if (!ready.ok) return errorResponse(502, "cartesia accent failed", ready.detail ?? "")
    }
    const id = accent ? `${uuid}:${accent}` : uuid
    if (id === current.elevenlabs_voice_id) return json({ voice_id: id })
    await supabase.from("voice_clones").update({ is_active: false })
      .eq("user_id", userId).eq("is_active", true)
    const { error } = await supabase.from("voice_clones").insert({
      user_id: userId, elevenlabs_voice_id: id, is_active: true,
      name: (body.voice_name ?? "").trim() || current.name,
    })
    if (error) console.error("voice_clones insert failed", error)
    return json({ voice_id: id })
  }

  if (!body.voice_id || !body.text) return errorResponse(400, "voice_id and text required")
  const { uuid } = cartesia.parseVoice(body.voice_id)
  if (!(await owns(uuid))) return errorResponse(403, "voice not owned by caller")
  const accent = cartesia.accentFromDescription(body.voice_description ?? "")
  if (!accent) return errorResponse(400, "accent not recognised")

  const free = await recordFreeUsage({
    supabase, userId, action: "voice_remix", purpose: "accent_previews",
    dailyCap: 24, sourceFn: SOURCE_FN, idempotencyKey: idemKey,
    metadata: { voice_id: body.voice_id, accent, provider: "cartesia" },
  })
  if (!free.ok) {
    if (free.reason === "rate_limited") return rateLimitedResponse(cors())
    return errorResponse(500, "usage record failed", free.detail)
  }

  const ready = await cartesia.ensureAccent(uuid, accent)
  if (!ready.ok) return errorResponse(502, "cartesia accent failed", ready.detail ?? "")
  const take = await cartesia.synthesizeMp3({
    voiceId: `${uuid}:${accent}`, text: body.text, language: cartesia.ACCENT_LANGUAGE[accent] ?? "en",
  })
  if (!take.ok) return errorResponse(take.status, "cartesia upstream error", (await take.text()).slice(0, 500))
  const audio = new Uint8Array(await take.arrayBuffer())
  let bin = ""
  for (let i = 0; i < audio.length; i += 0x8000) bin += String.fromCharCode(...audio.subarray(i, i + 0x8000))
  return json({ previews: [{
    generated_voice_id: `${uuid}:${accent}`, audio_base_64: btoa(bin), media_type: "audio/mpeg",
  }] })
}
