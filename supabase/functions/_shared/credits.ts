// Metering helpers shared by every Edge Function that touches billing.
//
// THE UNIT IS SECONDS OF SYNTHESIZED TALK (2026-08 minutes-native change —
// `user_credits.balance` holds seconds; "credits" survives only in table /
// RPC / field NAMES so deployed clients keep working). Who pays what:
//   * Subscribers consume their plan's per-day allowance
//     (subscription_plans.daily_seconds) — no balance, resets at midnight
//     UTC. Past it: DAILY_CAP_REACHED → 402 "daily_cap_reached".
//   * Free users debit a one-time seconds pool (signup grant 3960 s).
//     Spent: INSUFFICIENT_CREDITS → 402 "insufficient_credits" → paywall.
//   * Everything that isn't Talk minutes or Watch scene audio is FREE,
//     bounded by daily caps (recordFreeUsage / free char pools).
//
// Each provider call follows this pattern:
//   1. charge — atomic DB debit / allowance consume. On 402, stop.
//   2. invoke upstream provider (ElevenLabs / Gemini)
//   3. if upstream failed, refund() with the same idempotency key
//   4. return result to client
//
// Idempotency keys are required so client retries don't double-charge.
// Convention: hash(user_id + action + relevant_params + nonce) where nonce
// is supplied by the client per-attempt. The client-side networking layer
// generates one nonce per request and resends it on retry.

