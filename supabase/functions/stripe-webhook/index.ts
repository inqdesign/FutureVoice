// Stripe webhook — the ONLY writer of web-billed entitlements.
//
// Mirrors the design of the (upcoming) Apple server-notification webhook:
// user_subscriptions is upserted from provider events, credits are granted
// via the grant_credits() RPC with an idempotency key, and the client never
// mints anything itself.
//
// verify_jwt = false (Stripe can't send a Supabase JWT) — authenticity comes
// from the Stripe-Signature header, verified with the official SDK
// (constructEventAsync + SubtleCrypto provider, the Deno-supported path).
// Pattern proven in humhumhum's tip webhook.
//
// Stripe dashboard setup:
//   URL: https://<project>.supabase.co/functions/v1/stripe-webhook
//   Events: checkout.session.completed, invoice.paid,
//           customer.subscription.updated, customer.subscription.deleted
//
// Credits are granted on `invoice.paid` (billing_reason subscription_create /
// subscription_cycle), keyed by invoice id — renewals therefore grant exactly
// once no matter how many times Stripe retries the delivery.

import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import Stripe from "npm:stripe@17"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0"

const SOURCE_FN = "stripe-webhook"

const cryptoProvider = Stripe.createSubtleCryptoProvider()

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "method not allowed" })

  const secret = Deno.env.get("STRIPE_WEBHOOK_SECRET")
  const stripeKey = Deno.env.get("STRIPE_SECRET_KEY")
  if (!secret || !stripeKey) return json(500, { error: "server missing stripe secrets" })

  const stripe = new Stripe(stripeKey, { httpClient: Stripe.createFetchHttpClient() })

  // constructEventAsync needs the raw bytes Stripe sent — read once, don't parse first.
  const raw = await req.text()
  const sig = req.headers.get("stripe-signature")
  if (!sig) return json(400, { error: "missing signature" })

  let event: Stripe.Event
  try {
    event = await stripe.webhooks.constructEventAsync(raw, sig, secret, undefined, cryptoProvider)
  } catch (e) {
    const msg = e instanceof Error ? e.message : "invalid signature"
    return json(400, { error: msg })
  }

  const db = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  )

  try {
    switch (event.type) {
      case "checkout.session.completed": {
        const session = event.data.object as Stripe.Checkout.Session
        if (session.mode !== "subscription" || !session.subscription) break
        const subId = typeof session.subscription === "string"
          ? session.subscription : session.subscription.id
        const sub = await stripe.subscriptions.retrieve(subId)
        await upsertSubscription(db, sub)
        break
      }
      case "invoice.paid": {
        const invoice = event.data.object as Stripe.Invoice
        const subId = subscriptionIdOf(invoice)
        if (!subId) break
        const sub = await stripe.subscriptions.retrieve(subId)
        await upsertSubscription(db, sub)
        if (invoice.billing_reason === "subscription_create"
          || invoice.billing_reason === "subscription_cycle") {
          await grantCycleCredits(db, sub, String(invoice.id))
        }
        break
      }
      case "customer.subscription.updated": {
        await upsertSubscription(db, event.data.object as Stripe.Subscription)
        break
      }
      case "customer.subscription.deleted": {
        await upsertSubscription(db, event.data.object as Stripe.Subscription, "expired")
        break
      }
      default:
        break // acknowledge everything else
    }
  } catch (e) {
    // Return 500 so Stripe retries this event later instead of marking it
    // delivered while our side silently failed. grant_credits is idempotent,
    // so retries are safe.
    console.error("stripe-webhook failed", event.type, e)
    return json(500, { error: "handler failed" })
  }

  return json(200, { received: true })
})

// ── entitlement writes ─────────────────────────────────────────

