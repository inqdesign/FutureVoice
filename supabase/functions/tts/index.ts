// TTS proxy + credit gate. Every line is spoken by Cartesia.
//
// Body: { voice_id: string, text: string, with_timestamps?: boolean,
//         stream?: boolean, … } — `model_id`, `previous_text`, `next_text`
// are fields older builds still send for an earlier provider; they are
// accepted and ignored.
// Required header: X-Idempotency-Key (unique per attempt; resent on retry)
//
// stream=true answers raw 16-bit LE mono PCM with `X-Audio-Format: pcm_<rate>`
// — the client REQUIRES that header before treating bytes as PCM.
//
// Charges credits before synthesizing. If the upstream fails AFTER the
// charge, refunds with the same idempotency key so a client retry doesn't
// double-charge.

import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { requireUser, handlePreflight, errorResponse, cors } from "../_shared/auth.ts"
import { restoreCharacters } from "../_shared/calm-exclamations.ts"
import { isPresetSlot, presetVoice } from "../_shared/preset-voices.ts"
import * as cartesia from "../_shared/cartesia.ts"
import { chargePooledTTS, chargeFreePooledTTS, chargeTurnTTSFloored, refund,
         beginScenePlay, enforceRequestRate, insufficientCreditsResponse,
         dailyCapResponse, sceneCapResponse, rateLimitedResponse,
         billingClient } from "../_shared/credits.ts"

