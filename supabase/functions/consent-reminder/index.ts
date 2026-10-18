// Remind a learner that Apple is waiting on their consent to charge
// (2026-10-18).
//
// Korea asks for a second consent before a free trial turns into the regular
// price, and Apple asks it with its own email, push and in-app sheet. Four of
// six Korean trialers in September never answered and their subscriptions
// ended with auto-renew still on. Apple's own reminder arrives three days
// before the renewal (none at all on a 3-day trial) and reads like a price
// increase, which is the last thing someone who chose a plan expects.
//
// So once, about two days before the charge that will not happen without it,
// the learner hears it from us, in the app's language, with a tap that opens
// the app straight on the consent explanation (`futurevoice://consent`).
//
// Called hourly by pg_cron (20261018170000) with CLEANUP_SECRET; sends through
// `push-send`, whose ledger (`push_sends`) makes a second run a no-op.

import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0"
import { timingSafeEqual } from "../_shared/auth.ts"

/// How long before the due charge the reminder goes out. Apple's own follow-up
/// is at three days; ours lands after it and before the last day.
const LEAD_HOURS = 48

interface Text { title: string; body: string }

// Chrome, so it follows the app language (push-send picks by app_language,
// falling back to en). Korean is the storefront this exists for.
const TRIAL_TEXTS: Record<string, Text> = {
  en: {
    title: "One tap keeps your plan going",
    body: "Apple needs your OK before your free trial turns into your plan. Tap to confirm it in a few seconds.",
  },
  ko: {
    title: "확인 한 번이면 구독이 그대로 이어져요",
    body: "체험이 끝나기 전에 App Store에서 결제 동의를 한 번 해 주셔야 해요. 눌러서 바로 확인할 수 있어요.",
  },
}

const PLAN_TEXTS: Record<string, Text> = {
  en: {
    title: "One tap keeps your plan going",
    body: "Apple needs your OK before your next renewal. Tap to confirm it in a few seconds.",
  },
  ko: {
    title: "확인 한 번이면 구독이 그대로 이어져요",
    body: "다음 결제 전에 App Store에서 동의를 한 번 해 주셔야 해요. 눌러서 바로 확인할 수 있어요.",
  },
}

Deno.serve(async (req) => {
  const secret = Deno.env.get("CLEANUP_SECRET")
  if (!secret || !timingSafeEqual(req.headers.get("X-Cleanup-Secret") ?? "", secret)) {
    return new Response("forbidden", { status: 403 })
  }
  const pushSecret = Deno.env.get("PUSH_SECRET")
  const base = Deno.env.get("SUPABASE_URL")
  if (!pushSecret || !base) return new Response("push not configured", { status: 500 })

  const db = createClient(base, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!)
  const now = new Date()
  const horizon = new Date(now.getTime() + LEAD_HOURS * 3600_000)

  const { data: rows, error } = await db
    .from("user_subscriptions")
    .select("user_id, status, apple_original_tx_id, price_consent_due_at")
    .not("price_consent_pending_since", "is", null)
    .gt("price_consent_due_at", now.toISOString())
    .lte("price_consent_due_at", horizon.toISOString())
  if (error) return new Response(`query: ${error.message}`, { status: 500 })

  let sent = 0
  for (const row of rows ?? []) {
    const trial = row.status === "trialing"
    const res = await fetch(`${base}/functions/v1/push-send`, {
      method: "POST",
      headers: { "Content-Type": "application/json", "X-Push-Secret": pushSecret },
      body: JSON.stringify({
        kind: "price_consent",
        // One reminder per renewal: a later renewal asking again is a new key.
        dedupe_key: `${row.apple_original_tx_id ?? row.user_id}:${String(row.price_consent_due_at).slice(0, 10)}`,
        user_ids: [row.user_id],
        texts: trial ? TRIAL_TEXTS : PLAN_TEXTS,
        url: "futurevoice://consent",
        collapse_id: "price_consent",
      }),
    })
    if (res.ok) sent += 1
    else console.error("consent-reminder: push-send", res.status, await res.text())
  }

  return new Response(JSON.stringify({ waiting: rows?.length ?? 0, sent }), {
    headers: { "Content-Type": "application/json" },
  })
})
