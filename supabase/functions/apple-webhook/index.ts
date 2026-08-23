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
// Supabase user id, so every notification carries the uuid. Transactions
// without it (purchases made before that build) are logged and dropped.
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
import * as x509 from "npm:@peculiar/x509@1.12.3"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0"

const SOURCE_FN = "apple-webhook"

// Apple's public root CAs, pinned (downloaded from
// https://www.apple.com/certificateauthority/ — G3 signs current App Store
// receipts; G2 kept for completeness).
const APPLE_ROOT_CA_G3_B64 =
  "MIICQzCCAcmgAwIBAgIILcX8iNLFS5UwCgYIKoZIzj0EAwMwZzEbMBkGA1UEAwwSQXBwbGUgUm9vdCBDQSAtIEczMSYwJAYDVQQLDB1BcHBsZSBDZXJ0aWZpY2F0aW9uIEF1dGhvcml0eTETMBEGA1UECgwKQXBwbGUgSW5jLjELMAkGA1UEBhMCVVMwHhcNMTQwNDMwMTgxOTA2WhcNMzkwNDMwMTgxOTA2WjBnMRswGQYDVQQDDBJBcHBsZSBSb290IENBIC0gRzMxJjAkBgNVBAsMHUFwcGxlIENlcnRpZmljYXRpb24gQXV0aG9yaXR5MRMwEQYDVQQKDApBcHBsZSBJbmMuMQswCQYDVQQGEwJVUzB2MBAGByqGSM49AgEGBSuBBAAiA2IABJjpLz1AcqTtkyJygRMc3RCV8cWjTnHcFBbZDuWmBSp3ZHtfTjjTuxxEtX/1H7YyYl3J6YRbTzBPEVoA/VhYDKX1DyxNB0cTddqXl5dvMVztK517IDvYuVTZXpmkOlEKMaNCMEAwHQYDVR0OBBYEFLuw3qFYM4iapIqZ3r6966/ayySrMA8GA1UdEwEB/wQFMAMBAf8wDgYDVR0PAQH/BAQDAgEGMAoGCCqGSM49BAMDA2gAMGUCMQCD6cHEFl4aXTQY2e3v9GwOAEZLuN+yRhHFD/3meoyhpmvOwgPUnPWTxnS4at+qIxUCMG1mihDK1A3UT82NQz60imOlM27jbdoXt2QfyFMm+YhidDkLF1vLUagM6BgD56KyKA=="
const APPLE_ROOT_CA_G2_B64 =
  "MIIFkjCCA3qgAwIBAgIIAeDltYNno+AwDQYJKoZIhvcNAQEMBQAwZzEbMBkGA1UEAwwSQXBwbGUgUm9vdCBDQSAtIEcyMSYwJAYDVQQLDB1BcHBsZSBDZXJ0aWZpY2F0aW9uIEF1dGhvcml0eTETMBEGA1UECgwKQXBwbGUgSW5jLjELMAkGA1UEBhMCVVMwHhcNMTQwNDMwMTgxMDA5WhcNMzkwNDMwMTgxMDA5WjBnMRswGQYDVQQDDBJBcHBsZSBSb290IENBIC0gRzIxJjAkBgNVBAsMHUFwcGxlIENlcnRpZmljYXRpb24gQXV0aG9yaXR5MRMwEQYDVQQKDApBcHBsZSBJbmMuMQswCQYDVQQGEwJVUzCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBANgREkhI2imKScUcx+xuM23+TfvgHN6sXuI2pyT5f1BrTM65MFQn5bPW7SXmMLYFN14UIhHF6Kob0vuy0gmVOKTvKkmMXT5xZgM4+xb1hYjkWpIMBDLyyED7Ul+f9sDx47pFoFDVEovy3d6RhiPw9bZyLgHaC/YuOQhfGaFjQQscp5TBhsRTL3b2CtcM0YM/GlMZ81fVJ3/8E7j4ko380yhDPLVoACVdJ2LT3VXdRCCQgzWTxb+4Gftr49wIQuavbfqeQMpOhYV4SbHXw8EwOTKrfl+q04tvny0aIWhwZ7Oj8ZhBbZF8+NfbqOdfIRqMM78xdLe40fTgIvS/cjTf94FNcX1RoeKz8NMoFnNvzcytN31O661A4T+B/fc9Cj6i8b0xlilZ3MIZgIxbdMYs0xBTJh0UT8TUgWY8h2czJxQI6bR3hDRSj4n4aJgXv8O7qhOTH11UL6jHfPsNFL4VPSQ08prcdUFmIrQB1guvkJ4M6mL4m1k8COKWNORj3rw31OsMiANDC1CvoDTdUE0V+1ok2Az6DGOeHwOx4e7hqkP0ZmUoNwIx7wHHHtHMn23KVDpA287PT0aLSmWaasZobNfMmRtHsHLDd4/E92GcdB/O/WuhwpyUgquUoue9G7q5cDmVF8Up8zlYNPXEpMZ7YLlmQ1A/bmH8DvmGqmAMQ0uVAgMBAAGjQjBAMB0GA1UdDgQWBBTEmRNsGAPCe8CjoA1/coB6HHcmjTAPBgNVHRMBAf8EBTADAQH/MA4GA1UdDwEB/wQEAwIBBjANBgkqhkiG9w0BAQwFAAOCAgEAUabz4vS4PZO/Lc4Pu1vhVRROTtHlznldgX/+tvCHM/jvlOV+3Gp5pxy+8JS3ptEwnMgNCnWefZKVfhidfsJxaXwU6s+DDuQUQp50DhDNqxq6EWGBeNjxtUVAeKuowM77fWM3aPbn+6/Gw0vsHzYmE1SGlHKy6gLti23kDKaQwFd1z4xCfVzmMX3zybKSaUYOiPjjLUKyOKimGY3xn83uamW8GrAlvacp/fQ+onVJv57byfenHmOZ4VxG/5IFjPoeIPmGlFYl5bRXOJ3riGQUIUkhOb9iZqmxospvPyFgxYnURTbImHy99v6ZSYA7LNKmp4gDBDEZt7Y6YUX6yfIjyGNzv1aJMbDZfGKnexWoiIqrOEDCzBL/FePwN983csvMmOa/orz6JopxVtfnJBtIRD6e/J/JzBrsQzwBvDR4yGn1xuZW7AYJNpDrFEobXsmII9oDMJELuDY++ee1KG++P+w8j2Ud5cAeh6Squpj9kuNsJnfdBrRkBof0Tta6SqoWqPQFZ2aWuuJVecMsXUmPgEkrihLHdoBR37q9ZV0+N0djMenl9MU/S60EinpxLK8JQzcPqOMyT/RFtm2XNuyE9QoB6he7hY1Ck3DDUOUUi78/w0EP3SIEIwiKum1xRKtzCTrJ+VKACd+66eYWyi4uTLLT3OUEVLLUNIAytbwPF+E="