import { createClient, type SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.45.0"

export type ChargeableAction =
  | "tts"               // per ElevenLabs synthesis (no timestamps)
  | "tts_timestamps"    // with-timestamps endpoint (slightly more expensive)
  | "tts_scene"         // Watch scene lines — priced by playback time (~850 chars ≈ 1 min ≈ 4.5 cr)
  | "talk_time"         // wall-clock call seconds (talk-tick) — 4.5 cr/min
  | "voice_clone"       // /v1/voices/add — one-shot
  | "voice_delete"      // free — but we charge 0 so we get a ledger row
  | "voice_remix"       // accent remix (previews + save) — free, daily-capped
  | "gemini"            // generateContent
  | "gemini_summary"    // summary at end of session — same engine, separate tag
  | "gemini_weekly"     // weekly report
  | "gemini_enrichment" // drill enrichment
  | "gemini_transcribe" // verbatim transcript of one spoken turn (flash-lite)

/**
 * Returns the SECONDS-of-talk cost for a given action + parameters. Only the
 * pooled SQL functions do real pricing now (chars → seconds at 850 chars ≈
 * 60 s); this exists for the few call sites that still ask.
 */
export function priceFor(action: ChargeableAction, params: Record<string, unknown> = {}): number {
  switch (action) {
    case "tts": {
      const chars = typeof params.chars === "number" ? params.chars : 150
      return Math.max(1, Math.ceil((chars * 706) / 10000))
    }
    case "tts_timestamps": {
      const chars = typeof params.chars === "number" ? params.chars : 150
      return Math.max(1, Math.ceil((chars * 706) / 10000))
    }
    case "tts_scene": {
      // Playback-time rate: ~850 chars ≈ 60 s of speech.
      const chars = typeof params.chars === "number" ? params.chars : 850
      return Math.max(1, Math.ceil((chars * 706) / 10000))
    }
    // Priced inside charge_talk_seconds (1 s of call = 1 s) — never
    // through priceFor.
    case "talk_time":       return 0
    // Free since the minutes-native change: the meter is talk minutes and
    // nothing else. Re-clone churn is bounded by a daily cap in
    // elevenlabs-voice-clone instead of a price.
    case "voice_clone":     return 0
    case "voice_delete":    return 0
    // Free by the same logic as the clone's onboarding grace: the accent pick
    // is part of getting a voice the user believes is theirs, not usage.
    // Bounded by recordFreeUsage daily caps in elevenlabs-voice-remix.
    case "voice_remix":     return 0
    // Every Gemini action is FREE since 2026-08 (the free-learning-loop
    // change): upstream cost is ~$0.002/call vs the 1 credit (~$0.04) we
    // charged, and the per-click charge was measurably scaring users out of
    // review and exploration. Abuse is bounded by per-purpose daily request
    // caps (recordFreeUsage) instead of prices. Ledger rows keep being
    // written at 0 so per-feature attribution survives.
    case "gemini":          return 0
    case "gemini_summary":  return 0
    case "gemini_weekly":   return 0
    case "gemini_enrichment": return 0
    case "gemini_transcribe": return 0
  }
}

/**
 * Record a free (0-credit) call against the caller's per-purpose daily cap
 * (the `record_free_usage` SQL function). Writes the 0-delta ledger row for
 * attribution; raises past the cap. Rate-capped, never priced.
 */
export async function recordFreeUsage(opts: {
  supabase: SupabaseClient
  userId: string
  action: ChargeableAction
  purpose: string
  dailyCap: number
  sourceFn: string
  idempotencyKey: string
  metadata?: Record<string, unknown>
}): Promise<{ ok: true } | { ok: false; reason: "rate_limited" | "db_error"; detail?: string }> {
  const { supabase, userId, action, purpose, dailyCap, sourceFn, idempotencyKey, metadata } = opts
  const { error } = await billingClient().rpc("record_free_usage", {
    p_user_id: userId,
    p_action: action,
    p_purpose: purpose,
    p_source_fn: sourceFn,
    p_idempotency_key: idempotencyKey,
    p_metadata: metadata ?? null,
    p_daily_cap: dailyCap,
  })
  if (error) {
    if (error.message?.includes("RATE_LIMITED")) {
      return { ok: false, reason: "rate_limited", detail: error.message }
    }
    return { ok: false, reason: "db_error", detail: error.message }
  }
  return { ok: true }
}

/**
 * TTS charge for REVIEW surfaces (drill / library / shadow / previews /
 * voicemail): free inside a daily char budget, falling through to the normal
 * paid pooled charge past it (`charge_tts_free_pooled`). The fall-through is
 * what keeps `purpose` spoofing pointless — a client tagging conversation
 * audio as "drill" gains at most the daily budget. `charged` is this call's
 * exact debit (0 while free) — refund it if upstream fails.
 */
export async function chargeFreePooledTTS(opts: {
  supabase: SupabaseClient
  userId: string
  action: "tts" | "tts_timestamps"
  chars: number
  sourceFn: string
  idempotencyKey: string
  metadata?: Record<string, unknown>
}): Promise<ChargeResult | ChargeError> {
  const { supabase, userId, action, chars, sourceFn, idempotencyKey, metadata } = opts
  const { data, error } = await billingClient().rpc("charge_tts_free_pooled", {
    p_user_id: userId,
    p_chars: chars,
    p_action: action,
    p_source_fn: sourceFn,
    p_idempotency_key: idempotencyKey,
    p_metadata: metadata ?? null,
  })
  if (error) {
    if (error.message?.includes("INSUFFICIENT_CREDITS")) {
      await recordDepletion(userId, sourceFn)
      return { ok: false, reason: "insufficient_credits", detail: error.message }
    }
    if (error.message?.includes("DAILY_CAP_REACHED")) {
      return { ok: false, reason: "daily_cap", detail: error.message }
    }
    if (error.message?.includes("NO_CREDIT_ROW")) {
      return { ok: false, reason: "no_credit_row", detail: error.message }
    }
    return { ok: false, reason: "db_error", detail: error.message }
  }
  const parsed = data as { balance?: number; charged?: number }
  return {
    ok: true,
    balanceAfter: parsed?.balance ?? -1,
    charged: parsed?.charged ?? 0,
    idempotencyKey,
  }
}

/**
 * TTS charge for TALK surfaces (turn / opener): free while the day's chars
 * stay under the chars-per-talk-minute floor tied to `talk-tick` seconds
 * (`charge_turn_tts_floored`) — the audio is covered by the ticking minutes.
 * Past the floor (a client feeding TTS while under-reporting call time) the
 * whole call falls through to the paid pooled charge. `charged` is this
 * call's exact debit (0 while free) — refund it if upstream fails.
 */
export async function chargeTurnTTSFloored(opts: {
  supabase: SupabaseClient
  userId: string
  action: "tts" | "tts_timestamps"
  chars: number
  sourceFn: string
  idempotencyKey: string
  metadata?: Record<string, unknown>
}): Promise<ChargeResult | ChargeError> {
  const { supabase, userId, action, chars, sourceFn, idempotencyKey, metadata } = opts
  const { data, error } = await billingClient().rpc("charge_turn_tts_floored", {
    p_user_id: userId,
    p_chars: chars,
    p_action: action,
    p_source_fn: sourceFn,
    p_idempotency_key: idempotencyKey,
    p_metadata: metadata ?? null,
  })
  if (error) {
    if (error.message?.includes("INSUFFICIENT_CREDITS")) {
      await recordDepletion(userId, sourceFn)
      return { ok: false, reason: "insufficient_credits", detail: error.message }
    }
    if (error.message?.includes("DAILY_CAP_REACHED")) {
      return { ok: false, reason: "daily_cap", detail: error.message }
    }
    if (error.message?.includes("NO_CREDIT_ROW")) {
      return { ok: false, reason: "no_credit_row", detail: error.message }
    }
    return { ok: false, reason: "db_error", detail: error.message }
  }
  const parsed = data as { balance?: number; charged?: number }
  return {
    ok: true,
    balanceAfter: parsed?.balance ?? -1,
    charged: parsed?.charged ?? 0,
    idempotencyKey,
  }
}

/**
 * Idempotency-proof hourly abuse cap (the `bump_request_rate` SQL function).
 *
 * Every free/pooled metering RPC short-circuits on a duplicate idempotency key
 * without raising, so a client that pins one key never advances a daily cap and
 * never pays — an unlimited free faucet on both provider keys. This limiter
 * increments UNCONDITIONALLY per request, so a replayed key hits the ceiling
 * like any other traffic. It sits IN FRONT of the per-purpose daily caps as a
 * backstop; honest use never approaches `limit`. Returns rate_limited only when
 * the DB actually raised — a DB error fails OPEN (never block a paying call on
 * a limiter hiccup; the daily caps and charges are still behind it).
 */
export async function enforceRequestRate(opts: {
  userId: string
  sourceFn: string
  limit: number
}): Promise<{ ok: true } | { ok: false }> {
  const { error } = await billingClient().rpc("bump_request_rate", {
    p_user_id: opts.userId,
    p_source_fn: opts.sourceFn,
    p_limit: opts.limit,
  })
  if (error?.message?.includes("RATE_LIMITED")) return { ok: false }
  return { ok: true }
}

export function rateLimitedResponse(corsHeaders: HeadersInit): Response {
  return new Response(
    JSON.stringify({
      error: "rate_limited",
      message: "Daily limit reached for this feature. It resets at midnight UTC.",
    }),
    { status: 429, headers: { "Content-Type": "application/json", ...corsHeaders } },
  )
}

export interface ChargeResult {
  ok: true
  balanceAfter: number
  charged: number
  idempotencyKey: string
}
export interface ChargeError {
  ok: false
  reason: "insufficient_credits" | "daily_cap" | "no_credit_row" | "db_error"
  balanceAfter?: number
  detail?: string
}

/**
 * Atomic charge via the SQL `charge_credits` SECURITY DEFINER function.
 * Caller must already have a verified user (use requireUser first).
 */
export async function charge(opts: {
  supabase: SupabaseClient
  userId: string
  action: ChargeableAction
  amount: number
  sourceFn: string
  idempotencyKey: string
  metadata?: Record<string, unknown>
}): Promise<ChargeResult | ChargeError> {
  const { supabase, userId, action, amount, sourceFn, idempotencyKey, metadata } = opts
  if (amount === 0) {
    return { ok: true, balanceAfter: -1, charged: 0, idempotencyKey }
  }
  const { data, error } = await billingClient().rpc("charge_credits", {
    p_user_id: userId,
    p_credits: amount,
    p_action: action,
    p_source_fn: sourceFn,
    p_idempotency_key: idempotencyKey,
    p_metadata: metadata ?? null,
  })
  if (error) {
    if (error.message?.includes("INSUFFICIENT_CREDITS")) {
      await recordDepletion(userId, sourceFn)
      return { ok: false, reason: "insufficient_credits", detail: error.message }
    }
    if (error.message?.includes("DAILY_CAP_REACHED")) {
      return { ok: false, reason: "daily_cap", detail: error.message }
    }
    if (error.message?.includes("NO_CREDIT_ROW")) {
      return { ok: false, reason: "no_credit_row", detail: error.message }
    }
    return { ok: false, reason: "db_error", detail: error.message }
  }
  return { ok: true, balanceAfter: data as number, charged: amount, idempotencyKey }
}

/**
 * TTS charge with daily character pooling (the `charge_tts_pooled` SQL
 * function): characters accumulate per (user, day, action) and credits are
 * debited only when the running total crosses each 100-char boundary — same
 * long-run price as priceFor(), without the per-call ceil + 1-credit
 * minimum that overcharged short lines. `charged` in the result is exactly
 * what THIS call debited (possibly 0) — refund that amount if upstream
 * fails.
 */
export async function chargePooledTTS(opts: {
  supabase: SupabaseClient
  userId: string
  action: "tts" | "tts_timestamps" | "tts_scene"
  chars: number
  sourceFn: string
  idempotencyKey: string
  metadata?: Record<string, unknown>
  /**
   * Which daily pool these seconds land in. `scene_counted` means the scene
   * was already charged as ONE count by `beginScenePlay`, so its seconds must
   * not also be taken off the talk allowance. Anything else keeps the legacy
   * behaviour where scene seconds share the talk meter — which is what an
   * un-updated client (no scene key) still gets.
   */
  pool?: "scene_seconds" | "scene_counted"
}): Promise<ChargeResult | ChargeError> {
  const { supabase, userId, action, chars, sourceFn, idempotencyKey, metadata, pool } = opts
  const { data, error } = await billingClient().rpc("charge_tts_pooled", {
    p_user_id: userId,
    p_chars: chars,
    p_action: action,
    p_source_fn: sourceFn,
    p_idempotency_key: idempotencyKey,
    p_metadata: metadata ?? null,
    p_pool: pool ?? "scene_seconds",
  })
  if (error) {
    if (error.message?.includes("INSUFFICIENT_CREDITS")) {
      await recordDepletion(userId, sourceFn)
      return { ok: false, reason: "insufficient_credits", detail: error.message }
    }
    if (error.message?.includes("DAILY_CAP_REACHED")) {
      return { ok: false, reason: "daily_cap", detail: error.message }
    }
    if (error.message?.includes("NO_CREDIT_ROW")) {
      return { ok: false, reason: "no_credit_row", detail: error.message }
    }
    return { ok: false, reason: "db_error", detail: error.message }
  }
  const parsed = data as { balance?: number; charged?: number }
  return {
    ok: true,
    balanceAfter: parsed?.balance ?? -1,
    charged: parsed?.charged ?? 0,
    idempotencyKey,
  }
}

/**
 * Reverse a previous charge when the upstream call failed AFTER we debited.
 * Uses a derived idempotency key so a single charge can be cleanly refunded
 * exactly once.
 */
export async function refund(opts: {
  supabase: SupabaseClient
  userId: string
  amount: number
  action: ChargeableAction
  sourceFn: string
  originalIdempotencyKey: string
  metadata?: Record<string, unknown>
}): Promise<void> {
  const { supabase, userId, amount, action, sourceFn, originalIdempotencyKey, metadata } = opts
  if (amount === 0) return
  const refundKey = originalIdempotencyKey + ":refund"
  await billingClient().rpc("grant_credits", {
    p_user_id: userId,
    p_credits: amount,
    p_kind: "refund",
    p_action: action,
    p_source_fn: sourceFn,
    p_idempotency_key: refundKey,
    p_metadata: metadata ?? null,
  })
}

/**
 * Best-effort owner alert the FIRST time a user hits the credit wall.
 * Writes one row to credit_depletion_alerts (dedup by user_id) and, when
 * TELEGRAM_BOT_TOKEN + TELEGRAM_ADMIN_CHAT_ID are configured, pings the
 * owner. Never throws — the 402 to the client must not depend on this.
 */
async function recordDepletion(userId: string, sourceFn: string): Promise<void> {
  try {
    const svc = serviceRoleClient()
    const { data } = await svc
      .from("credit_depletion_alerts")
      .upsert({ user_id: userId, source_fn: sourceFn },
              { onConflict: "user_id", ignoreDuplicates: true })
      .select("user_id")
    const firstTime = (data?.length ?? 0) > 0
    if (!firstTime) return

    const token = Deno.env.get("TELEGRAM_BOT_TOKEN")
    const chatId = Deno.env.get("TELEGRAM_ADMIN_CHAT_ID")
    if (token && chatId) {
      await fetch(`https://api.telegram.org/bot${token}/sendMessage`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          chat_id: chatId,
          text: `[FutureVoice] beta user out of credits\nuser: ${userId}\nvia: ${sourceFn}`,
        }),
      })
    }
  } catch (e) {
    console.error("recordDepletion failed (non-fatal)", e)
  }
}

