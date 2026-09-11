// apple-claim: the APP hands us a StoreKit transaction, and it becomes the
// signed-in user's subscription.
//
// Why this exists (2026-09-11). The only way a subscription reached the
// database was Apple's server notification, attributed through the
// `appAccountToken` that StoreKitService.purchase() stamps on an in-app
// purchase. Anything bought OUTSIDE that call has no token: an App Store
// Offer Code redeemed from a link, a purchase restored on a new phone, a
// subscription started from the App Store's own page. The webhook logged
// those and dropped them — the person was paying Apple and the app showed
// "No plan". With the beta ending on half-price offer codes, that was every
// single recipient.
//
// The app now sends every verified current entitlement here as its JWS
// (`Transaction.jwsRepresentation`), on launch and whenever StoreKit delivers
// one. The signature is Apple's, checked exactly as the webhook checks a
// notification (_shared/apple-jws.ts), so a client cannot mint anything: it
// can only tell us about a transaction Apple really signed, for a product we
// really sell, and we file it under the session that sent it. Once filed,
// `apple_original_tx_id` is what lets the webhook attribute every later
// renewal and expiry for that subscription without a token (see the fallback
// in apple-webhook).
//
// Rules, in order:
//   * bundle must be ours, product must be in `subscription_plans`;
//   * a transaction already filed under ANOTHER user is refused (409) — one
//     Apple subscription, one account;
//   * an active row from another source (stripe, comp) is REPLACED only if
//     the Apple transaction is live: a comp is what the beta testers hold,
//     and redeeming the code is precisely how they leave it;
//   * an expired/revoked transaction never downgrades a live row from
//     anywhere else, and never writes over a live Apple row for a different
//     original transaction (an old, lapsed subscription re-sent by StoreKit
//     must not clobber the current one).
//
// Response: { status, plan_id, applied } — `applied: false` means the row
// was already at least this current and nothing changed.

import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0"
import { requireUser, handlePreflight, errorResponse, cors } from "../_shared/auth.ts"
import { verifyAppleJWS, peekJWSUnverified, isoFromMs } from "../_shared/apple-jws.ts"

const LIVE = new Set(["trialing", "active", "grace"])