const ROOT_CAS = [
  Buffer.from(APPLE_ROOT_CA_G3_B64, "base64"),
  Buffer.from(APPLE_ROOT_CA_G2_B64, "base64"),
]

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

    const userId = tx.appAccountToken
    if (!userId) {
      // Purchase from a build that didn't set appAccountToken — nothing to
      // attribute it to. Acknowledge so Apple stops retrying.
      console.warn("transaction without appAccountToken", tx.originalTransactionId)
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

async function verifyJWS(jws: string): Promise<Record<string, any>> {
  const [rawHeader, rawBody, rawSig] = jws.split(".")
  if (!rawHeader || !rawBody || !rawSig) throw new Error("malformed JWS")

  const header = JSON.parse(b64url(rawHeader).toString("utf8"))
  if (header.alg !== "ES256") throw new Error(`unexpected alg ${header.alg}`)
  const chain: string[] = header.x5c ?? []
  if (chain.length < 2) throw new Error(`x5c too short (${chain.length})`)

  const certs = chain.map((c) => new x509.X509Certificate(Buffer.from(c, "base64")))

  // The pinned end of the chain. Byte equality rather than "the issuer name
  // looks right": a forged chain can restate any name it likes, and this is
  // the one link an attacker cannot.
  const rootDer = new Uint8Array(certs[certs.length - 1].rawData)
  if (!ROOT_CAS.some((pinned) => equalBytes(new Uint8Array(pinned), rootDer))) {
    throw new Error("chain does not end at a pinned Apple root")
  }

  // Every link verified against the next one's key. Without this, the check
  // above would let anyone append Apple's (public) root to their own leaf.
  const now = new Date()
  for (let i = 0; i < certs.length; i++) {
    const cert = certs[i]
    if (now < cert.notBefore || now > cert.notAfter) {
      throw new Error(`cert ${i} outside its validity window`)
    }
    if (i + 1 < certs.length) {
      const ok = await cert.verify({ publicKey: certs[i + 1].publicKey, signatureOnly: true })
      if (!ok) throw new Error(`cert ${i} not signed by cert ${i + 1}`)
    }
  }

  const key = await certs[0].publicKey.export()
  const ok = await crypto.subtle.verify(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    b64url(rawSig),
    new TextEncoder().encode(`${rawHeader}.${rawBody}`),
  )
  if (!ok) throw new Error("JWS signature does not match the leaf certificate")

  return JSON.parse(b64url(rawBody).toString("utf8"))
}

function b64url(s: string): Buffer {
  return Buffer.from(s.replace(/-/g, "+").replace(/_/g, "/"), "base64")
}

function equalBytes(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false
  for (let i = 0; i < a.length; i++) if (a[i] !== b[i]) return false
  return true
}

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