export function insufficientCreditsResponse(corsHeaders: HeadersInit): Response {
  return new Response(
    JSON.stringify({
      error: "insufficient_credits",
      message: "You're out of talk minutes. Upgrade to keep talking.",
    }),
    { status: 402, headers: { "Content-Type": "application/json", ...corsHeaders } },
  )
}

/**
 * A SUBSCRIBER used up today's minutes (plan daily allowance). Same 402
 * status as insufficient_credits so old clients still stop the call, but the
 * `error` field lets new clients show "see you tomorrow" instead of a
 * paywall — a paying user must never be asked to pay again.
 */
export function dailyCapResponse(corsHeaders: HeadersInit): Response {
  return new Response(
    JSON.stringify({
      error: "daily_cap_reached",
      message: "Today's talk minutes are used up. They reset at midnight UTC.",
    }),
    { status: 402, headers: { "Content-Type": "application/json", ...corsHeaders } },
  )
}

/**
 * A SUBSCRIBER used up today's Watch scenes (plan `daily_scenes`). Like the
 * daily talk cap this is NEVER a paywall — they already paid, and the answer
 * is "tomorrow", not "pay again". Distinct from `daily_cap_reached` so the
 * app can say which of the two allowances ran out; an older client that
 * doesn't know this string still sees a 402 and stops.
 */
