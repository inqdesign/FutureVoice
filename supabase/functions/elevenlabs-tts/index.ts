// ElevenLabs TTS proxy + credit gate.
//
// Body: { voice_id: string, text: string, model_id?: string,
//         with_timestamps?: boolean, stream?: boolean }
// Required header: X-Idempotency-Key (unique per attempt; resent on retry)
//
// stream=true hits the /stream endpoint with output_format=pcm_22050 and
// pipes raw 16-bit LE mono PCM chunks straight through, so the app can start
// playback on the first chunk instead of waiting for the full file. The
// response carries `X-Audio-Format: pcm_22050` — the client REQUIRES that
// header before treating bytes as PCM, so an older deployment of this
// function (which ignores `stream`) degrades safely to the buffered MP3 path.
//
// Charges credits before forwarding upstream. If ElevenLabs returns an
// error AFTER the charge, refunds with the same idempotency key so a
// client retry doesn't double-charge.

import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { requireUser, handlePreflight, errorResponse, cors } from "../_shared/auth.ts"
import { chargePooledTTS, refund, insufficientCreditsResponse } from "../_shared/credits.ts"

const SOURCE_FN = "elevenlabs-tts"

// Highest streaming PCM format known to work on this ElevenLabs plan, learned
// by probing (pcm_44100 is Pro-tier; lower rates are open to all). Instance
// memory only — a cold start re-probes once. Set ONLY from ladder requests,
// so a legacy pcm_22050-only call can never pin new clients to 22.05 kHz.
let cachedStreamFormat: string | null = null

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
    stream?: boolean
    // PCM output formats the client can play, best first (e.g.
    // ["pcm_44100", "pcm_24000", "pcm_22050"]). Absent on older builds,
    // which hard-expect pcm_22050 — so absence means exactly that.
    stream_formats?: string[]
    // Client-supplied feature tag ("turn" | "scene" | "shadow" | "drill" |
    // "library" | "greeting" …) — recorded in the ledger metadata so spend
    // can be attributed per feature. Never forwarded upstream, never priced.
    purpose?: string
  }
  try { body = await req.json() } catch { return errorResponse(400, "invalid json body") }

  if (!body.voice_id || !body.text) {
    return errorResponse(400, "voice_id and text required")
  }

  const apiKey = Deno.env.get("ELEVENLABS_API_KEY")
  if (!apiKey) return errorResponse(500, "server missing ELEVENLABS_API_KEY")

  const action = body.with_timestamps ? "tts_timestamps" : "tts"
  // Onboarding greeting is free: it's the clone's first words, part of the
  // product's entry experience — not usage. Length-capped so the tag can't
  // be abused to smuggle real synthesis for free.
  const isFreeGreeting = body.purpose === "greeting" && body.text.length <= 120

  // Daily character pooling — credits debit only when the day's running
  // char total crosses a 100-char boundary, so short lines stop costing a
  // full minimum credit each. `ch.charged` is this call's exact debit.
  const ch = isFreeGreeting
    ? { ok: true as const, balanceAfter: -1, charged: 0, idempotencyKey: idemKey }
    : await chargePooledTTS({
        supabase, userId: user.id, action, chars: body.text.length,
        sourceFn: SOURCE_FN, idempotencyKey: idemKey,
        metadata: { chars: body.text.length, voice_id: body.voice_id, purpose: body.purpose ?? null },
      })
  if (!ch.ok) {
    if (ch.reason === "insufficient_credits" || ch.reason === "no_credit_row") {
      return insufficientCreditsResponse(cors())
    }
    return errorResponse(500, "charge failed", ch.detail)
  }

  const modelId = body.model_id ?? "eleven_turbo_v2_5"
  const streaming = body.stream === true && !body.with_timestamps

  const fetchOptions: RequestInit = {
    method: "POST",
    headers: {
      "xi-api-key": apiKey,
      "Content-Type": "application/json",
      Accept: body.with_timestamps ? "application/json"
        : streaming ? "application/octet-stream"
        : "audio/mpeg",
    },
    body: JSON.stringify({
      text: body.text,
      model_id: modelId,
      voice_settings: {
        stability: 0.55,
        similarity_boost: 0.90,
        // style MUST stay 0 for cloned voices. Any style exaggeration > 0
        // pushes the model away from the reference speaker (and adds
        // latency) — it buys performance at the cost of the one thing this
        // product sells: "that sounds like me". We ran 0.15 through
        // TestFlight and users reported the clone not sounding like them.
        style: 0,
        use_speaker_boost: true,
      },
    }),
  }

  let upstream: Response
  let streamFormatUsed = "pcm_22050"
  if (streaming) {
    // Highest PCM rate the client offers that the ElevenLabs plan allows.
    // Tier-locked formats (pcm_44100 needs Pro) come back as an upstream
    // error — walk down the client's ladder until one succeeds. The working
    // format is remembered per edge instance so warm calls don't re-pay the
    // failed round-trip on every turn. Legacy clients (no stream_formats)
    // hard-expect pcm_22050 and never touch the probe or its cache.
    const requested = (body.stream_formats ?? [])
      .filter((f) => typeof f === "string" && /^pcm_(16000|22050|24000|44100)$/.test(f))
    let ladder = requested.length ? requested : ["pcm_22050"]
    const probing = requested.length > 0
    if (probing && cachedStreamFormat && ladder.includes(cachedStreamFormat)) {
      ladder = ladder.slice(ladder.indexOf(cachedStreamFormat))
    }
    let last: Response | null = null
    for (const [i, format] of ladder.entries()) {
      const r = await fetch(
        `https://api.elevenlabs.io/v1/text-to-speech/${body.voice_id}/stream?output_format=${format}`,
        fetchOptions,
      )
      last = r
      if (r.ok) {
        streamFormatUsed = format
        if (probing) cachedStreamFormat = format
        break
      }
      // Not the last rung → drain the error body and try the next format
      // down. (A non-format failure — bad voice id, auth — fails every rung
      // and surfaces through the shared error path below.)
      if (i < ladder.length - 1) await r.text()
    }
    upstream = last!
  } else {
    const path = body.with_timestamps
      ? `/v1/text-to-speech/${body.voice_id}/with-timestamps`
      : `/v1/text-to-speech/${body.voice_id}`
    upstream = await fetch(`https://api.elevenlabs.io${path}`, fetchOptions)
  }

  if (!upstream.ok) {
    // Roll back this call's exact debit — user didn't actually get audio.
    // (The pooled chars stay accumulated; a rare failed call's characters
    // at most pull the next boundary crossing slightly earlier.)
    if (ch.charged > 0) {
      await refund({
        supabase, userId: user.id, amount: ch.charged,
        action, sourceFn: SOURCE_FN, originalIdempotencyKey: idemKey,
        metadata: { reason: "upstream_error", status: upstream.status },
      })
    }
    const detail = await upstream.text()
    return errorResponse(upstream.status, "elevenlabs upstream error", detail.slice(0, 500))
  }

  const headers = new Headers(cors())
  const contentType = upstream.headers.get("Content-Type") ?? "application/octet-stream"
  headers.set("Content-Type", contentType)
  headers.set("X-Credits-Balance", String(ch.balanceAfter))
  if (streaming) headers.set("X-Audio-Format", streamFormatUsed)

  return new Response(upstream.body, { status: 200, headers })
})
