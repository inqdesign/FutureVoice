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
import { chargePooledTTS, chargeFreePooledTTS, chargeTurnTTSFloored, refund,
         beginScenePlay, enforceRequestRate, insufficientCreditsResponse,
         dailyCapResponse, sceneCapResponse, rateLimitedResponse,
         billingClient } from "../_shared/credits.ts"

const SOURCE_FN = "elevenlabs-tts"

// Which ElevenLabs model the client may request. The fidelity model bills ~2x
// per char upstream at the SAME price to us, so a client sending it on every
// turn doubles our cost — allowlist it only to the purposes that are meant to
// use it (scenes + the onboarding entry lines, both cached or once-per-user).
const CONVERSATION_MODEL = "eleven_turbo_v2_5"
const FIDELITY_MODEL = "eleven_multilingual_v2"
const FLASH_MODEL = "eleven_flash_v2_5"
const ALLOWED_MODELS = new Set([CONVERSATION_MODEL, FIDELITY_MODEL, FLASH_MODEL])
const FIDELITY_PURPOSES = new Set(["scene", "greeting", "voice_comparison"])

// The four counterpart preset voices (VoicePreset.catalog). A caller may only
// synthesize with one of these OR their own cloned voice — never a voice_id
// that belongs to another user.
const PRESET_VOICE_IDS = new Set([
  "NDTYOmYEjbDIVCKB35i3", "UgBBYS2sOqTuMpoF3BR0",
  "FF59babHL8N8gfTgtBMT", "L0Dsvb3SLTyegXwtm47J",
])

// Idempotency-proof hourly backstop (see enforceRequestRate) — above a heavy
// hour of talk turns + scene lines.
const HOURLY_REQUEST_LIMIT = 900

// REVIEW surfaces synthesize free (2026-08 free-learning-loop change): short
// lines, cached forever client-side after first synthesis, and their material
// only exists as the output of metered talk/scene activity — so the volume is
// structurally bounded. Each call still burns the user's daily free-char pool
// (charge_tts_free_pooled) and falls through to the PAID pooled charge past
// it, which is what makes spoofing one of these tags pointless. Metered
// purposes (turn / scene / opener) never touch the free pool.
const FREE_PURPOSES = new Set([
  "drill",          // SRS card + enrichment example playback
  "library",        // vocabulary / expressions dictionaries
  "shadow",         // first synthesis of a shadow line (with timestamps)
  "voice_preview",  // counterpart preset voice preview
  "daily-call",     // voicemail — the retention hook is on us, not the user
])

// TALK surfaces meter by wall-clock call time (talk-tick), so their TTS is
// free under a chars-per-talk-minute floor (charge_turn_tts_floored) — the
// floor is what makes under-reporting call time pointless. Includes the
// free-talk greeting prewarm, which the floor's 2-minute grace covers.
const TALK_PURPOSES = new Set(["turn", "opener"])

// Highest streaming PCM format known to work on this ElevenLabs plan, learned
// by probing (pcm_44100 is Pro-tier; lower rates are open to all). Instance
// memory only — a cold start re-probes once. Set ONLY from ladder requests,
// so a legacy pcm_22050-only call can never pin new clients to 22.05 kHz.
let cachedStreamFormat: string | null = null