// deno-lint-ignore no-explicit-any
async function upsertSubscription(db: any, sub: Stripe.Subscription, forceStatus?: string) {
  const userId = sub.metadata?.user_id
  const planId = sub.metadata?.plan_id
  if (!userId) {
    console.error("subscription without user_id metadata", sub.id)
    return
  }
  const period = periodOf(sub)
  const { error } = await db.from("user_subscriptions").upsert({
    user_id: userId,
    plan_id: planId ?? null,
    source: "stripe",
    stripe_customer_id: typeof sub.customer === "string" ? sub.customer : sub.customer?.id,
    stripe_subscription_id: sub.id,
    status: forceStatus ?? mapStatus(sub.status),
    current_period_start: period.start,
    current_period_end: period.end,
    trial_ends_at: sub.trial_end ? iso(sub.trial_end) : null,
    cancel_at_period_end: !!sub.cancel_at_period_end,
    updated_at: new Date().toISOString(),
  })
  if (error) {
    // The user may have deleted their account between checkout and this
    // event (FK violation, 23503) — drop the event instead of retrying
    // forever. (Same guard as humhumhum's tip webhook.)
    if (error.code === "23503") {
      console.warn("user gone, dropping subscription event", sub.id)
      return
    }
    throw new Error(`user_subscriptions upsert: ${error.message}`)
  }
}

// deno-lint-ignore no-explicit-any
async function grantCycleCredits(db: any, sub: Stripe.Subscription, invoiceId: string) {
  const userId = sub.metadata?.user_id
  const planId = sub.metadata?.plan_id
  if (!userId || !planId) return

  const { data: plan, error: planErr } = await db
    .from("subscription_plans")
    .select("credits_per_cycle")
    .eq("id", planId)
    .single()
  if (planErr || !plan) throw new Error(`unknown plan ${planId}`)

  const { error: rpcErr } = await db.rpc("grant_credits", {
    p_user_id: userId,
    p_credits: plan.credits_per_cycle,
    p_kind: "grant",
    p_action: "cycle_grant",
    p_source_fn: SOURCE_FN,
    p_idempotency_key: `stripe_invoice_${invoiceId}`,
    p_metadata: { stripe_invoice: invoiceId, stripe_subscription: sub.id, plan_id: planId },
  })
  if (rpcErr) {
    if (rpcErr.code === "23503") {
      console.warn("user gone, dropping credit grant", sub.id)
      return
    }
    throw new Error(`grant_credits: ${rpcErr.message}`)
  }

  const period = periodOf(sub)
  const { error: credErr } = await db.from("user_credits").update({
    period_start: period.start,
    period_end: period.end,
    cycle_grant: plan.credits_per_cycle,
    updated_at: new Date().toISOString(),
  }).eq("user_id", userId)
  if (credErr) throw new Error(`user_credits period update: ${credErr.message}`)
}

// ── mapping helpers ────────────────────────────────────────────

function mapStatus(s: Stripe.Subscription.Status): string {
  switch (s) {
    case "trialing": return "trialing"
    case "active": return "active"
    case "past_due": return "grace"
    case "canceled":
    case "unpaid":
    case "incomplete_expired": return "expired"
    default: return "inactive" // incomplete, paused, …
  }
}

// The subscription id moved around across Stripe API versions — check both
// the classic `invoice.subscription` and the 2025+ `parent.subscription_details`.
function subscriptionIdOf(invoice: Stripe.Invoice): string | null {
  // deno-lint-ignore no-explicit-any
  const inv = invoice as any
  const raw = inv.subscription ?? inv.parent?.subscription_details?.subscription
  if (!raw) return null
  return typeof raw === "string" ? raw : raw.id
}

// current_period_* lives on the subscription in classic API versions and on
// the subscription item in 2025+ versions — read both defensively.
function periodOf(sub: Stripe.Subscription): { start: string | null; end: string | null } {
  // deno-lint-ignore no-explicit-any
  const s = sub as any
  const item = s.items?.data?.[0]
  const start = s.current_period_start ?? item?.current_period_start
  const end = s.current_period_end ?? item?.current_period_end
  return { start: start ? iso(start) : null, end: end ? iso(end) : null }
}

function iso(epochSeconds: number): string {
  return new Date(epochSeconds * 1000).toISOString()
}

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  })
}
