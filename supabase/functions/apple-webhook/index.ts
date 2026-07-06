// Apple App Store Server Notifications V2 webhook — the ONLY writer of
// iOS-billed entitlements. The twin of stripe-webhook: verify the provider's
// signature, upsert user_subscriptions, grant credits idempotently via
// grant_credits(). The app itself never mints anything (StoreKitService just
// finishes the transaction).
//
// Verification uses Apple's official JS library (SignedDataVerifier): the
// signedPayload JWS is checked against Apple's pinned root CAs, and the
// nested signedTransactionInfo / signedRenewalInfo JWS are decoded the same
// way. verify_jwt = false — Apple can't send a Supabase JWT.
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
import {
  SignedDataVerifier,
  Environment,
} from "npm:@apple/app-store-server-library@1.5.0"
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

  // TestFlight bills through Sandbox, production through Production — accept
  // both. Each verifier enforces its own environment, so try Production
  // first and fall back to Sandbox on a mismatch.
  const decoded = await decodeWithEitherEnvironment(body.signedPayload, bundleId, appAppleId)
  if (!decoded) return json(401, { error: "signature verification failed" })
  const { verifier, payload, environment } = decoded

  const db = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  )

  try {
    const data = payload.data
    if (!data?.signedTransactionInfo) return json(200, { received: true }) // e.g. TEST notification

    const tx = await verifier.verifyAndDecodeTransaction(data.signedTransactionInfo)
    const renewal = data.signedRenewalInfo
      ? await verifier.verifyAndDecodeRenewalInfo(data.signedRenewalInfo)
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
      .select("id, credits_per_cycle")
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

    // Grant credits on entry + every renewal. Trial starts grant the full
    // cycle too (schema doc: "the webhook just grants the same credits as a
    // paid Pro Monthly when trial starts"). transactionId is unique per
    // renewal, so the idempotency key makes Apple's redeliveries no-ops.
    const grants = payload.notificationType === "SUBSCRIBED"
      || payload.notificationType === "DID_RENEW"
      || payload.notificationType === "OFFER_REDEEMED"
    if (grants) {
      const { error: rpcErr } = await db.rpc("grant_credits", {
        p_user_id: userId,
        p_credits: plan.credits_per_cycle,
        p_kind: "grant",
        p_action: "cycle_grant",
        p_source_fn: SOURCE_FN,
        p_idempotency_key: `apple_tx_${tx.transactionId}`,
        p_metadata: {
          apple_tx: tx.transactionId,
          apple_original_tx: tx.originalTransactionId,
          plan_id: plan.id,
          environment,
          notification: payload.notificationType,
        },
      })
      if (rpcErr && rpcErr.code !== "23503") {
        throw new Error(`grant_credits: ${rpcErr.message}`)
      }
      if (!rpcErr) {
        const { error: credErr } = await db.from("user_credits").update({
          period_start: tx.purchaseDate ? iso(tx.purchaseDate) : null,
          period_end: tx.expiresDate ? iso(tx.expiresDate) : null,
          cycle_grant: plan.credits_per_cycle,
          updated_at: new Date().toISOString(),
        }).eq("user_id", userId)
        if (credErr) throw new Error(`user_credits period update: ${credErr.message}`)
      }
    }
  } catch (e) {
    // Non-2xx → Apple retries with backoff; grants are idempotent so that's safe.
    console.error("apple-webhook failed", payload?.notificationType, e)
    return json(500, { error: "handler failed" })
  }

  return json(200, { received: true })
})

// ── helpers ────────────────────────────────────────────────────

async function decodeWithEitherEnvironment(
  signedPayload: string,
  bundleId: string,
  appAppleId: number,
) {
  for (const environment of [Environment.PRODUCTION, Environment.SANDBOX]) {
    try {
      const verifier = new SignedDataVerifier(
        ROOT_CAS,
        false, // no online OCSP from the edge runtime
        environment,
        bundleId,
        environment === Environment.PRODUCTION ? appAppleId : undefined,
      )
      const payload = await verifier.verifyAndDecodeNotification(signedPayload)
      return { verifier, payload, environment }
    } catch {
      continue
    }
  }
  return null
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
