// Creates a Stripe Checkout Session for a subscription plan.
//
// Body: { plan_id: string, return_url: string }
// Returns: { url } — the Stripe-hosted checkout page to redirect to.
//
// Auth: standard verified-JWT function (verify_jwt = true). The signed-in
// Supabase user id rides along in the session + subscription metadata, so
// stripe-webhook can attribute every later event to the right user without
// any email matching (Apple relay emails make email matching unreliable).

import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import Stripe from "npm:stripe@17"
import { requireUser, handlePreflight, errorResponse, cors } from "../_shared/auth.ts"

Deno.serve(async (req) => {
  const pre = handlePreflight(req)
  if (pre) return pre
  if (req.method !== "POST") return errorResponse(405, "method not allowed")

  const authed = await requireUser(req)
  if (authed instanceof Response) return authed
  const { user, supabase } = authed

  const stripeKey = Deno.env.get("STRIPE_SECRET_KEY")
  if (!stripeKey) return errorResponse(500, "server missing STRIPE_SECRET_KEY")

  let body: { plan_id?: string; return_url?: string; currency?: string; challenge_ref?: string }
  try { body = await req.json() } catch { return errorResponse(400, "invalid json body") }
  const planId = body.plan_id
  if (!planId) return errorResponse(400, "missing plan_id")

  // The page passes the currency it DISPLAYED (ko page prints ₩, en page $),
  // so the buyer is charged the number they read. Only honored when the
  // Stripe Price carries that currency_option — see web/README.md.
  // The 100-day challenge is priced in every currency the App Store prices Light in; a
  // currency its Price does not carry is refused by Stripe, so only those are let through.
  const CHALLENGE_CURRENCIES = ["aed", "aud", "brl", "cad", "chf", "clp", "cny", "cop", "czk", "dkk", "egp", "gbp", "hkd", "huf", "idr", "ils", "inr", "kzt", "mxn", "myr", "ngn", "nok", "nzd", "pen", "php", "pkr", "pln", "qar", "ron", "sar", "sek", "sgd", "thb", "try", "twd", "tzs", "vnd", "zar"]
  const currency = body.currency && (["usd", "eur", "krw", "jpy"].includes(body.currency) ||
    (CHALLENGE_CURRENCIES.includes(body.currency) && /_challenge$/.test(planId)))
    ? body.currency
    : undefined

  // Only allow redirect back to our own site.
  const site = Deno.env.get("SITE_URL")
  const returnUrl = body.return_url && site && (body.return_url === site || body.return_url.startsWith(site.replace(/\/$/, "") + "/"))
    ? body.return_url
    : site
  if (!returnUrl) return errorResponse(500, "server missing SITE_URL")

  // Plan catalog is public-read; stripe_price_id must be configured.
  const { data: plan, error: planErr } = await supabase
    .from("subscription_plans")
    .select("id, stripe_price_id, is_active, period")
    .eq("id", planId)
    .single()
  if (planErr || !plan) return errorResponse(400, "unknown plan")
  if (!plan.is_active) {
    // Off the stores' shelf is not off the web's: a plan with no App Store or
    // Play product (max_annual) is kept inactive so no paywall lists it, and
    // `sold_on_web` says the site may sell it. Asked for in its own query, so
    // this function never depends on the column for a plan that is active.
    const { data: web } = await supabase
      .from("subscription_plans")
      .select("sold_on_web")
      .eq("id", planId)
      .maybeSingle()
    if (!web?.sold_on_web) return errorResponse(400, "plan is not active")
  }
  if (!plan.stripe_price_id) return errorResponse(400, "plan not configured for web billing")

  // One row per user (user_id is the PK): a second purchase while an
  // entitled row exists would take the buyer's money and overwrite the
  // entitlement they already have. The two-store policy (see the Google
  // scaffold migration) is to REFUSE the second purchase, so:
  //  - entitled via Stripe  → 409 already_subscribed (manage via the portal)
  //  - entitled via a store → 409 store_subscription_active (cancel there first)
  const { data: existing } = await supabase
    .from("user_subscriptions")
    .select("stripe_customer_id, source, status")
    .eq("user_id", user.id)
    .maybeSingle()

  // A comp (a free code: beta testers, creators, a free month) is not a
  // purchase and has no store to cancel it in, so it never blocks one: buying
  // replaces it, the rule apple-claim has for a live Apple transaction. The
  // webhook's upsert writes source = "stripe" over the row, and the comp sweep
  // only ends rows whose source is still "comp".
  const entitled = existing && existing.source !== "comp" &&
    ["trialing", "active", "grace"].includes(existing.status)
  if (entitled) {
    return existing.source === "stripe"
      ? errorResponse(409, "already_subscribed")
      : errorResponse(409, "store_subscription_active", existing.source)
  }

  // No trial on the web, as in the store since 2026-09-26: the free first
  // 20 minutes (user_credits.balance) are the sample, and a 7-day trial here
  // would be a free week the App Store no longer gives.

  const stripe = new Stripe(stripeKey, { httpClient: Stripe.createFetchHttpClient() })

  // The 100-day challenge package is paid ONCE: a payment, not a subscription.
  // stripe-webhook writes its 100 days from this session's metadata.
  const once = plan.period === "challenge"
  // The challenger's application, when the buyer came from the form.
  const applicationId = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(body.challenge_ref ?? "")
    ? { application_id: body.challenge_ref as string } : {}

  let session: Stripe.Checkout.Session
  try {
    session = once ? await stripe.checkout.sessions.create({
      mode: "payment",
      line_items: [{ price: plan.stripe_price_id, quantity: 1 }],
      success_url: `${returnUrl}?checkout=success`,
      cancel_url: `${returnUrl}?checkout=cancelled`,
      client_reference_id: user.id,
      metadata: { project: "futurevoice", kind: "challenge", user_id: user.id, plan_id: plan.id, ...applicationId },
      payment_intent_data: {
        metadata: { project: "futurevoice", kind: "challenge", user_id: user.id, plan_id: plan.id },
      },
      ...(currency ? { currency } : {}),
      // deno-lint-ignore no-explicit-any
      ...({ branding_settings: { display_name: "nawana" } } as any),
      ...(existing?.stripe_customer_id
        ? { customer: existing.stripe_customer_id }
        : { customer_creation: "always", ...(user.email ? { customer_email: user.email } : {}) }),
    }) : await stripe.checkout.sessions.create({
      mode: "subscription",
      line_items: [{ price: plan.stripe_price_id, quantity: 1 }],
      success_url: `${returnUrl}?checkout=success`,
      cancel_url: `${returnUrl}?checkout=cancelled`,
      client_reference_id: user.id,
      // `project` marks whose purchase this is on the SHARED Dear RoRo Stripe
      // account (humhumhum tips + DeskSquat licenses live there too; every
      // webhook on the account sees every event and filters to its own —
      // same convention as DeskCoach/payments/api/stripe-webhook.js).
      metadata: { project: "futurevoice", user_id: user.id, plan_id: plan.id },
      subscription_data: {
        metadata: { project: "futurevoice", user_id: user.id, plan_id: plan.id },
      },
      ...(currency ? { currency } : {}),
      // The Stripe account is Dear RoRo's, so the page said "Dear RoRo" above
      // "Subscribe to Nawana Plus". The name is set per session; the SDK's
      // types predate the field, the API takes it.
      // deno-lint-ignore no-explicit-any
      ...({ branding_settings: { display_name: "nawana" } } as any),
      allow_promotion_codes: true,
      // Reuse the Stripe customer when we have one; otherwise prefill the
      // receipt email (may be an Apple private-relay address — fine).
      ...(existing?.stripe_customer_id
        ? { customer: existing.stripe_customer_id }
        : user.email ? { customer_email: user.email } : {}),
    })
  } catch (e) {
    const msg = e instanceof Error ? e.message : "stripe error"
    console.error("stripe checkout session failed", msg)
    return errorResponse(502, "stripe error", msg)
  }

  return new Response(JSON.stringify({ url: session.url }), {
    headers: { "Content-Type": "application/json", ...cors() },
  })
})
