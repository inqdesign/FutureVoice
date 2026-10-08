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
import { calmExclamations, restoreCharacters } from "../_shared/calm-exclamations.ts"
import { speakAs, guessAccentLanguage, BUSY } from "../_shared/default-accent.ts"
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
// Languages a client may pin with `language_code`. Korean only: it is the one
// measured by ear (2026-10-05). Add a language only after the same test.
const PINNABLE_LANGUAGES = new Set(["ko"])
const FIDELITY_PURPOSES = new Set(["scene", "greeting", "voice_comparison"])

// The four counterpart preset voices (VoicePreset.catalog). A caller may only
// synthesize with one of these OR their own cloned voice — never a voice_id
// that belongs to another user.
const PRESET_VOICE_IDS = new Set([
  "NDTYOmYEjbDIVCKB35i3", "UgBBYS2sOqTuMpoF3BR0",
  "FF59babHL8N8gfTgtBMT", "L0Dsvb3SLTyegXwtm47J",
  // The same four slots voiced natively for Korean and Japanese learners
  // (VoicePreset.speaking, 2026-09-28): Sian, KO-Calm, Han, Joon.
  "5n5gqmaQi9Ewevrz7bOS", "L4az9Gb378GIycFl2nAB",
  "8jHHF8rMqMlg8if2mOUe", "AKF7f2y1L8ktV5vxXILw",
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
    // How fast the fluent self speaks — the learner's choice in Me → Voice,
    // forwarded to ElevenLabs as `voice_settings.speed`. Absent means normal,
    // which is what every build before 2026-09-23 sends.
    speed?: number
    // Pins the line's language upstream. Sent by the app only for a Korean
    // learner's Hangul line (2026-10-05): a clone recorded in another
    // language read Korean with an accent, and the pinned take was preferred
    // by ear (scripts/tts-korean-probe.sh). Absent = the model guesses, as
    // every build before it does.
    language_code?: string
  }
  try { body = await req.json() } catch { return errorResponse(400, "invalid json body") }

  if (!body.voice_id || !body.text) {
    return errorResponse(400, "voice_id and text required")
  }

  // The daily call's voicemail is never synthesized ahead any more
  // (2026-10-08): 583 takes in 30 days for 46 answered calls, ~$9/month for
  // audio nobody heard. Build 77 stopped asking; older builds still do, so
  // they are refused here, before anything is charged or spent upstream.
  // Every build from 53 on treats a failed take as "no audio": the call still
  // rings (the ring is a bundled tone) and on answer the gateway speaks the
  // script live. Nothing on screen depends on this request.
  if (body.purpose === "daily-call") {
    return new Response(JSON.stringify({ error: "voicemail_spoken_live" }), {
      status: 410, headers: { "Content-Type": "application/json", ...cors() },
    })
  }

  // Idempotency-proof hourly backstop, before any upstream spend. FIRED here,
  // awaited beside the charge below: the rate bump, the ownership check and
  // the charge are three independent DB round trips, and this function sits
  // on the live call's critical path (`tts_first_ms` clocks it per turn) —
  // run serially they cost up to two extra DB RTTs per spoken line.
  // `bump_request_rate` increments unconditionally by design, so firing it
  // early changes nothing about what it counts.
  const ratePromise = enforceRequestRate({
    userId: user.id, sourceFn: SOURCE_FN, limit: HOURLY_REQUEST_LIMIT,
  })

  // Voice ownership: a caller may synthesize only with a counterpart preset or
  // their OWN cloned voice. Without this, anyone who learns another user's
  // voice_id can speak arbitrary text in that person's cloned voice — a
  // deepfake primitive against our users' biometric data.
  //
  // Kicked off concurrently with the rate bump and the charge; the result is
  // awaited before anything is spent upstream or returned to the caller.
  const ownerKey = `${user.id}:${body.voice_id}`
  const ownershipPromise: Promise<Response | null> =
    (PRESET_VOICE_IDS.has(body.voice_id) || verifiedVoiceOwners.has(ownerKey))
      ? Promise.resolve(null)
      : (async () => {
          const { data: owned, error: ownErr } = await billingClient()
            .from("voice_clones")
            .select("id, parked_at")
            .eq("user_id", user.id)
            .eq("elevenlabs_voice_id", body.voice_id!)
            .limit(1)
            .maybeSingle()
          if (ownErr) return errorResponse(500, "voice ownership check failed", ownErr.message)
          if (!owned) return errorResponse(403, "voice_id not permitted")
          // PARKED (park-idle-voices): the voice no longer exists upstream
          // because nobody was paying for it. Answered as a spent pool — the
          // same 402 body — so every build, old ones included, shows its
          // paywall instead of an upstream "voice not found". Never cached as
          // verified: the answer changes the day they subscribe.
          if ((owned as { parked_at?: string | null }).parked_at) {
            return new Response(JSON.stringify({ error: "insufficient_credits", reason: "voice_parked" }), {
              status: 402, headers: { "Content-Type": "application/json", ...cors() },
            })
          }
          verifiedVoiceOwners.add(ownerKey)
          return null
        })()

  // The voice upstream actually speaks with. An old build's plain clone
  // speaks English/German through its default-accent remix (made on its
  // first such line — see _shared/default-accent.ts); everything else is
  // the voice asked for. Started beside the ownership check (it reads only
  // this user's own rows), awaited before the upstream fetch. Never fails.
  const speakAsPromise: Promise<string> = PRESET_VOICE_IDS.has(body.voice_id)
    ? Promise.resolve(body.voice_id)
    : speakAs({
        admin: billingClient(), apiKey: Deno.env.get("ELEVENLABS_API_KEY") ?? "",
        userId: user.id, voiceId: body.voice_id,
        language: body.language_code ?? guessAccentLanguage(body.text),
        create: true,
      })

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
  const baseAction = timestamped ? "tts_timestamps" as const : "tts" as const
  let ch: Awaited<ReturnType<typeof chargePooledTTS>>
  if (action === "tts_scene" && body.scene_key) {
    // Watch: claim one of today's scenes BEFORE synthesizing anything. Doing
    // it first means the cap is hit on the line that would have started a
    // third scene, not after we already paid ElevenLabs for it.
    //
    // The scene path stays SERIAL: a claim has no un-claim, so it must not be
    // taken by a request that then fails the rate or ownership gate — and a
    // scene line is not the latency-critical path the parallel branch below
    // exists for.
    if (!(await ratePromise).ok) return rateLimitedResponse(cors())
    const ownershipFailure = await ownershipPromise
    if (ownershipFailure) return ownershipFailure
    let scenePool: "scene_seconds" | "scene_counted" = "scene_seconds"
    const claim = await beginScenePlay({
      supabase, userId: user.id, sceneKey: body.scene_key,
    })
    if (!claim.ok) {
      if (claim.reason === "scene_cap") return sceneCapResponse(cors())
      if (claim.reason === "free_scene_cap") return insufficientCreditsResponse(cors())
      return errorResponse(500, "scene claim failed", claim.detail)
    }
    // Only an entitled user's scene was paid for with a count; a free user's
    // scene still owes seconds against their balance.
    if (claim.counted) scenePool = "scene_counted"
    ch = await chargePooledTTS({ ...chargeArgs, action: "tts_scene", pool: scenePool })
  } else {
    // Hot path (turn / opener / review): the charge runs CONCURRENTLY with
    // the rate bump and the ownership check — all three depend only on the
    // verified user. A charge that landed ahead of a failed gate is refunded
    // under the same idempotency key, the exact pattern the upstream-error
    // path below already uses; the gates fail only on abuse, so the refund
    // path is cold. The legacy scene call (purpose "scene", no scene_key —
    // an un-updated app) keeps its tts_scene action and seconds pool here,
    // exactly as before.
    const chargePromise = isFreeEntry
      ? Promise.resolve({ ok: true as const, balanceAfter: -1, charged: 0, idempotencyKey: idemKey })
      : FREE_PURPOSES.has(body.purpose ?? "")
      ? chargeFreePooledTTS({ ...chargeArgs, action: baseAction })
      : action === "tts_scene"
      ? chargePooledTTS({ ...chargeArgs, action: "tts_scene", pool: "scene_seconds" })
      : TALK_PURPOSES.has(body.purpose ?? "")
      ? chargeTurnTTSFloored({ ...chargeArgs, action: baseAction })
      : chargePooledTTS({ ...chargeArgs, action: baseAction })
    const rate = await ratePromise
    const ownershipFailure = await ownershipPromise
    ch = await chargePromise
    if (!rate.ok || ownershipFailure) {
      if (ch.ok && ch.charged > 0) {
        await refund({
          supabase, userId: user.id, amount: ch.charged,
          action, sourceFn: SOURCE_FN, originalIdempotencyKey: idemKey,
          metadata: { reason: "precheck_failed" },
        })
      }
      return ownershipFailure ?? rateLimitedResponse(cors())
    }
  }
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
  // The voice is sent "." where the line has "!" — a "!" made it shout
  // (_shared/calm-exclamations.ts). Same length, so nothing else moves.
  const spokenText = calmExclamations(body.text)

  const upstreamVoiceId = await speakAsPromise
  if (upstreamVoiceId === BUSY) {
    // Another line is making this voice's accent remix; nothing was
    // synthesized, so nothing is owed.
    if (ch.ok && ch.charged > 0) {
      await refund({
        supabase, userId: user.id, amount: ch.charged,
        action, sourceFn: SOURCE_FN, originalIdempotencyKey: idemKey,
        metadata: { reason: "default_accent_busy" },
      })
    }
    return errorResponse(503, "voice is being prepared, retry shortly")
  }
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
      text: spokenText,
      model_id: modelId,
      // Omitted entirely when absent — sending empty strings would tell the
      // model "silence preceded this", which is worse than saying nothing.
      ...(body.previous_text ? { previous_text: calmExclamations(body.previous_text) } : {}),
      ...(body.next_text ? { next_text: calmExclamations(body.next_text) } : {}),
      // Allowlisted, and never on multilingual_v2, which refuses the field.
      ...(body.language_code && PINNABLE_LANGUAGES.has(body.language_code) && modelId !== FIDELITY_MODEL
        ? { language_code: body.language_code }
        : {}),
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
        // Clamped, not trusted: outside 0.7–1.2 ElevenLabs refuses the whole
        // request, so a bad value would be a silent line rather than a
        // slightly wrong one. Out of range means "no preference".
        ...(typeof body.speed === "number" && body.speed >= 0.7 && body.speed <= 1.2
          ? { speed: body.speed }
          : {}),
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
        `https://api.elevenlabs.io/v1/text-to-speech/${upstreamVoiceId}/stream?output_format=${format}&optimize_streaming_latency=3`,
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
      ? `/v1/text-to-speech/${upstreamVoiceId}/with-timestamps`
      : `/v1/text-to-speech/${upstreamVoiceId}`
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

  // A timestamped reply spells the line out character by character, and the
  // app draws shadowing words from it — give it back the "!" it sent.
  if (body.with_timestamps && spokenText !== body.text) {
    const json = await upstream.json()
    restoreCharacters(json?.alignment?.characters, body.text, spokenText)
    restoreCharacters(json?.normalized_alignment?.characters, body.text, spokenText)
    return new Response(JSON.stringify(json), { status: 200, headers })
  }

  return new Response(upstream.body, { status: 200, headers })
})
