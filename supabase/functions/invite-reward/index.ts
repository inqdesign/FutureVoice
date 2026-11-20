// The invite event's hands (2026-11-19): what `invite_rewards` says, carried
// out. The table decides who gets a half-price month; this function tells
// them and, where a store lets a server do it, gives it.
//
// One caller: the DATABASE, with CLEANUP_SECRET in X-Cleanup-Secret
// (`verify_jwt = false`), when a reward was earned or a new billing period
// made the next one givable:
//     { user_ids: [...] }
// For each: a Stripe subscriber gets the coupon applied and is told it is
// done; an App Store or Play subscriber is told to come and take it (those
// stores ask the subscriber). One push per reward (push-send's ledger), in
// the words of `invite_event.texts`.
//
// The App Store claim needs nothing from here: the app gets a one-time offer
// code from the database (`invite_reward_code`) and Apple's renewal info
// marks the reward claimed (migration 20261119120000).
//
// Every number and word comes from `invite_event`: nothing here is the
// event's size.

import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { createClient, type SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.45.0"
import { cors, errorResponse, handlePreflight, timingSafeEqual } from "../_shared/auth.ts"
import { addStripeCoupon } from "../_shared/stripe-discount.ts"

interface Reward { id: string; user_id: string; status: string; claimed_at: string | null; notified_at: string | null }

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status, headers: { "Content-Type": "application/json", ...cors() },
  })
}

// The oldest waiting reward, unless one was already taken in this billing
// period. The same rule as `invite_event_state`.
async function givable(db: SupabaseClient, userId: string, periodStart: string | null): Promise<Reward | null> {
  const { data } = await db.from("invite_rewards")
    .select("id, user_id, status, claimed_at, notified_at")
    .eq("user_id", userId).in("status", ["ready", "claimed"])
    .order("created_at", { ascending: true })
  const rows = (data ?? []) as Reward[]
  const takenThisPeriod = rows.some((r) =>
    r.status === "claimed" && r.claimed_at != null &&
    (periodStart == null || r.claimed_at >= periodStart))
  if (takenThisPeriod) return null
  return rows.find((r) => r.status === "ready") ?? null
}

function fill(text: string, percent: number): string {
  return text.replaceAll("{percent}", String(percent))
}

// language -> { title, body } for push-send, from the event's own texts.
function pushTexts(texts: Record<string, Record<string, string>>, bodyKey: string, percent: number) {
  const out: Record<string, { title: string; body: string }> = {}
  for (const [lang, t] of Object.entries(texts ?? {})) {
    if (t?.push_title && t?.[bodyKey]) {
      out[lang] = { title: fill(t.push_title, percent), body: fill(t[bodyKey], percent) }
    }
  }
  return out
}

async function tell(db: SupabaseClient, base: string, userIds: string[]) {
  const pushSecret = Deno.env.get("PUSH_SECRET")
  const stripeKey = Deno.env.get("STRIPE_SECRET_KEY")
  const { data: event } = await db.from("invite_event").select("*").eq("id", 1).single()
  if (!event?.enabled) return { skipped: "event off" }

  const results: Record<string, string> = {}
  for (const userId of userIds) {
    const { data: sub } = await db.from("user_subscriptions")
      .select("status, source, stripe_subscription_id, current_period_start")
      .eq("user_id", userId).maybeSingle()
    if (!sub || !["trialing", "active", "grace"].includes(sub.status)) { results[userId] = "no plan"; continue }
    const reward = await givable(db, userId, sub.current_period_start)
    if (!reward) { results[userId] = "nothing givable"; continue }

    let bodyKey = "push_claim_body"
    if (sub.source === "stripe" && sub.stripe_subscription_id && event.stripe_coupon_id && stripeKey) {
      const failed = await addStripeCoupon(stripeKey, sub.stripe_subscription_id, event.stripe_coupon_id)
      if (failed) {
        console.error("invite-reward: stripe", failed)
        results[userId] = "stripe failed"
        continue
      }
      await db.from("invite_rewards")
        .update({ status: "claimed", claimed_at: new Date().toISOString(), store: "stripe" })
        .eq("id", reward.id).eq("status", "ready")
      bodyKey = "push_auto_body"
    }

    const texts = pushTexts(event.texts, bodyKey, event.percent)
    if (pushSecret && Object.keys(texts).length > 0) {
      const res = await fetch(`${base}/functions/v1/push-send`, {
        method: "POST",
        headers: { "Content-Type": "application/json", "X-Push-Secret": pushSecret },
        body: JSON.stringify({
          kind: "invite_reward", dedupe_key: reward.id, user_ids: [userId],
          texts, url: "futurevoice://invite", collapse_id: "invite_reward",
        }),
      })
      if (!res.ok) console.error("invite-reward: push-send", res.status, await res.text())
    }
    await db.from("invite_rewards").update({ notified_at: new Date().toISOString() }).eq("id", reward.id)
    results[userId] = bodyKey === "push_auto_body" ? "applied" : "told"
  }
  return results
}

Deno.serve(async (req) => {
  const pre = handlePreflight(req)
  if (pre) return pre
  if (req.method !== "POST") return errorResponse(405, "method not allowed")
  const base = Deno.env.get("SUPABASE_URL")!
  const db = createClient(base, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!)

  let body: { user_ids?: string[] }
  try { body = await req.json() } catch { return errorResponse(400, "invalid json body") }

  const given = req.headers.get("X-Cleanup-Secret")
  const secret = Deno.env.get("CLEANUP_SECRET")
  if (given == null || !secret || !timingSafeEqual(given, secret)) {
    return new Response("forbidden", { status: 403 })
  }
  const ids = (body.user_ids ?? []).filter((x) => typeof x === "string").slice(0, 20)
  return json(await tell(db, base, ids))
})
