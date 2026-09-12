// Stripe webhook — the ONLY writer of web-billed entitlements.
//
// Mirrors the design of the Apple server-notification webhook:
// user_subscriptions is upserted from provider events, and the client never
// mints anything itself. Minutes-native model: the subscription row IS the
// entitlement (per-day allowance via subscription_plans.daily_seconds) —
// no credit grants on entry or renewal.
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
    // delivered while our side silently failed. The upsert is a plain
    // overwrite keyed on user_id, so retries are safe. (Minutes-native:
    // nothing is granted here — the subscription row IS the entitlement.)
    console.error("stripe-webhook failed", event.type, e)
    return json(500, { error: "handler failed" })
  }

  return json(200, { received: true })
})

// ── entitlement writes ─────────────────────────────────────────

// deno-lint-ignore no-explicit-any
async function upsertSubscription(db: any, sub: Stripe.Subscription, forceStatus?: string) {
  // SHARED Stripe account (Dear RoRo): humhumhum and DeskSquat bill here too,
  // and every webhook endpoint on the account receives every matching event.
  // Ours is subscribed to subscription-shaped events only and both of those
  // projects sell one-time payments, so foreign events are rare here — but a
  // subscription that isn't ours must be SKIPPED quietly, never retried and
  // never written. Ours carry metadata.project = "futurevoice" (and always
  // user_id); anything else is another project's.
  const project = sub.metadata?.project
  if (project && project !== "futurevoice") {
    console.log("skipping another project's subscription", project, sub.id)
    return
  }
  const userId = sub.metadata?.user_id
  if (!userId) {
    console.warn("subscription without user_id metadata — not ours, skipping", sub.id)
    return
  }
  // The plan comes from the PRICE actually on the subscription, not from the
  // checkout metadata: a portal upgrade/downgrade swaps the price but keeps
  // the metadata written at checkout, so metadata alone goes stale the first
  // time anyone changes plan. Metadata stays as the fallback (e.g. a price
  // not yet in the catalog).
  // deno-lint-ignore no-explicit-any
  const priceId = (sub as any).items?.data?.[0]?.price?.id
  let planId: string | null = sub.metadata?.plan_id ?? null
  if (priceId) {
    const { data: planRow } = await db
      .from("subscription_plans")
      .select("id")
      .eq("stripe_price_id", priceId)
      .maybeSingle()
    if (planRow) planId = planRow.id
    else console.warn("no plan for stripe price", priceId, "— falling back to metadata", planId)
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
