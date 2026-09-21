// ElevenLabs voice-remix proxy — the accent picker.
//
// A clone recorded in the learner's NATIVE language carries no
// target-language accent information, so the TTS model fills that gap with
// its own default (US English for `en`). Remixing lets the learner choose:
// same voice, instructed accent. Two calls, one function, distinguished by
// body shape:
//
//   { voice_id, voice_description, text }
//       → generate remix PREVIEWS (pass-through of upstream previews:
//         [{ audio_base_64, generated_voice_id, … }])
//   { generated_voice_id, voice_name, voice_description }
//       → SAVE the picked preview as a permanent voice → { voice_id }
//
// Free (0 credits) — the accent pick is part of getting a voice the user
// believes is theirs, same logic as the clone's onboarding grace — bounded
// by per-purpose daily caps instead of a price.

import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { requireUser, handlePreflight, errorResponse, cors } from "../_shared/auth.ts"
import { recordFreeUsage, rateLimitedResponse } from "../_shared/credits.ts"

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

  const apiKey = Deno.env.get("ELEVENLABS_API_KEY")
  if (!apiKey) return errorResponse(500, "server missing ELEVENLABS_API_KEY")

  let body: {
    voice_id?: string
    voice_description?: string
    text?: string
    generated_voice_id?: string
    voice_name?: string
    prompt_strength?: number
    guidance_scale?: number
  }
  try { body = await req.json() } catch { return errorResponse(400, "invalid json body") }
  if (!body.voice_description) return errorResponse(400, "voice_description required")
  // How far the remix may drift from the reference audio. Upstream: 0 is
  // "almost no prompt influence", 1 "almost no reference audio influence".
  // For an accent pick the reference IS the product — the learner has to
  // still hear themselves — so the client sends a low value; omitted, the
  // upstream default applies (which is what every accent before 2026-09-18
  // was made with, and is where "it stopped sounding like me" came from).
  if (body.prompt_strength !== undefined
      && !(typeof body.prompt_strength === "number" && body.prompt_strength >= 0 && body.prompt_strength <= 1)) {
    return errorResponse(400, "prompt_strength must be a number in 0...1")
  }
  if (body.guidance_scale !== undefined
      && !(typeof body.guidance_scale === "number" && body.guidance_scale > 0 && body.guidance_scale <= 100)) {
    return errorResponse(400, "guidance_scale must be a number in 0...100")
  }

  // ---- SAVE: promote the picked preview into a permanent voice ------------
  if (body.generated_voice_id) {
    if (!body.voice_name) return errorResponse(400, "voice_name required")

    const free = await recordFreeUsage({
      supabase, userId: user.id, action: "voice_remix", purpose: "accent_save",
      dailyCap: 6, sourceFn: SOURCE_FN, idempotencyKey: idemKey,
      metadata: { generated_voice_id: body.generated_voice_id },
    })
    if (!free.ok) {
      if (free.reason === "rate_limited") return rateLimitedResponse(cors())
      return errorResponse(500, "usage record failed", free.detail)
    }

    const upstream = await fetch("https://api.elevenlabs.io/v1/text-to-voice", {
      method: "POST",
      headers: { "xi-api-key": apiKey, "Content-Type": "application/json" },
      body: JSON.stringify({
        voice_name: body.voice_name,
        voice_description: body.voice_description,
        generated_voice_id: body.generated_voice_id,
      }),
    })
    if (!upstream.ok) {
      const detail = await upstream.text()
      return errorResponse(upstream.status, "elevenlabs upstream error", detail.slice(0, 500))
    }
    const json = await upstream.json() as { voice_id: string }

    // Mirror into voice_clones exactly like a fresh clone: voice-delete and
    // account-delete both authorize against this table, so a remixed voice
    // that isn't mirrored could never be cleaned up.
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
        name: (body.voice_name ?? "").trim() || null,
      })
    if (insErr) console.error("voice_clones insert failed", insErr)

    return new Response(JSON.stringify({ voice_id: json.voice_id }), {
      status: 200,
      headers: { "Content-Type": "application/json", ...cors() },
    })
  }

  // ---- PREVIEWS: only on a voice the caller owns --------------------------
  if (!body.voice_id) return errorResponse(400, "voice_id required")
  if (!body.text || body.text.length < 100 || body.text.length > 1000) {
    return errorResponse(400, "text must be 100-1000 characters")
  }

  const { data: owned } = await supabase
    .from("voice_clones")
    .select("id")
    .eq("user_id", user.id)
    .eq("elevenlabs_voice_id", body.voice_id)
    .maybeSingle()
  if (!owned) return errorResponse(403, "voice not owned by caller")

  const free = await recordFreeUsage({
    supabase, userId: user.id, action: "voice_remix", purpose: "accent_previews",
    dailyCap: 12, sourceFn: SOURCE_FN, idempotencyKey: idemKey,
    metadata: { voice_id: body.voice_id, prompt_strength: body.prompt_strength ?? null },
  })
  if (!free.ok) {
    if (free.reason === "rate_limited") return rateLimitedResponse(cors())
    return errorResponse(500, "usage record failed", free.detail)
  }

  const upstream = await fetch(
    `https://api.elevenlabs.io/v1/text-to-voice/${body.voice_id}/remix`,
    {
      method: "POST",
      headers: { "xi-api-key": apiKey, "Content-Type": "application/json" },
      body: JSON.stringify({
        voice_description: body.voice_description,
        text: body.text,
        output_format: "mp3_44100_128",
        ...(body.prompt_strength !== undefined ? { prompt_strength: body.prompt_strength } : {}),
        ...(body.guidance_scale !== undefined ? { guidance_scale: body.guidance_scale } : {}),
      }),
    },
  )
  if (!upstream.ok) {
    const detail = await upstream.text()
    return errorResponse(upstream.status, "elevenlabs upstream error", detail.slice(0, 500))
  }

  // Pass the previews through untouched — the client decodes
  // { previews: [{ audio_base_64, generated_voice_id, … }] }.
  const passthrough = await upstream.text()
  return new Response(passthrough, {
    status: 200,
    headers: { "Content-Type": "application/json", ...cors() },
  })
})
