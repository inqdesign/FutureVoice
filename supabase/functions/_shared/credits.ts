// Credit-gate helpers shared by every paid Edge Function.
//
// Each provider call follows this pattern:
//   1. estimate cost in credits via priceFor(action, params)
//   2. charge() — atomic DB debit. If INSUFFICIENT_CREDITS, return 402.
//   3. invoke upstream provider (ElevenLabs / Gemini)
//   4. if upstream failed, refund() with the same idempotency key
//   5. return result to client
//
// Idempotency keys are required so client retries don't double-charge.
// Convention: hash(user_id + action + relevant_params + nonce) where nonce
// is supplied by the client per-attempt. The client-side networking layer
// generates one nonce per request and resends it on retry.

import { createClient, type SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.45.0"
import { notifyOwner } from "./ops_alert.ts"

// One internal credit ≈ $0.04 of upstream cost at full retail. Pricing is
// derived from this so changes to provider rates only need a single edit.
//
// IMPORTANT: keep these aligned with whatever copy the iOS PaywallView shows.
// Mismatch between the credit cost a user sees in the UI and what we actually
// charge is a trust-breaker.

export type ChargeableAction =
  | "tts"               // per ElevenLabs synthesis (no timestamps)
  | "tts_timestamps"    // with-timestamps endpoint (slightly more expensive)
  | "voice_clone"       // /v1/voices/add — one-shot
  | "voice_delete"      // free — but we charge 0 so we get a ledger row
  | "gemini"            // generateContent
  | "gemini_summary"    // summary at end of session — same engine, separate tag
  | "gemini_weekly"     // weekly report
  | "gemini_enrichment" // drill enrichment

/**
 * Returns the credit cost for a given action + parameters. Credit math here
 * mirrors what's documented in the paywall — keep them in sync.
 *
 * For TTS we charge by character count rounded up (turbo v2.5 is billed
 * per character upstream). 100 chars ≈ 1 credit, so a typical 150-char
 * future-self response = 2 credits.
 *
 * For Gemini we treat each call as roughly equivalent — input + output
 * tokens vary but per-call cost is dominated by the fixed Gemini overhead
 * at our prompt sizes.
 */
export function priceFor(action: ChargeableAction, params: Record<string, unknown> = {}): number {
  switch (action) {
    case "tts": {
      const chars = typeof params.chars === "number" ? params.chars : 150
      return Math.max(1, Math.ceil(chars / 100))
    }
    case "tts_timestamps": {
      const chars = typeof params.chars === "number" ? params.chars : 150
      // ~25% premium for the with-timestamps endpoint (it's slower + more
      // upstream cost) and shadow learners value the per-word alignment.
      return Math.max(1, Math.ceil((chars * 1.25) / 100))
    }
    case "voice_clone":     return 5
    case "voice_delete":    return 0
    case "gemini":          return 1
    case "gemini_summary":  return 2
    case "gemini_weekly":   return 5
    case "gemini_enrichment": return 1
  }
}

export interface ChargeResult {
  ok: true
  balanceAfter: number
  charged: number
  idempotencyKey: string
}
export interface ChargeError {
  ok: false
  reason: "insufficient_credits" | "no_credit_row" | "db_error"
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
  const { data, error } = await supabase.rpc("charge_credits", {
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
  action: "tts" | "tts_timestamps"
  chars: number
  sourceFn: string
  idempotencyKey: string
  metadata?: Record<string, unknown>
}): Promise<ChargeResult | ChargeError> {
  const { supabase, userId, action, chars, sourceFn, idempotencyKey, metadata } = opts
  const { data, error } = await supabase.rpc("charge_tts_pooled", {
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
  await supabase.rpc("grant_credits", {
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
 * Writes one row to credit_depletion_alerts (dedup by user_id) and pings the
 * owner over Telegram (_shared/ops_alert.ts). Never throws — the 402 to the
 * client must not depend on this.
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

    await notifyOwner(`[FutureVoice] beta user out of credits\nuser: ${userId}\nvia: ${sourceFn}`)
  } catch (e) {
    console.error("recordDepletion failed (non-fatal)", e)
  }
}

export function insufficientCreditsResponse(corsHeaders: HeadersInit): Response {
  return new Response(
    JSON.stringify({
      error: "insufficient_credits",
      message: "You're out of credits. Upgrade or wait for your cycle reset.",
    }),
    { status: 402, headers: { "Content-Type": "application/json", ...corsHeaders } },
  )
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
