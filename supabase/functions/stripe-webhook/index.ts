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
import { reportStripeSubscriptionToRevenueCat } from "../_shared/revenuecat.ts"

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
        if (session.mode === "payment") { await grantChallenge(db, session); break }
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

// Returns the owner's user id when the row was written, null when skipped.
async function upsertSubscription(
  // deno-lint-ignore no-explicit-any
  db: any, sub: Stripe.Subscription, forceStatus?: string,
): Promise<string | null> {
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
    return null
  }
  const userId = sub.metadata?.user_id
  if (!userId) {
    console.warn("subscription without user_id metadata — not ours, skipping", sub.id)
    return null
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
  const status = forceStatus ?? mapStatus(sub.status)
  // A subscription that is not live may only end the row it is ON. A checkout
  // opened and never paid makes an `incomplete` subscription that Stripe
  // expires 23 hours later, and that event used to overwrite whatever the
  // account held: on 2026-11-12 a learner whose card was refused, and who
  // paid on a second checkout two minutes later, had the paid Plus replaced
  // by the first one's "expired". (apple-claim's rule: a dead transaction
  // never downgrades a live row.)
  if (!["active", "trialing", "grace"].includes(status)) {
    const { data: held, error: heldErr } = await db.from("user_subscriptions")
      .select("stripe_subscription_id").eq("user_id", userId).maybeSingle()
    if (heldErr) throw new Error(`user_subscriptions read: ${heldErr.message}`)
    if (held?.stripe_subscription_id !== sub.id) {
      console.log("not live and not the subscription on the row, skipping", sub.id, sub.status)
      return null
    }
  }
  const { error } = await db.from("user_subscriptions").upsert({
    user_id: userId,
    plan_id: planId ?? null,
    source: "stripe",
    stripe_customer_id: typeof sub.customer === "string" ? sub.customer : sub.customer?.id,
    stripe_subscription_id: sub.id,
    status,
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
      return null
    }
    throw new Error(`user_subscriptions upsert: ${error.message}`)
  }
  // RevenueCat hears about every subscription event (2026-11-11), as on
  // google-webhook: the first post makes the subscription known there under
  // this user, a later one has it re-read Stripe (a renewal, a cancel). No
  // Stripe webhook points at RevenueCat, because the account is shared with
  // other projects. After the row above, which it never gates.
  await reportStripeSubscriptionToRevenueCat({ userId, subscriptionId: sub.id })
  return userId
}

// The 100-day challenge package: paid once, so there is no Stripe subscription
// and this session is the only event there will ever be. The row it writes is
// the entitlement for 100 days; the nightly sweep ends it
// (expire_comp_subscriptions, 20261112100000). The account is shared with
// projects that sell one-time payments too, so anything that is not ours by
// its own metadata is skipped quietly.
const CHALLENGE_DAYS = 100

