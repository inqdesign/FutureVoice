// ElevenLabs TTS proxy + credit gate.
//
// Body: { voice_id: string, text: string, model_id?: string, with_timestamps?: boolean }
// Required header: X-Idempotency-Key (unique per attempt; resent on retry)
//
// Charges credits before forwarding upstream. If ElevenLabs returns an
// error AFTER the charge, refunds with the same idempotency key so a
// client retry doesn't double-charge.

import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { requireUser, handlePreflight, errorResponse, cors } from "../_shared/auth.ts"
import { priceFor, charge, refund, insufficientCreditsResponse } from "../_shared/credits.ts"

const SOURCE_FN = "elevenlabs-tts"

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
    text?: string
    model_id?: string
    with_timestamps?: boolean
  }
  try { body = await req.json() } catch { return errorResponse(400, "invalid json body") }

  if (!body.voice_id || !body.text) {
    return errorResponse(400, "voice_id and text required")
  }

  const apiKey = Deno.env.get("ELEVENLABS_API_KEY")
  if (!apiKey) return errorResponse(500, "server missing ELEVENLABS_API_KEY")

  const action = body.with_timestamps ? "tts_timestamps" : "tts"
  const amount = priceFor(action, { chars: body.text.length })

  const ch = await charge({
    supabase, userId: user.id, action, amount,
    sourceFn: SOURCE_FN, idempotencyKey: idemKey,
    metadata: { chars: body.text.length, voice_id: body.voice_id },
  })
  if (!ch.ok) {
    if (ch.reason === "insufficient_credits" || ch.reason === "no_credit_row") {
      return insufficientCreditsResponse(cors())
    }
    return errorResponse(500, "charge failed", ch.detail)
  }

  const modelId = body.model_id ?? "eleven_turbo_v2_5"
  const path = body.with_timestamps
    ? `/v1/text-to-speech/${body.voice_id}/with-timestamps`
    : `/v1/text-to-speech/${body.voice_id}`

  const upstream = await fetch(`https://api.elevenlabs.io${path}`, {
    method: "POST",
    headers: {
      "xi-api-key": apiKey,
      "Content-Type": "application/json",
      Accept: body.with_timestamps ? "application/json" : "audio/mpeg",
    },
    body: JSON.stringify({
      text: body.text,
      model_id: modelId,
      voice_settings: {
        stability: 0.55,
        similarity_boost: 0.90,
        style: 0.15,
        use_speaker_boost: true,
      },
    }),
  })

  if (!upstream.ok) {
    // Roll back the charge — user didn't actually get audio.
    await refund({
      supabase, userId: user.id, amount,
      action, sourceFn: SOURCE_FN, originalIdempotencyKey: idemKey,
      metadata: { reason: "upstream_error", status: upstream.status },
    })
    const detail = await upstream.text()
    return errorResponse(upstream.status, "elevenlabs upstream error", detail.slice(0, 500))
  }

  const headers = new Headers(cors())
  const contentType = upstream.headers.get("Content-Type") ?? "application/octet-stream"
  headers.set("Content-Type", contentType)
  headers.set("X-Credits-Balance", String(ch.balanceAfter))

  return new Response(upstream.body, { status: 200, headers })
})