// The ledger's name for this function.
const SOURCE_FN = "tts"

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
    // Fields older builds still send for an earlier provider; ignored.
    model_id?: string
    previous_text?: string
    next_text?: string
    // Stable across every line of ONE Watch scene (a per-playback UUID from
    // the client). Present only on `purpose: "scene"`. With it, the scene
    // costs one of the plan's daily scene counts and its seconds stop coming
    // out of the talk allowance; without it — an un-updated app — the scene
    // is metered in seconds against the talk allowance exactly as before.
    scene_key?: string
    // "talk" = this build shows a scene's price as talk minutes, so the claim
    // may charge them (20261019120000). Absent = an older build, metered by
    // the plan's scene count exactly as before.
    scene_billing?: string
    // How fast the fluent self speaks — the learner's choice in Me → Voice,
    // mapped onto Cartesia's speed scale (`cartesiaSpeed`). Absent means normal,
    // which is what every build before 2026-09-23 sends.
    speed?: number
    // The line's language when the app names it (a Korean learner's Hangul
    // line); otherwise read off the script and the learner's target language.
    language_code?: string
    // A Speech script's voiceover ("Hear it in my voice", 2026-10-14). With
    // `purpose: "script-voiceover"` the line is not metered per character:
    // it is claimed against the reservation the app made with
    // `reserve_script_voiceover`, and the whole voiceover is charged once,
    // in talk minutes, by `charge_script_voiceover` after it was made.
    voiceover_key?: string
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
    (isPresetSlot(body.voice_id) || verifiedVoiceOwners.has(ownerKey))
      ? Promise.resolve(null)
      : (async () => {
          // A Cartesia library voice (a Find-people person, a public profile).
          if (await cartesia.isStockVoice(body.voice_id!)) return null
          const { data: owned, error: ownErr } = await billingClient()
            .from("voice_clones")
            .select("id, parked_at")
            .eq("user_id", user.id)
            .eq("voice_id", body.voice_id!)
            .limit(1)
            .maybeSingle()
          if (ownErr) return errorResponse(500, "voice ownership check failed", ownErr.message)
          if (!owned) return errorResponse(403, "voice_id not permitted")
          // PARKED (park-idle-voices): the voice no longer exists upstream
          // because nobody was paying for it. Answered as a spent pool — the
          // same 402 body — so every build, old ones included, shows its
          // paywall instead of an upstream "voice not found". Never cached as
          // verified: the answer changes the day they subscribe.
          // A clone made with an earlier provider is gone the same way:
          // nothing can speak it any more, and the learner's way back is the
          // same rebuild from their recording.
          if ((owned as { parked_at?: string | null }).parked_at || !cartesia.isCartesiaVoice(body.voice_id!)) {
            return new Response(JSON.stringify({ error: "insufficient_credits", reason: "voice_parked" }), {
              status: 402, headers: { "Content-Type": "application/json", ...cors() },
            })
          }
          verifiedVoiceOwners.add(ownerKey)
          return null
        })()

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
  // A script voiceover line rides on its reservation (see the migration
  // `20261014150000_script_voiceover`): timestamped only, a key required, and
  // the line's characters must fit what the reservation covers. Without one
  // it is refused rather than metered, so the tag is never free synthesis.
  const isVoiceover = body.purpose === "script-voiceover"
  if (isVoiceover && (!body.voiceover_key || body.with_timestamps !== true)) {
    return errorResponse(400, "voiceover_key and with_timestamps required")
  }

  // Daily character pooling — credits debit only when the day's running
  // char total crosses a rate boundary, so short lines stop costing a full
  // minimum credit each. Review purposes route through the FREE pool
  // (0 credits inside the daily char budget, paid pooled past it); talk
  // purposes are free under the talk-minute floor. `ch.charged` is this
  // call's exact debit either way.
  const chargeArgs = {
    supabase, userId: user.id, chars: body.text.length,
    sourceFn: SOURCE_FN, idempotencyKey: idemKey,
    // The model that ACTUALLY spoke, so a char count can be costed.
    metadata: { chars: body.text.length, voice_id: body.voice_id,
                purpose: body.purpose ?? null, model_id: cartesia.CARTESIA_MODEL },
  }
  const baseAction = timestamped ? "tts_timestamps" as const : "tts" as const
  let ch: Awaited<ReturnType<typeof chargePooledTTS>>
  if (action === "tts_scene" && body.scene_key) {
    // Watch: claim one of today's scenes BEFORE synthesizing anything. Doing
    // it first means the cap is hit on the line that would have started a
    // third scene, not after we already paid for its audio.
    //
    // The scene path stays SERIAL: a claim has no un-claim, so it must not be
    // taken by a request that then fails the rate or ownership gate — and a
    // scene line is not the latency-critical path the parallel branch below
    // exists for.
    if (!(await ratePromise).ok) return rateLimitedResponse(cors())
    const ownershipFailure = await ownershipPromise
    if (ownershipFailure) return ownershipFailure
    let scenePool: "scene_seconds" | "scene_counted" | "scene_paid" = "scene_seconds"
    const claim = await beginScenePlay({
      supabase, userId: user.id, sceneKey: body.scene_key,
      talk: body.scene_billing === "talk",
    })
    if (!claim.ok) {
      if (claim.reason === "scene_cap") return sceneCapResponse(cors())
      if (claim.reason === "free_scene_cap") return insufficientCreditsResponse(cors())
      if (claim.reason === "talk_spent") return dailyCapResponse(cors())
      return errorResponse(500, "scene claim failed", claim.detail)
    }
    // A scene paid for at its claim (five minutes of talk, or a free
    // account's one sample) spends nothing per line; one paid with a count
    // keeps its seconds off the talk pool; anything else (the admin flag)
    // still owes seconds against the balance.
    if (claim.paid) scenePool = "scene_paid"
    else if (claim.counted) scenePool = "scene_counted"
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
    const chargePromise = isVoiceover
      ? claimVoiceoverLine(user.id, body.voiceover_key!, body.text.length, idemKey)
      : isFreeEntry
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

  const streaming = body.stream === true && !timestamped
  const language = body.language_code ?? cartesia.lineLanguage(body.text, await targetLanguageOf(user.id))
  // A preset slot speaks the language's own Cartesia voice (_shared/preset-voices.ts).
  const voiceId = presetVoice(body.voice_id, language) ?? body.voice_id
  return await noteVoiceoverSeconds(isVoiceover, user.id, body.voiceover_key, await speakOnCartesia({
    // Cartesia gets the line as written: its "!" is +0.6–1.7 dB, not a
    // shout (measured 2026-10-12, en/de/ko/ja).
    voiceId, text: body.text, originalText: body.text, language,
    speed: body.speed, timestamped, streaming, streamFormats: body.stream_formats,
    onFail: async (status: number) => {
      if (ch.ok && ch.charged > 0) {
        await refund({
          supabase, userId: user.id, amount: ch.charged,
          action, sourceFn: SOURCE_FN, originalIdempotencyKey: idemKey,
          metadata: { reason: "upstream_error", status, provider: "cartesia" },
        })
      }
    },
    balanceAfter: ch.balanceAfter,
  }))
})

/** A script voiceover line may be synthesized only under its reservation.
 *  Shaped like a charge so the hot path's gates and refunds treat it alike;
 *  it never charges anything (the voiceover is charged whole, afterwards). */
