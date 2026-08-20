// Owner-facing operational alerts.
//
// One place that talks to Telegram, one place that decides how often the same
// incident is allowed to ping. Everything here is best-effort and never
// throws: an alert that fails must not change what the user's request returns.
//
// Requires TELEGRAM_BOT_TOKEN + TELEGRAM_ADMIN_CHAT_ID in the function env
// (`supabase secrets set`). Without them the alert is logged and dropped.

import { createClient, type SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.45.0"

/** Service-role client — `ops_alerts` is RLS'd shut to everyone else. */
function serviceClient(): SupabaseClient {
  return createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false } },
  )
}

/** Best-effort Telegram ping to the owner. Never throws. */
export async function notifyOwner(text: string): Promise<void> {
  const token = Deno.env.get("TELEGRAM_BOT_TOKEN")
  const chatId = Deno.env.get("TELEGRAM_ADMIN_CHAT_ID")
  if (!token || !chatId) {
    console.warn("owner alert not sent (TELEGRAM_* unset):", text)
    return
  }
  try {
    const res = await fetch(`https://api.telegram.org/bot${token}/sendMessage`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ chat_id: chatId, text, disable_web_page_preview: true }),
    })
    if (!res.ok) {
      console.error("telegram sendMessage failed", res.status, (await res.text()).slice(0, 300))
    }
  } catch (e) {
    console.error("telegram sendMessage threw (non-fatal)", e)
  }
}

/** UTC-hour dedupe bucket: "2026-08-20T14". */
export function hourWindow(at: Date = new Date()): string {
  return at.toISOString().slice(0, 13)
}

/** UTC-day dedupe bucket: "2026-08-20". */
export function dayWindow(at: Date = new Date()): string {
  return at.toISOString().slice(0, 10)
}

/**
 * Counts one occurrence of `kind` inside `windowKey` and returns the running
 * count (1 = first in this window). Returns 1 when the ledger is unreachable:
 * a duplicate alert is a far cheaper failure than a silent one.
 */
export async function countAlert(
  kind: string,
  windowKey: string,
  detail?: Record<string, unknown>,
): Promise<number> {
  try {
    const { data, error } = await serviceClient().rpc("record_ops_alert", {
      p_kind: kind,
      p_window_key: windowKey,
      p_detail: detail ?? null,
    })
    if (error) throw error
    return typeof data === "number" && data > 0 ? data : 1
  } catch (e) {
    console.error("record_ops_alert failed (non-fatal)", e)
    return 1
  }
}

/**
 * The ElevenLabs account is out of custom-voice slots (or upstream is
 * throttling us), so a user could not get the one thing the product is:
 * their own voice. The fix is a plan upgrade, so this goes straight to the
 * owner's phone.
 *
 * Pings on the FIRST failure in the hour, then only as the incident escalates
 * (5th, 25th, then every 50th) — enough to tell "one unlucky signup" from
 * "the whole cohort is blocked" without turning into a notification storm.
 */
export async function alertVoiceCapacity(args: {
  userId: string
  sourceFn: string
  status: number
  detail: string
}): Promise<void> {
  const count = await countAlert("voice_capacity", hourWindow(), {
    user_id: args.userId,
    source_fn: args.sourceFn,
    status: args.status,
    upstream: args.detail.slice(0, 300),
  })
  const escalating = count === 1 || count === 5 || count === 25 || count % 50 === 0
  if (!escalating) return

  const lines = [
    "🚨 FutureVoice — ElevenLabs voice slots are FULL",
    count === 1
      ? "A user just failed to create their voice."
      : `${count} voice creations blocked in this hour.`,
    `user: ${args.userId}`,
    `via: ${args.sourceFn} (upstream HTTP ${args.status})`,
    "",
    "Fix: upgrade the ElevenLabs plan (more custom voices) or free slots.",
    "The app is showing them a wait-and-retry sheet — their recording is saved, so a retry costs them nothing.",
  ]
  await notifyOwner(lines.join("\n"))
}

/**
 * The account is CLOSE to the custom-voice ceiling but hasn't hit it. Worth a
 * calmer ping than `alertVoiceCapacity`: the fix (a bigger ElevenLabs plan) is
 * a human doing a few minutes of work, and learning about the ceiling from the
 * first blocked user is already too late.
 *
 * Deduped per remaining-slot count per day, so a busy day pings once at 3
 * slots left, once at 2, once at 1 — a countdown, not a stream.
 */
export async function alertVoiceHeadroom(args: {
  used: number
  limit: number
  sourceFn: string
}): Promise<void> {
  const remaining = Math.max(0, args.limit - args.used)
  const count = await countAlert("voice_headroom", `${dayWindow()}:${remaining}`, {
    used: args.used,
    limit: args.limit,
    source_fn: args.sourceFn,
  })
  if (count !== 1) return

  await notifyOwner([
    "⚠️ FutureVoice — ElevenLabs voice slots are running out",
    `${args.used} of ${args.limit} used · ${remaining} left`,
    "",
    "Upgrade the plan (or free slots) before the next users are blocked.",
  ].join("\n"))
}
