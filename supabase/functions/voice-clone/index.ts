// Voice-clone endpoint: the learner's recording becomes a Cartesia voice,
// mirrored into voice_clones.
//
// Clones cost NOTHING (minutes-native model: the meter is talk minutes and
// nothing else) — churn is bounded by a daily re-clone cap instead, with the
// onboarding window fully exempt: getting a voice the user believes is
// theirs is the entry ticket.

import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { requireUser, handlePreflight, errorResponse, cors } from "../_shared/auth.ts"
import { recordVoiceChange } from "../_shared/voice-changes.ts"
import {
  recordFreeUsage, rateLimitedResponse, billingClient,
  enforceRequestRate,
} from "../_shared/credits.ts"
import * as cartesia from "../_shared/cartesia.ts"

const SOURCE_FN = "voice-clone"

Deno.serve(async (req) => {
  const pre = handlePreflight(req)
  if (pre) return pre
  if (req.method !== "POST") return errorResponse(405, "method not allowed")

  const authed = await requireUser(req, { allowAnonymous: true })
  if (authed instanceof Response) return authed
  const { user, supabase } = authed

  const idemKey = req.headers.get("X-Idempotency-Key")
  if (!idemKey) return errorResponse(400, "missing X-Idempotency-Key header")

  // Free clones (the first, and any within the onboarding day) had no bound
  // at all (2026-10-21). An onboarding re-records a handful of times.
  if (!(await enforceRequestRate({ userId: user.id, sourceFn: SOURCE_FN, limit: 12 })).ok) {
    return rateLimitedResponse(cors())
  }

  const contentType = req.headers.get("Content-Type") ?? ""
  if (!contentType.includes("multipart/form-data")) {
    return errorResponse(400, "expected multipart/form-data")
  }

  const action = "voice_clone" as const
  // The FIRST clone is free — it's the product's entry ticket, not usage —
  // and so are the retakes that immediately follow it. The user only learns
  // whether the clone sounds like THEM one screen later, when they first
  // hear it speak; charging for "that isn't my voice, let me read it again"
  // would price the entry ticket after the fact. Bounded by TIME only —
  // deliberately no attempt cap: the user who needs six takes before the
  // voice sounds like them is exactly the user we can least afford to
  // charge, and the window alone keeps this from being a free-clone faucet.
  // Re-records after it (Me → Voice) pay the full price.
  //
  // "First" = no voice_clone row in the ledger yet. Every free clone stamps
  // a 0-credit row AFTER upstream success, so a failed attempt stays free on
  // retry and the window is anchored to a clone the user actually got.
  const ONBOARDING_GRACE_MS = 24 * 60 * 60 * 1000
  const { data: priorClones } = await supabase
    .from("usage_ledger")
    .select("created_at")
    .eq("user_id", user.id)
    .eq("action", action)
    // Debits only — a refunded failed clone also writes a voice_clone row,
    // and it must not move the anchor.
    .eq("kind", "debit")
    .order("created_at", { ascending: true })
    .limit(1)
  const firstCloneAt = priorClones?.[0]?.created_at
    ? Date.parse(priorClones[0].created_at as string)
    : null
  const isFirstClone = firstCloneAt === null
  const withinOnboardingGrace =
    firstCloneAt !== null && Number.isFinite(firstCloneAt) &&
    Date.now() - firstCloneAt < ONBOARDING_GRACE_MS
  const isFree = isFirstClone || withinOnboardingGrace

  // Cartesia keeps clones without a limit, so there is no monthly voice
  // allowance and no 30-day change limit.

  // Minutes-native model: clones are never PRICED — the meter is talk
  // minutes and nothing else. Re-clones past the onboarding window are
  // bounded by a daily cap instead: the accent/retake flow needs a handful,
  // a faucet needs more. (The cap row stamps this attempt's idempotency key
  // BEFORE upstream, so a failed upstream burns one slot — acceptable for
  // an abuse bound.)
  // A voice that was PARKED (park-idle-voices) comes back only to someone
  // with something to spend it on. Without this, "re-record" in Me would
  // mint, free, the exact slot the sweep just gave back. A brand-new account
  // has no parked row and is never refused. Same 402 body as a spent pool, so
  // every build shows its paywall. Fails OPEN on a lookup error — refusing a
  // paying learner their voice is worse than one slot held a little longer.
  {
    const { data: allowed, error: allowErr } = await billingClient()
      .rpc("voice_clone_allowed", { p_user_id: user.id })
    if (!allowErr && allowed === false) {
      return new Response(JSON.stringify({ error: "insufficient_credits", reason: "voice_parked" }), {
        status: 402, headers: { "Content-Type": "application/json", ...cors() },
      })
    }
  }

  if (!isFree) {
    const rec = await recordFreeUsage({
      supabase, userId: user.id, action, purpose: "voice_clone",
      // Cartesia keeps clones without a limit and charges nothing for one,
      // so the cap is only a runaway guard (it was 5 under the old provider's
      // slot economy, and left a learner trying accents on a spinner,
      // 2026-10-12).
      dailyCap: 30, sourceFn: SOURCE_FN, idempotencyKey: idemKey,
      metadata: { reclone: true },
    })
    if (!rec.ok) {
      if (rec.reason === "rate_limited") return rateLimitedResponse(cors())
      return errorResponse(500, "usage record failed", rec.detail)
    }
  }
  let balanceAfter = -1
  {
    const { data: row } = await supabase
      .from("user_credits").select("balance").eq("user_id", user.id).maybeSingle()
    balanceAfter = row?.balance ?? -1
  }

  const incoming = await req.formData()

  // Mirrored into voice_clones below. The name is otherwise known only to
  // the voice provider and to the device that chose it, so nothing on our
  // side could say which user a voice in the library belongs to.
  const voiceName = ((incoming.get("name") as string | null) ?? "").trim() || null

  // One clip — the take the phone recorded (the app sends one file), cleaned
  // on the phone by builds from 2026-10-15. Its language is the learner's
  // target: the read-aloud script is written in it.
  const clip = incoming.getAll("files").find((v): v is File => v instanceof File)
  if (!clip) return errorResponse(400, "no recording in files")
  // The app sends the target language (builds from 2026-11-15). The
  // profile is only the fallback for older builds: a NEW account's row still
  // holds the column default `en` at this moment (the setup is mirrored after
  // the session exists), so every new voice was made as English whatever was
  // read or learned.
  const sent = ((incoming.get("language") as string | null) ?? "").trim()
  let language: string
  if (sent) {
    language = cartesia.lineLanguage("", sent)
  } else {
    const { data: profile } = await billingClient().from("profiles")
      .select("target_language").eq("id", user.id).maybeSingle()
    language = cartesia.lineLanguage("", (profile as { target_language?: string } | null)?.target_language)
  }
  const made = await cartesia.cloneVoice(clip, voiceName ?? `Future ${user.id.slice(0, 8)}`, language)
  if (!made.ok) return errorResponse(made.status >= 400 ? made.status : 502, "cartesia upstream error", made.detail)
  const json = { voice_id: made.voiceId }

  // Free clone: stamp a 0-credit ledger row NOW (post-success) — the first
  // one anchors the grace window, the rest keep usage analytics honest about
  // what actually ran. Keyed per user for the first (idempotent), per
  // attempt for retakes.
  if (isFree) {
    await billingClient().rpc("charge_credits", {
      p_user_id: user.id,
      p_credits: 0,
      p_action: action,
      p_source_fn: SOURCE_FN,
      p_idempotency_key: isFirstClone ? `first-clone:${user.id}` : `free-clone:${idemKey}`,
      p_metadata: isFirstClone
        ? { free_first_clone: true }
        : { free_onboarding_retake: true },
    })
  }

  // Deactivate prior active clones so the partial unique index accepts
  // the new row.
  await supabase
    .from("voice_clones")
    .update({ is_active: false })
    .eq("user_id", user.id)
    .eq("is_active", true)

  const { error: insErr } = await supabase
    .from("voice_clones")
    .insert({
      user_id: user.id,
      voice_id: json.voice_id,
      is_active: true,
      name: voiceName,
    })
  if (insErr) console.error("voice_clones insert failed", insErr)
  if (isFirstClone) await recordVoiceChange(user.id, "first")

  // The recording is NOT kept on our side (2026-11-06, founder): the
  // multipart body is sent upstream and forgotten. The only copies are the
  // learner's own: the phone's VoiceSampleStore and, with sync on, their own
  // iCloud / Google Drive.

  return new Response(JSON.stringify(json), {
    status: 200,
    headers: {
      "Content-Type": "application/json",
      "X-Credits-Balance": String(balanceAfter),
      ...cors(),
    },
  })
})