async function claimVoiceoverLine(userId: string, key: string, chars: number,
                                  idempotencyKey: string) {
  const { data, error } = await billingClient().rpc("claim_script_voiceover_chars", {
    p_user_id: userId, p_key: key, p_chars: chars,
  })
  if (error) return { ok: false as const, reason: "db_error" as const, detail: error.message }
  if (data !== true) {
    return { ok: false as const, reason: "insufficient_credits" as const, detail: "voiceover_not_reserved" }
  }
  return { ok: true as const, balanceAfter: -1, charged: 0, idempotencyKey }
}

/** Records how many seconds of audio a voiceover line came out as — the
 *  server's own measure, which `charge_script_voiceover` charges at least.
 *  Read off the alignment's last character; a failure records nothing (the
 *  app's own measure then stands) and never changes the reply. */
async function noteVoiceoverSeconds(isVoiceover: boolean, userId: string,
                                    key: string | undefined, resp: Response): Promise<Response> {
  if (!isVoiceover || !key || !resp.ok) return resp
  try {
    const json = await resp.clone().json()
    const a = json?.alignment ?? json?.normalized_alignment
    const ends: number[] = a?.character_end_times_seconds ?? []
    const seconds = ends.length ? Math.max(...ends) : 0
    if (seconds > 0) {
      await billingClient().rpc("note_script_voiceover_seconds", {
        p_user_id: userId, p_key: key, p_seconds: seconds,
      })
    }
  } catch { /* the reply stands */ }
  return resp
}

// The learner's target language, remembered per edge instance — it names the
// language of every Cartesia line that isn't in Hangul or kana. A miss reads
// `profiles` once; a failure falls back to English (lineLanguage).
// Ten minutes, so a learner who switches language is heard in the new one soon.
const targetLanguages = new Map<string, { lang: string | null; at: number }>()
async function targetLanguageOf(userId: string): Promise<string | null> {
  const hit = targetLanguages.get(userId)
  if (hit && Date.now() - hit.at < 10 * 60_000) return hit.lang
  const { data } = await billingClient().from("profiles")
    .select("target_language").eq("id", userId).maybeSingle()
  const lang = (data as { target_language?: string | null } | null)?.target_language ?? null
  targetLanguages.set(userId, { lang, at: Date.now() })
  return lang
}

/** A line, answered in the shapes every build reads — streamed PCM with
 *  `X-Audio-Format`, an MP3, or the `/with-timestamps` JSON. */
async function speakOnCartesia(o: {
  voiceId: string; text: string; originalText: string; language: string
  speed?: number; timestamped: boolean; streaming: boolean; streamFormats?: string[]
  onFail: (status: number) => Promise<void>; balanceAfter: number
}): Promise<Response> {
  const line = await cartesia.withDefaultAccent({ voiceId: o.voiceId, text: o.text, language: o.language, speed: o.speed })
  const headers = new Headers(cors())
  headers.set("X-Credits-Balance", String(o.balanceAfter))
  headers.set("X-Voice-Provider", "cartesia")

  if (o.timestamped) {
    const r = await cartesia.synthesizeWithTimestamps(line)
    if (!r.ok) {
      await o.onFail(r.status)
      return errorResponse(r.status >= 400 ? r.status : 502, "cartesia upstream error", r.detail)
    }
    // The alignment spells the text the app SENT (its "!" included).
    if (o.text !== o.originalText) {
      const a = r.json.alignment as { characters: string[] } | undefined
      if (a) restoreCharacters(a.characters, o.originalText, o.text)
    }
    headers.set("Content-Type", "application/json")
    return new Response(JSON.stringify(r.json), { status: 200, headers })
  }

  if (o.streaming) {
    // The best rate the client offers; every PCM rate it can ask for is one
    // Cartesia makes. No ladder offered = an old build expecting pcm_22050.
    const offered = (o.streamFormats ?? []).filter((f) => /^pcm_(16000|22050|24000|44100)$/.test(f))
    const format = offered[0] ?? "pcm_22050"
    const r = await cartesia.synthesizePcmStream(line, Number(format.slice(4)))
    if (!r.ok || !r.body) {
      await o.onFail(r.status)
      return errorResponse(r.status >= 400 ? r.status : 502, "cartesia upstream error", (await r.text()).slice(0, 500))
    }
    headers.set("Content-Type", "application/octet-stream")
    headers.set("X-Audio-Format", format)
    return new Response(r.body, { status: 200, headers })
  }

  const r = await cartesia.synthesizeMp3(line)
  if (!r.ok || !r.body) {
    await o.onFail(r.status)
    return errorResponse(r.status >= 400 ? r.status : 502, "cartesia upstream error", (await r.text()).slice(0, 500))
  }
  headers.set("Content-Type", "audio/mpeg")
  return new Response(r.body, { status: 200, headers })
}
