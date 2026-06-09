// ElevenLabs TTS proxy.
//
// Body: { voice_id: string, text: string, model_id?: string, with_timestamps?: boolean }
//
// Responses:
//   - with_timestamps=false (default): audio/mpeg binary
//   - with_timestamps=true: ElevenLabs JSON ({ audio_base64, alignment, ... })
//
// We replace the iOS-side `xi-api-key` header with the server-side one read
// from Deno env (set via `supabase secrets set ELEVENLABS_API_KEY=...`).
// The iOS app never sees the real key.

import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { requireUser, handlePreflight, errorResponse, cors } from "../_shared/auth.ts"

Deno.serve(async (req) => {
  const pre = handlePreflight(req)
  if (pre) return pre
  if (req.method !== "POST") return errorResponse(405, "method not allowed")

  const authed = await requireUser(req)
  if (authed instanceof Response) return authed

  let body: {
    voice_id?: string
    text?: string
    model_id?: string
    with_timestamps?: boolean
  }
  try {
    body = await req.json()
  } catch {
    return errorResponse(400, "invalid json body")
  }

  if (!body.voice_id || !body.text) {
    return errorResponse(400, "voice_id and text required")
  }

  const apiKey = Deno.env.get("ELEVENLABS_API_KEY")
  if (!apiKey) return errorResponse(500, "server missing ELEVENLABS_API_KEY")

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
    const detail = await upstream.text()
    return errorResponse(upstream.status, "elevenlabs upstream error", detail.slice(0, 500))
  }

  // Stream the response body straight through. For audio/mpeg this avoids
  // buffering 100KB+ of MP3 in function memory; for JSON it's just normal
  // forwarding.
  const headers = new Headers(cors())
  const contentType = upstream.headers.get("Content-Type") ?? "application/octet-stream"
  headers.set("Content-Type", contentType)

  return new Response(upstream.body, { status: 200, headers })
})
