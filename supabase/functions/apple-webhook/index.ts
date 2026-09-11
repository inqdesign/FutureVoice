// Apple App Store Server Notifications V2 webhook — the ONLY writer of
// iOS-billed entitlements. The twin of stripe-webhook: verify the provider's
// signature, upsert user_subscriptions. The subscription row IS the
// entitlement (minutes-native model — per-day allowance via
// subscription_plans.daily_seconds); nothing is granted on renewal. The app
// itself never mints anything (StoreKitService just finishes the
// transaction).
//
// Verification is done HERE rather than by Apple's official JS library.
// `SignedDataVerifier` validates the certificate chain through node:crypto's
// `X509Certificate.verify()` / `.checkIssued()`, and the Supabase edge
// runtime implements NEITHER — it throws "Not implemented:
// crypto.X509Certificate.prototype.verify" with an empty message, so every
// notification failed identically and said nothing about why. Measured
// 2026-08-20 with a runtime self-test: the webhook had never once succeeded,
// and could not have.
//
// What replaces it does the same four things, on Web Crypto (which the
// runtime does implement) via @peculiar/x509:
//   1. read the JWS header's x5c chain (leaf → intermediate → root),
//   2. verify each link against the next one's public key,
//   3. require the root to be byte-identical to a pinned Apple root,
//   4. verify the JWS body with the leaf's public key.
// Then the payload's own claims (bundleId, appAppleId, environment) are
// checked — the library did that too, and skipping it would accept a
// perfectly-signed notification meant for somebody else's app. The nested
// signedTransactionInfo / signedRenewalInfo take the same path.
// verify_jwt = false — Apple can't send a Supabase JWT.
//
// User mapping: StoreKitService.purchase() sets appAccountToken to the
// Supabase user id, so an in-app purchase carries the uuid. A transaction
// WITHOUT one — an offer code redeemed from a link, a restore, a purchase
// from the App Store's own page — is attributed through
// `user_subscriptions.apple_original_tx_id`, which `apple-claim` writes when
// the app hands us the transaction. Only a transaction nobody has claimed yet
// is dropped (2026-09-11; until then every token-less one was).
//
// App Store Connect setup:
//   App → App Information → App Store Server Notifications
//   → Production + Sandbox URL: https://<project>.supabase.co/functions/v1/apple-webhook
//   → Version 2 notifications
//
// Env: APPLE_BUNDLE_ID (com.roro.futurevoice), APPLE_APP_ID (numeric App
// Apple ID from ASC — required for production verification).

import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { Buffer } from "node:buffer"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0"
// The chain check itself lives in _shared/apple-jws.ts since 2026-09-11, so
// apple-claim verifies a transaction the app hands over EXACTLY the way this
// verifies a notification.
import { verifyAppleJWS as verifyJWS } from "../_shared/apple-jws.ts"

const SOURCE_FN = "apple-webhook"

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "method not allowed" })

  const bundleId = Deno.env.get("APPLE_BUNDLE_ID")
  const appAppleId = Number(Deno.env.get("APPLE_APP_ID") ?? "")
  if (!bundleId) return json(500, { error: "server missing APPLE_BUNDLE_ID" })

  let body: { signedPayload?: string }
  try { body = await req.json() } catch { return json(400, { error: "invalid json" }) }
  if (!body.signedPayload) return json(400, { error: "missing signedPayload" })

  const decoded = await decodeNotification(body.signedPayload, bundleId, appAppleId)
  if (!decoded) return json(401, { error: "signature verification failed" })
  const { payload, environment } = decoded

  const db = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  )

  try {
    const data = payload.data
    if (!data?.signedTransactionInfo) return json(200, { received: true }) // e.g. TEST notification

    // Nested payloads are separately signed by Apple and get the same
    // treatment — decoding them unverified would leave the amount, the
    // product and the account token forgeable inside a genuine envelope.
    const tx = await verifyJWS(data.signedTransactionInfo)
    const renewal = data.signedRenewalInfo
      ? await verifyJWS(data.signedRenewalInfo)
      : null

    let userId: string | undefined = tx.appAccountToken
    if (!userId && tx.originalTransactionId) {
      // No token: not an in-app purchase. If the app has already claimed
      // this subscription (apple-claim), the row names its owner and every
      // later renewal/expiry lands there.
      const { data: owner } = await db
        .from("user_subscriptions")
        .select("user_id")
        .eq("apple_original_tx_id", tx.originalTransactionId)
        .maybeSingle()
      userId = owner?.user_id
    }
    if (!userId) {
      // Nobody has claimed it yet. The app will, on its next launch, and the
      // claim carries the same dates — so acknowledge; Apple must not retry.
      console.warn("transaction without appAccountToken and no claim", tx.originalTransactionId)
      return json(200, { received: true })
    }

    const { data: plan } = await db
      .from("subscription_plans")
      .select("id")
      .eq("apple_product_id", tx.productId ?? "")
      .maybeSingle()
    if (!plan) {
      console.error("unknown apple product", tx.productId)
      return json(200, { received: true })
    }

    const isTrial = tx.offerDiscountType === "FREE_TRIAL"
    const status = statusFor(payload.notificationType, payload.subtype, isTrial)

    const { error: subErr } = await db.from("user_subscriptions").upsert({
      user_id: userId,
      plan_id: plan.id,
      source: "apple",
      apple_original_tx_id: tx.originalTransactionId,
      status,
      current_period_start: tx.purchaseDate ? iso(tx.purchaseDate) : null,
      current_period_end: tx.expiresDate ? iso(tx.expiresDate) : null,
      trial_ends_at: isTrial && tx.expiresDate ? iso(tx.expiresDate) : null,
      cancel_at_period_end: renewal ? renewal.autoRenewStatus === 0 : false,
      updated_at: new Date().toISOString(),
    })
    if (subErr) {
      // Account deleted between purchase and notification — drop, don't retry.
      if (subErr.code === "23503") {
        console.warn("user gone, dropping apple event", tx.originalTransactionId)
        return json(200, { received: true })
      }
      throw new Error(`user_subscriptions upsert: ${subErr.message}`)
    }

    // Revenue, as Apple actually charged it. `price` (milliunits of
    // `currency`) is the only honest figure available: it already accounts for
    // the storefront's price tier, the local currency and any intro offer,
    // none of which a hardcoded plan price knows about. It was being decoded
    // and thrown away until 2026-08-23, which left margin uncomputable.
    //
    // Upserted on transaction_id so Apple's retries are idempotent, and its
    // failure is logged rather than thrown: this is measurement, and it must
    // not be able to fail an entitlement that was already written.
    const { error: txErr } = await db.from("subscription_transactions").upsert({
      transaction_id:          tx.transactionId ?? `${tx.originalTransactionId}:${tx.purchaseDate}`,
      original_transaction_id: tx.originalTransactionId ?? null,
      user_id:                 userId,
      plan_id:                 plan.id,
      apple_product_id:        tx.productId ?? null,
      price_milliunits:        typeof tx.price === "number" ? tx.price : null,
      currency:                tx.currency ?? null,
      purchase_date:           tx.purchaseDate ? iso(tx.purchaseDate) : null,
      expires_date:            tx.expiresDate ? iso(tx.expiresDate) : null,
      is_trial:                isTrial,
      is_upgrade:              payload.subtype === "UPGRADE",
      revocation_date:         tx.revocationDate ? iso(tx.revocationDate) : null,
      // Which offer priced this period, if any — what Me → Talk time reads
      // to say "code discount running" (20260912100000).
      offer_type:              typeof tx.offerType === "number" ? tx.offerType : null,
      offer_discount_type:     tx.offerDiscountType ?? null,
      offer_period:            tx.offerPeriod ?? null,
      notification_type:       payload.notificationType ?? null,
      subtype:                 payload.subtype ?? null,
      environment,
    }, { onConflict: "transaction_id" })
    if (txErr) console.error("subscription_transactions upsert", txErr.message)

    // Minutes-native model: the subscription row upserted above IS the
    // entitlement — an entitled status buys the plan's per-day allowance
    // (subscription_plans.daily_seconds), checked live by
    // consume_metered_seconds. Nothing to grant on entry or renewal; the
    // seconds balance belongs to free users only.
  } catch (e) {
    // Non-2xx → Apple retries with backoff; grants are idempotent so that's safe.
    console.error("apple-webhook failed", payload?.notificationType, e)
    return json(500, { error: "handler failed" })
  }

  return json(200, { received: true })
})