Deno.serve(async (req) => {
  const pre = handlePreflight(req)
  if (pre) return pre
  if (req.method !== "POST") return errorResponse(405, "method not allowed")

  const authed = await requireUser(req)
  if (authed instanceof Response) return authed
  const userId = authed.user.id

  const bundleId = Deno.env.get("APPLE_BUNDLE_ID")
  if (!bundleId) return errorResponse(500, "server missing APPLE_BUNDLE_ID")

  let body: any
  try { body = await req.json() } catch { return errorResponse(400, "invalid json") }
  const jws = typeof body?.jws === "string" ? body.jws : null
  if (!jws) return errorResponse(400, "missing jws")

  let tx: Record<string, any>
  try {
    tx = await verifyAppleJWS(jws)
  } catch (e) {
    console.error("apple-claim signature rejected", {
      reason: (e as Error)?.message ?? String(e),
      unverified: peekJWSUnverified(jws),
      user: userId,
    })
    return errorResponse(401, "signature verification failed")
  }

  if (tx.bundleId && tx.bundleId !== bundleId) {
    console.error("apple-claim wrong bundle", { got: tx.bundleId, want: bundleId, user: userId })
    return errorResponse(400, "wrong bundle")
  }
  if (tx.type && tx.type !== "Auto-Renewable Subscription") {
    return errorResponse(400, "not a subscription")
  }
  const originalTxId: string | undefined = tx.originalTransactionId
  if (!originalTxId) return errorResponse(400, "transaction has no originalTransactionId")

  const db = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  )

  const { data: plan } = await db
    .from("subscription_plans")
    .select("id")
    .eq("apple_product_id", tx.productId ?? "")
    .maybeSingle()
  if (!plan) {
    console.error("apple-claim unknown product", tx.productId)
    return errorResponse(400, "unknown product")
  }

  // One Apple subscription belongs to one account. If somebody else already
  // filed this original transaction, this session does not get it — the
  // webhook keeps writing to the first claimant.
  const { data: holder } = await db
    .from("user_subscriptions")
    .select("user_id")
    .eq("apple_original_tx_id", originalTxId)
    .neq("user_id", userId)
    .maybeSingle()
  if (holder) {
    console.warn("apple-claim already held by another user", { originalTxId, user: userId })
    return errorResponse(409, "subscription belongs to another account")
  }

  const nowMs = Date.now()
  const revoked = typeof tx.revocationDate === "number"
  const expiresMs: number | undefined = typeof tx.expiresDate === "number" ? tx.expiresDate : undefined
  const live = !revoked && expiresMs !== undefined && expiresMs > nowMs
  const isTrial = tx.offerDiscountType === "FREE_TRIAL"
  const status = live ? (isTrial ? "trialing" : "active") : "expired"

  const { data: existing } = await db
    .from("user_subscriptions")
    .select("source, status, apple_original_tx_id, current_period_end")
    .eq("user_id", userId)
    .maybeSingle()

  // Never let a dead transaction take a live row down — from any source, and
  // in particular not a live Apple row for a DIFFERENT subscription.
  if (!live && existing && LIVE.has(existing.status)
      && existing.apple_original_tx_id !== originalTxId) {
    return json({ status: existing.status, plan_id: null, applied: false, reason: "live row kept" })
  }
  // Same subscription, and the row already describes a period at least as
  // late as this transaction: a renewal notification already landed.
  if (existing && existing.apple_original_tx_id === originalTxId
      && existing.current_period_end && expiresMs !== undefined
      && Date.parse(existing.current_period_end) >= expiresMs
      && (LIVE.has(existing.status) === live)) {
    return json({ status: existing.status, plan_id: plan.id, applied: false, reason: "already current" })
  }

  const { error: subErr } = await db.from("user_subscriptions").upsert({
    user_id: userId,
    plan_id: plan.id,
    source: "apple",
    apple_original_tx_id: originalTxId,
    stripe_subscription_id: null,
    status,
    current_period_start: typeof tx.purchaseDate === "number" ? isoFromMs(tx.purchaseDate) : null,
    current_period_end: expiresMs !== undefined ? isoFromMs(expiresMs) : null,
    trial_ends_at: isTrial && expiresMs !== undefined ? isoFromMs(expiresMs) : null,
    // StoreKit's transaction carries no renewal info; the webhook's next
    // notification for this original transaction fills it in.
    cancel_at_period_end: false,
    updated_at: new Date().toISOString(),
  })
  if (subErr) {
    console.error("apple-claim upsert failed", subErr.message)
    return errorResponse(500, "could not record subscription")
  }

  // Measurement, same shape the webhook writes; a failure here is logged and
  // never fails the entitlement above.
  const { error: txErr } = await db.from("subscription_transactions").upsert({
    transaction_id:          tx.transactionId ?? `${originalTxId}:${tx.purchaseDate}`,
    original_transaction_id: originalTxId,
    user_id:                 userId,
    plan_id:                 plan.id,
    apple_product_id:        tx.productId ?? null,
    price_milliunits:        typeof tx.price === "number" ? tx.price : null,
    currency:                tx.currency ?? null,
    purchase_date:           typeof tx.purchaseDate === "number" ? isoFromMs(tx.purchaseDate) : null,
    expires_date:            expiresMs !== undefined ? isoFromMs(expiresMs) : null,
    is_trial:                isTrial,
    is_upgrade:              false,
    revocation_date:         revoked ? isoFromMs(tx.revocationDate) : null,
    notification_type:       "CLIENT_CLAIM",
    subtype:                 tx.offerType != null ? `offerType:${tx.offerType}` : null,
    environment:             tx.environment ?? "unknown",
  }, { onConflict: "transaction_id" })
  if (txErr) console.error("apple-claim subscription_transactions upsert", txErr.message)

  console.log("apple-claim filed", { user: userId, originalTxId, plan: plan.id, status, offerType: tx.offerType })
  return json({ status, plan_id: plan.id, applied: true })
})

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...cors() },
  })
}