export function sceneCapResponse(corsHeaders: HeadersInit): Response {
  return new Response(
    JSON.stringify({
      error: "scene_cap_reached",
      message: "Today's Watch scenes are used up. They reset at midnight UTC.",
    }),
    { status: 402, headers: { "Content-Type": "application/json", ...corsHeaders } },
  )
}

/**
 * Claim one of today's Watch scenes for this user.
 *
 * Called once per scene LINE with a key that is stable across the whole
 * scene, so the first line claims the slot and the rest ride along — a scene
 * costs one count no matter how many lines it has, and a scene already in
 * progress is never cut off half way through.
 *
 * `counted: false` means the user has no entitlement, so scenes stay priced
 * in seconds out of their balance and no count applies.
 */
export async function beginScenePlay(opts: {
  supabase: SupabaseClient
  userId: string
  sceneKey: string
}): Promise<
  | { ok: true; counted: boolean; used?: number; cap?: number }
  | { ok: false; reason: "scene_cap" | "db_error"; detail?: string }
> {
  const { data, error } = await billingClient().rpc("begin_scene_play", {
    p_user_id: opts.userId,
    p_scene_key: opts.sceneKey,
  })
  if (error) {
    if (error.message?.includes("SCENE_CAP_REACHED")) {
      return { ok: false, reason: "scene_cap", detail: error.message }
    }
    return { ok: false, reason: "db_error", detail: error.message }
  }
  const parsed = data as { metered_by?: string; used?: number; cap?: number }
  return {
    ok: true,
    counted: parsed?.metered_by === "scenes",
    used: parsed?.used,
    cap: parsed?.cap,
  }
}