// deno-lint-ignore no-explicit-any
async function grantChallenge(db: any, session: Stripe.Checkout.Session): Promise<void> {
  const m = session.metadata ?? {}
  if (m.project === "futurevoice" && m.kind === "challenge_upgrade") return await upgradeChallenge(db, session)
  if (m.project !== "futurevoice" || m.kind !== "challenge") return
  if (session.payment_status !== "paid") return
  const userId = m.user_id, planId = m.plan_id
  if (!userId || !planId) { console.warn("challenge session without user or plan", session.id); return }

  const { data: plan } = await db.from("subscription_plans")
    .select("id, period").eq("id", planId).maybeSingle()
  if (!plan || plan.period !== "challenge") { console.warn("challenge session for a non-challenge plan", session.id, planId); return }

  // The application this payment belongs to, when the buyer came from the form:
  // it now knows its app account. Before anything that can return early, and
  // only ever filled once.
  if (m.application_id) {
    const { error: linkErr } = await db.from("creator_applications")
      .update({ user_id: userId, paid_at: new Date(session.created * 1000).toISOString(), paid_plan: planId, status: "active", started_at: new Date(session.created * 1000).toISOString(), updated_at: new Date().toISOString() })
      .eq("id", m.application_id).eq("kind", "challenger").is("paid_at", null)
    if (linkErr) console.error("challenge application not linked", session.id, linkErr.message)
  }

  // Paid ahead, started together: the 100 days (three months, and ten days on
  // the house) run from the cohort's first day when it is set and still ahead
  // (billing_config.challenge_starts_at, set in the admin), otherwise from the
  // payment. The app works from the payment on either way. While the day is
  // not set yet, the admin moves these rows when it is. session.created keeps
  // a retried event from moving the dates.
  const paidAt = new Date(session.created * 1000)
  const { data: cfg } = await db.from("billing_config").select("challenge_starts_at").maybeSingle()
  const cohort = new Date(cfg?.challenge_starts_at ?? "")
  // Everyone ends on the same day, so someone who joins after the first day
  // still counts from it (unless the cohort is already over).
  const cohortEnd = new Date(cohort.getTime() + CHALLENGE_DAYS * 86_400_000)
  const from = !isNaN(cohort.getTime()) && cohortEnd > paidAt ? cohort : paidAt
  const end = new Date(from.getTime() + CHALLENGE_DAYS * 86_400_000)

  // A retry of this same event must not shorten a row the reward has since
  // lengthened, and a live subscription from a store is never overwritten.
  const { data: held } = await db.from("user_subscriptions")
    .select("plan_id, source, status, current_period_start, stripe_subscription_id").eq("user_id", userId).maybeSingle()
  if (held && held.plan_id === planId && held.source === "stripe" && !held.stripe_subscription_id &&
      new Date(held.current_period_start ?? 0).getTime() === paidAt.getTime()) return
  if (held && held.source !== "comp" && ["trialing", "active", "grace"].includes(held.status)) {
    console.error("challenge paid while another plan is live — not written, needs a person", session.id, userId)
    return
  }

  const { error } = await db.from("user_subscriptions").upsert({
    user_id: userId,
    plan_id: planId,
    source: "stripe",
    stripe_customer_id: typeof session.customer === "string" ? session.customer : session.customer?.id ?? null,
    stripe_subscription_id: null,
    status: "active",
    current_period_start: paidAt.toISOString(),
    current_period_end: end.toISOString(),
    trial_ends_at: null,
    cancel_at_period_end: true,
    updated_at: new Date().toISOString(),
  })
  if (error) {
    if (error.code === "23503") { console.warn("user gone, dropping challenge session", session.id); return }
    throw new Error(`user_subscriptions upsert (challenge): ${error.message}`)
  }
}

// A challenger paid the difference to move up a size (the checkout is made by
// challenge-upgrade for the admin desk). Only the package's size changes: its
// dates stay, and the new pool counts from the same month.
// deno-lint-ignore no-explicit-any
async function upgradeChallenge(db: any, session: Stripe.Checkout.Session): Promise<void> {
  const m = session.metadata ?? {}
  if (session.payment_status !== "paid" || !m.user_id || !m.plan_id) return
  const { data: plan } = await db.from("subscription_plans").select("id, period").eq("id", m.plan_id).maybeSingle()
  if (!plan || plan.period !== "challenge") { console.warn("upgrade to a non-challenge plan", session.id, m.plan_id); return }
  const { data: held } = await db.from("user_subscriptions")
    .select("plan_id, source, stripe_subscription_id").eq("user_id", m.user_id).maybeSingle()
  // Only the package itself is changed; anything else is a person's call (the money is in Stripe either way).
  if (!held || held.source !== "stripe" || held.stripe_subscription_id || !String(held.plan_id ?? "").endsWith("_challenge")) {
    console.error("upgrade paid but no package to change — needs a person", session.id, m.user_id)
    return
  }
  const { error } = await db.from("user_subscriptions")
    .update({ plan_id: m.plan_id, updated_at: new Date().toISOString() }).eq("user_id", m.user_id)
  if (error) throw new Error(`user_subscriptions update (upgrade): ${error.message}`)
  if (m.application_id) {
    const { error: appErr } = await db.from("creator_applications")
      .update({ paid_plan: m.plan_id, upgraded_at: new Date(session.created * 1000).toISOString(), upgrade_amount: session.amount_total ?? null, upgrade_currency: session.currency ?? null, updated_at: new Date().toISOString() })
      .eq("id", m.application_id).eq("kind", "challenger")
    if (appErr) console.error("upgrade not written on the application", session.id, appErr.message)
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
