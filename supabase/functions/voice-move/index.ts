// Move a learner's voice from ElevenLabs to Cartesia from the SERVER's copy
// of their recording (2026-10-12).
//
// The app's move sheet (VoiceMoveSheet) rebuilds from the recording saved on
// the phone. When the phone has none (a reinstall, another device), the
// recording may still exist upstream: an ElevenLabs instant clone keeps the
// file it was made from as its sample. So this reads the learner's active
// ElevenLabs voice, and if it is a plain clone ("cloned", with a sample)
// downloads that sample, levels it, and clones it on Cartesia — the same
// clone `elevenlabs-voice-clone` makes, minus the upload from the phone.
//
// An accent remix ("generated") carries no recording — only a preview the
// remix made — so it answers 409 `no_original` and the app asks for a new
// recording instead. Body: {} (the active voice is looked up). Returns
// { voice_id } — the new Cartesia voice, already the active row. The old
// ElevenLabs voice is left for the app to delete, as after any rebuild.

import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { requireUser, handlePreflight, errorResponse, cors } from "../_shared/auth.ts"
import { billingClient } from "../_shared/credits.ts"
import * as cartesia from "../_shared/cartesia.ts"
import { MPEGDecoder } from "npm:mpg123-decoder@1.0.3"

Deno.serve(async (req) => {
  const pre = handlePreflight(req)
  if (pre) return pre
  if (req.method !== "POST") return errorResponse(405, "method not allowed")
  const authed = await requireUser(req)
  if (authed instanceof Response) return authed
  const { user, supabase } = authed
  const json = (o: unknown, status = 200) => new Response(JSON.stringify(o), {
    status, headers: { "Content-Type": "application/json", ...cors() },
  })

  const elKey = Deno.env.get("ELEVENLABS_API_KEY")
  if (!elKey) return errorResponse(500, "server missing ELEVENLABS_API_KEY")

  const { data: active } = await supabase.from("voice_clones").select("id, elevenlabs_voice_id, name")
    .eq("user_id", user.id).eq("is_active", true).limit(1)
  const row = (active ?? [])[0] as { id: string; elevenlabs_voice_id: string; name: string | null } | undefined
  if (!row) return errorResponse(404, "no voice")
  if (cartesia.isCartesiaVoice(row.elevenlabs_voice_id)) return json({ voice_id: row.elevenlabs_voice_id })

  // The ElevenLabs voice and the recording it was made from.
  const meta = await fetch(`https://api.elevenlabs.io/v1/voices/${row.elevenlabs_voice_id}`, {
    headers: { "xi-api-key": elKey },
  })
  if (!meta.ok) return json({ error: "no_original", detail: `voice ${meta.status}` }, 409)
  const voice = await meta.json() as {
    category?: string; samples?: { sample_id: string; mime_type?: string; file_name?: string }[] | null
  }
  const sample = (voice.samples ?? [])[0]
  if (voice.category !== "cloned" || !sample) {
    return json({ error: "no_original", detail: voice.category ?? "unknown" }, 409)
  }
  const audio = await fetch(
    `https://api.elevenlabs.io/v1/voices/${row.elevenlabs_voice_id}/samples/${sample.sample_id}/audio`,
    { headers: { "xi-api-key": elKey } })
  if (!audio.ok) return json({ error: "no_original", detail: `sample ${audio.status}` }, 409)
  const bytes = new Uint8Array(await audio.arrayBuffer())

  // ElevenLabs serves the sample as MP3; decode so it can be levelled (a
  // Cartesia clone speaks at its recording's loudness).
  let clip: File
  const isWav = bytes.length > 12 && String.fromCharCode(...bytes.subarray(0, 4)) === "RIFF"
  if (isWav) {
    clip = new File([bytes.slice().buffer as ArrayBuffer], "sample.wav", { type: "audio/wav" })
  } else {
    const decoder = new MPEGDecoder()
    await decoder.ready
    const decoded = decoder.decode(bytes)
    decoder.free()
    if (!decoded.samplesDecoded) return json({ error: "no_original", detail: "undecodable sample" }, 409)
    clip = cartesia.wavFileFromFloat(decoded.channelData, decoded.sampleRate)
  }

  const { data: profile } = await billingClient().from("profiles")
    .select("target_language").eq("id", user.id).maybeSingle()
  const language = cartesia.lineLanguage("", (profile as { target_language?: string } | null)?.target_language)
  const made = await cartesia.cloneVoice(clip, row.name ?? `Future ${user.id.slice(0, 8)}`, language)
  if (!made.ok) return errorResponse(made.status >= 400 ? made.status : 502, "cartesia upstream error", made.detail)

  await supabase.from("voice_clones").update({ is_active: false })
    .eq("user_id", user.id).eq("is_active", true)
  const { error: insErr } = await supabase.from("voice_clones").insert({
    user_id: user.id, elevenlabs_voice_id: made.voiceId, is_active: true, name: row.name,
  })
  if (insErr) console.error("voice_clones insert failed", insErr)
  console.log("voice moved from server copy", { from: row.elevenlabs_voice_id, to: made.voiceId })
  return json({ voice_id: made.voiceId })
})
