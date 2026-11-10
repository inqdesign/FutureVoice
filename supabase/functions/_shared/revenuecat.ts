// Tells RevenueCat about a Google Play purchase, so Android shows up in the
// same dashboard iOS already does (2026-11-10).
//
// iOS reaches RevenueCat through Apple's notifications (RC forwards them to
// apple-webhook). Play's notifications go straight to google-webhook: the
// RTDN topic lives in a GCP project RevenueCat's credentials cannot list, so
// RC cannot subscribe to it. Instead the two functions that already verify a
// Play purchase post its token here. RevenueCat validates the token with its
// own service credentials and tracks the subscription from then on.
//
// A record for the owner, never a gate: entitlement stays in our tables. So
// this never throws, waits at most a few seconds, and does nothing at all
// until REVENUECAT_PLAY_API_KEY (the Play app's public key in RC) is set.

const ENDPOINT = "https://api.revenuecat.com/v1/receipts"

export async function reportPlayPurchaseToRevenueCat(p: {
  userId: string          // the RC app user id — the Supabase user id, as on iOS
  purchaseToken: string
  productId: string
}): Promise<void> {
  const key = Deno.env.get("REVENUECAT_PLAY_API_KEY")
  if (!key) return
  try {
    const res = await fetch(ENDPOINT, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${key}`,
        "X-Platform": "android",
      },
      body: JSON.stringify({
        app_user_id: p.userId,
        fetch_token: p.purchaseToken,
        product_id: p.productId,
      }),
      signal: AbortSignal.timeout(4000),
    })
    if (!res.ok) {
      console.error("revenuecat refused", res.status, (await res.text()).slice(0, 300),
        { product: p.productId })
    }
  } catch (e) {
    console.error("revenuecat report failed (non-fatal)", (e as Error)?.message ?? String(e))
  }
}

// A Stripe (web) subscription, the same way (2026-11-11). RevenueCat reads the
// subscription from Stripe with its own connection to the account (the
// RevenueCat app installed there); this post says which one and WHO it
// belongs to. Posted on every event, since RevenueCat gets no Stripe webhook
// of its own and "track new purchases" stays off: the Stripe account is
// shared with other projects. Does nothing until
// REVENUECAT_STRIPE_API_KEY (the Stripe app's public key in RC) is set.
export async function reportStripeSubscriptionToRevenueCat(p: {
  userId: string
  subscriptionId: string  // sub_…
}): Promise<void> {
  const key = Deno.env.get("REVENUECAT_STRIPE_API_KEY")
  if (!key) return
  try {
    const res = await fetch(ENDPOINT, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${key}`,
        "X-Platform": "stripe",
      },
      body: JSON.stringify({
        app_user_id: p.userId,
        fetch_token: p.subscriptionId,
      }),
      signal: AbortSignal.timeout(4000),
    })
    if (!res.ok) {
      console.error("revenuecat refused", res.status, (await res.text()).slice(0, 300),
        { subscription: p.subscriptionId })
    }
  } catch (e) {
    console.error("revenuecat report failed (non-fatal)", (e as Error)?.message ?? String(e))
  }
}