// Verified (user, voice) ownership pairs, remembered per edge instance so the
// ownership check below adds a DB round-trip at most ONCE per warm instance
// rather than on every conversation turn (the latency-critical path). A pair
// is only ever added after a positive DB check; a cold start re-verifies once.
const verifiedVoiceOwners = new Set<string>()

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
    // Surrounding lines of a longer stretch of speech. Forwarded upstream to
    // condition prosody so consecutive lines flow as one conversation instead
    // of a series of standalone utterances. NOT spoken, and NOT billed — the
    // charge below stays on `text` alone, which is what ElevenLabs prices.
    previous_text?: string
    next_text?: string
    // Stable across every line of ONE Watch scene (a per-playback UUID from
    // the client). Present only on `purpose: "scene"`. With it, the scene
    // costs one of the plan's daily scene counts and its seconds stop coming
    // out of the talk allowance; without it — an un-updated app — the scene
    // is metered in seconds against the talk allowance exactly as before.
    scene_key?: string
  }
  try { body = await req.json() } catch { return errorResponse(400, "invalid json body") }

  if (!body.voice_id || !body.text) {
    return errorResponse(400, "voice_id and text required")
  }

  // Idempotency-proof hourly backstop, before any upstream spend.
  const rate = await enforceRequestRate({
    userId: user.id, sourceFn: SOURCE_FN, limit: HOURLY_REQUEST_LIMIT,
  })
  if (!rate.ok) return rateLimitedResponse(cors())

  // Voice ownership: a caller may synthesize only with a counterpart preset or
  // their OWN cloned voice. Without this, anyone who learns another user's
  // voice_id can speak arbitrary text in that person's cloned voice — a
  // deepfake primitive against our users' biometric data.
  const ownerKey = `${user.id}:${body.voice_id}`
  if (!PRESET_VOICE_IDS.has(body.voice_id) && !verifiedVoiceOwners.has(ownerKey)) {
    const { data: owned, error: ownErr } = await billingClient()
      .from("voice_clones")
      .select("id")
      .eq("user_id", user.id)
      .eq("elevenlabs_voice_id", body.voice_id)
      .limit(1)
      .maybeSingle()
    if (ownErr) return errorResponse(500, "voice ownership check failed", ownErr.message)
    if (!owned) return errorResponse(403, "voice_id not permitted")
    verifiedVoiceOwners.add(ownerKey)
  }

  // Model allowlist: the fidelity model costs ~2x upstream at the SAME price to
  // us, so it's reserved for the purposes meant to use it (scenes + once-per-
  // user entry lines, all cached). A fidelity request on any other purpose is
  // silently DOWNGRADED to the conversation model rather than rejected — that
  // holds the cost line without breaking the DEBUG turns-on-fidelity A/B, which
  // sends purpose "turn". An entirely unknown model id is still a 400.
  const clientModel = body.model_id ?? CONVERSATION_MODEL
  if (!ALLOWED_MODELS.has(clientModel)) {
    return errorResponse(400, "unsupported model_id")
  }
  const requestedModel =
    clientModel === FIDELITY_MODEL && !FIDELITY_PURPOSES.has(body.purpose ?? "")
      ? CONVERSATION_MODEL
      : clientModel

  const apiKey = Deno.env.get("ELEVENLABS_API_KEY")
  if (!apiKey) return errorResponse(500, "server missing ELEVENLABS_API_KEY")

  const timestamped = body.with_timestamps === true
  // Watch scenes meter by playback time — a dedicated pooled action whose
  // rate makes ~1 min of scene audio ≈ 4.5 cr, the same scale as a talk
  // minute. Scenes never use the timestamps endpoint; if one ever did, it
  // falls back to the normal timestamps price.
  const action = timestamped ? "tts_timestamps"
    : body.purpose === "scene" ? "tts_scene"
    : "tts"
  // Onboarding greeting is free: it's the clone's first words, part of the
  // product's entry experience — not usage. Length-capped so the tag can't
  // be abused to smuggle real synthesis for free.
  const isFreeGreeting = body.purpose === "greeting" && body.text.length <= 120
  // Judging the clone is free for the same reason. "Doesn't sound like you?"
  // plays the opening the learner just read, in the clone's voice, beside
  // their own recording — the only honest way to answer "is this me?", and
  // the answer decides whether they re-record. A hard paywall in front of it
  // charges for the entry ticket after the fact, and it lands on precisely
  // the user who suspects the voice isn't theirs. Same length cap as the
  // greeting (the client cuts at ~160 chars — VoiceCloneScript
  // .comparisonOpening) and the result is cached client-side per line+voice,
  // so this is one synthesis per voice, ever.
  const isFreeVoiceCheck = body.purpose === "voice_comparison" && body.text.length <= 200
  const isFreeEntry = isFreeGreeting || isFreeVoiceCheck

  // Daily character pooling — credits debit only when the day's running
  // char total crosses a rate boundary, so short lines stop costing a full
  // minimum credit each. Review purposes route through the FREE pool
  // (0 credits inside the daily char budget, paid pooled past it); talk
  // purposes are free under the talk-minute floor. `ch.charged` is this
  // call's exact debit either way.
  const chargeArgs = {
    supabase, userId: user.id, chars: body.text.length,
    sourceFn: SOURCE_FN, idempotencyKey: idemKey,
    // `model_id` is the one field that turns characters into money: the
    // fidelity model bills ~2x per character upstream, so a char count
    // without it cannot be costed. It records the model we ACTUALLY used —
    // after the fidelity downgrade above — never what the client asked for.
    metadata: { chars: body.text.length, voice_id: body.voice_id,
                purpose: body.purpose ?? null, model_id: requestedModel },
  }
  // Watch: claim one of today's scenes BEFORE synthesizing anything. Doing
  // it first means the cap is hit on the line that would have started a
  // third scene, not after we already paid ElevenLabs for it.
  let scenePool: "scene_seconds" | "scene_counted" = "scene_seconds"
  if (action === "tts_scene" && body.scene_key) {
    const claim = await beginScenePlay({
      supabase, userId: user.id, sceneKey: body.scene_key,
    })
    if (!claim.ok) {
      if (claim.reason === "scene_cap") return sceneCapResponse(cors())
      return errorResponse(500, "scene claim failed", claim.detail)
    }
    // Only an entitled user's scene was paid for with a count; a free user's
    // scene still owes seconds against their balance.
    if (claim.counted) scenePool = "scene_counted"
  }

  const baseAction = timestamped ? "tts_timestamps" as const : "tts" as const
  const ch = isFreeEntry
    ? { ok: true as const, balanceAfter: -1, charged: 0, idempotencyKey: idemKey }
    : FREE_PURPOSES.has(body.purpose ?? "")
    ? await chargeFreePooledTTS({ ...chargeArgs, action: baseAction })
    : action === "tts_scene"
    ? await chargePooledTTS({ ...chargeArgs, action: "tts_scene", pool: scenePool })
    : TALK_PURPOSES.has(body.purpose ?? "")
    ? await chargeTurnTTSFloored({ ...chargeArgs, action: baseAction })
    : await chargePooledTTS({ ...chargeArgs, action: baseAction })
  if (!ch.ok) {
    if (ch.reason === "insufficient_credits" || ch.reason === "no_credit_row") {
      return insufficientCreditsResponse(cors())
    }
    if (ch.reason === "daily_cap") {
      return dailyCapResponse(cors())
    }
    return errorResponse(500, "charge failed", ch.detail)
  }

  const modelId = requestedModel
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
      // Omitted entirely when absent — sending empty strings would tell the
      // model "silence preceded this", which is worse than saying nothing.
      ...(body.previous_text ? { previous_text: body.previous_text } : {}),
      ...(body.next_text ? { next_text: body.next_text } : {}),
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
        // optimize_streaming_latency=3 — the strongest level that leaves the
        // text normalizer ON (4 turns it off, and normalization errors are
        // audible in a cloned voice). Streaming is the live call's path and
        // its first byte is what the learner is waiting on; the buffered path
        // below deliberately doesn't send this, fidelity surfaces don't race.
        `https://api.elevenlabs.io/v1/text-to-speech/${body.voice_id}/stream?output_format=${format}&optimize_streaming_latency=3`,
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