/**
 * Charges using the service-role client (bypasses RLS) — required because
 * `user_credits` writes happen inside the SECURITY DEFINER function but the
 * function itself needs to be invoked by a client that can actually call it.
 * Edge Functions get the service-role key from env automatically.
 */
export function serviceRoleClient(): SupabaseClient {
  return createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false } },
  )
}

/**
 * The client EVERY metering RPC goes through — never the caller's.
 *
 * These functions all take `p_user_id` as an argument, so whoever can execute
 * them can name any account: `grant_credits` was a money printer reachable
 * with nothing but the app's (public by design) anon key, and the `charge_*`
 * family could burn a stranger's daily cap once their uuid was harvested from
 * `public_personas.owner_user_id`. Argument-level guards can't close that —
 * a caller passing their OWN uuid to `grant_credits` is indistinguishable
 * from a legitimate call. The only real fix is that no client role holds
 * EXECUTE at all, which makes these server-only primitives.
 *
 * Every call site already passes the id of the user it just authenticated,
 * so routing through service-role changes no behaviour — only who is able to
 * make the call. Cached because Edge Function instances are reused across
 * requests and each createClient is a fresh connection pool.
 */
let cachedBillingClient: SupabaseClient | null = null
export function billingClient(): SupabaseClient {
  if (!cachedBillingClient) cachedBillingClient = serviceRoleClient()
  return cachedBillingClient
}
