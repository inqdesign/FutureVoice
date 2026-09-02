// Creates a Stripe Billing Portal session for the signed-in user.
//
// Body: { return_url?: string }
// Returns: { url } — the Stripe-hosted portal (cancel, change plan, update card).
//
// Why this exists: a web (Stripe) subscription cannot be cancelled from the
// App Store's subscription settings, so without this the product has a way
// to charge and no way to stop. The portal is Stripe-hosted — nothing here
// mutates anything; every change flows back through stripe-webhook, which
// stays the only writer of web entitlements.
//
// Portal configuration lives in the Stripe dashboard (Settings → Billing →
// Customer portal). Plan switching may be left ON: stripe-webhook resolves
// the plan from the subscription's live price, not from checkout metadata.

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

  let body: { return_url?: string }
  try { body = await req.json() } catch { body = {} }

  // Only allow redirect back to our own site (same rule as stripe-checkout).
  const site = Deno.env.get("SITE_URL")
  const returnUrl = body.return_url && site && body.return_url.startsWith(site)
    ? body.return_url
    : site
  if (!returnUrl) return errorResponse(500, "server missing SITE_URL")

  // RLS: owner-read on user_subscriptions. A user who never bought on the
  // web has no Stripe customer — there is nothing to open a portal on.
  const { data: row } = await supabase
    .from("user_subscriptions")
    .select("stripe_customer_id")
    .eq("user_id", user.id)
    .maybeSingle()
  if (!row?.stripe_customer_id) return errorResponse(404, "no_web_subscription")

  const stripe = new Stripe(stripeKey, { httpClient: Stripe.createFetchHttpClient() })

  let session: Stripe.BillingPortal.Session
  try {
    session = await stripe.billingPortal.sessions.create({
      customer: row.stripe_customer_id,
      return_url: returnUrl,
    })
  } catch (e) {
    const msg = e instanceof Error ? e.message : "stripe error"
    console.error("stripe portal session failed", msg)
    return errorResponse(502, "stripe error", msg)
  }

  return new Response(JSON.stringify({ url: session.url }), {
    headers: { "Content-Type": "application/json", ...cors() },
  })
})