// ── helpers ────────────────────────────────────────────────────

/**
 * Verify a notification and confirm it is addressed to THIS app. Sandbox and
 * Production are both accepted — TestFlight bills through Sandbox — but the
 * payload has to say which it is, and `appAppleId` is only present, and only
 * checked, in Production.
 */
async function decodeNotification(
  signedPayload: string,
  bundleId: string,
  appAppleId: number,
) {
  let payload: Record<string, any>
  try {
    payload = await verifyJWS(signedPayload)
  } catch (e) {
    console.error("apple-webhook signature rejected", {
      reason: (e as Error)?.message || String(e),
      unverifiedClaims: peekUnverified(signedPayload),
    })
    return null
  }

  const data = payload.data ?? {}
  if (data.bundleId && data.bundleId !== bundleId) {
    console.error("apple-webhook wrong bundle", { got: data.bundleId, want: bundleId })
    return null
  }
  if (data.environment === "Production" && appAppleId && data.appAppleId !== appAppleId) {
    console.error("apple-webhook wrong app id", { got: data.appAppleId, want: appAppleId })
    return null
  }
  return { payload, environment: data.environment ?? "unknown" }
}

/** JWS payload claims WITHOUT signature checking — diagnostics only. */
function peekUnverified(signedPayload: string) {
  try {
    const [, body] = signedPayload.split(".")
    const json = JSON.parse(
      Buffer.from(body.replace(/-/g, "+").replace(/_/g, "/"), "base64").toString("utf8"),
    )
    const tx = json?.data?.signedTransactionInfo
    return {
      notificationType: json?.notificationType,
      subtype: json?.subtype,
      environment: json?.data?.environment,
      bundleId: json?.data?.bundleId,
      appAppleId: json?.data?.appAppleId,
      hasTransaction: typeof tx === "string",
    }
  } catch (e) {
    return { peekFailed: (e as Error)?.message ?? String(e) }
  }
}

/// Maps notification type (+subtype) to our status vocabulary:
/// 'trialing' | 'active' | 'grace' | 'expired' | 'inactive'
function statusFor(type?: string, subtype?: string, isTrial?: boolean): string {
  switch (type) {
    case "SUBSCRIBED":
    case "DID_RENEW":
    case "OFFER_REDEEMED":
    case "DID_CHANGE_RENEWAL_PREF":
      return isTrial ? "trialing" : "active"
    case "DID_CHANGE_RENEWAL_STATUS":
      // Auto-renew toggled; the sub itself is still whatever it was.
      return isTrial ? "trialing" : "active"
    case "DID_FAIL_TO_RENEW":
      return subtype === "GRACE_PERIOD" ? "grace" : "expired"
    case "GRACE_PERIOD_EXPIRED":
    case "EXPIRED":
    case "REFUND":
    case "REVOKE":
      return "expired"
    default:
      return "active"
  }
}

function iso(epochMs: number): string {
  return new Date(epochMs).toISOString()
}

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  })
}
