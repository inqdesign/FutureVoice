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

  let body: { plan_id?: string; return_url?: string }
  try { body = await req.json() } catch { return errorResponse(400, "invalid json body") }
  const planId = body.plan_id
  if (!planId) return errorResponse(400, "missing plan_id")

  // Only allow redirect back to our own site.
  const site = Deno.env.get("SITE_URL")
  const returnUrl = body.return_url && site && body.return_url.startsWith(site)
    ? body.return_url
    : site
  if (!returnUrl) return errorResponse(500, "server missing SITE_URL")

  // Plan catalog is public-read; stripe_price_id must be configured.
  const { data: plan, error: planErr } = await supabase
    .from("subscription_plans")
    .select("id, stripe_price_id, is_active")
    .eq("id", planId)
    .single()
  if (planErr || !plan) return errorResponse(400, "unknown plan")
  if (!plan.is_active) return errorResponse(400, "plan is not active")
  if (!plan.stripe_price_id) return errorResponse(400, "plan not configured for web billing")

  // Reuse the Stripe customer if this user bought on the web before
  // (RLS: owner-read on user_subscriptions).
  const { data: existing } = await supabase
    .from("user_subscriptions")
    .select("stripe_customer_id")
    .eq("user_id", user.id)
    .maybeSingle()

  const stripe = new Stripe(stripeKey, { httpClient: Stripe.createFetchHttpClient() })

  let session: Stripe.Checkout.Session
  try {
    session = await stripe.checkout.sessions.create({
      mode: "subscription",
      line_items: [{ price: plan.stripe_price_id, quantity: 1 }],
      success_url: `${returnUrl}?checkout=success`,
      cancel_url: `${returnUrl}?checkout=cancelled`,
      client_reference_id: user.id,
      metadata: { user_id: user.id, plan_id: plan.id },
      subscription_data: { metadata: { user_id: user.id, plan_id: plan.id } },
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
