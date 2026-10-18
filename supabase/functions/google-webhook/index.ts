// Google Play RTDN webhook — the `apple-webhook` sibling (roadmap §1.11).
//
// NOT ARMED YET: needs the owner's Play Console setup (§4.4) — a Pub/Sub
// topic pushing here with `?secret=<GOOGLE_RTDN_SECRET>`, and a service
// account with the Play Developer API for verification. Until those env vars
// exist every request is refused. Deploy together with
// 20260901100000_google_billing_scaffold.sql.
//
// Flow, mirroring apple-webhook's four steps:
//   1. authenticate the push (shared secret in the query, timing-safe),
//   2. decode the RTDN envelope (Pub/Sub base64 → DeveloperNotification),
//   3. VERIFY with Google before believing anything — fetch the subscription
//      from the Play Developer API (never trust the notification body alone),
//   4. upsert user_subscriptions: the row IS the entitlement; nothing is
//      granted on renewal (minutes-native model).
//
// User mapping: BillingService sets obfuscatedExternalAccountId to the
// Supabase user id — the appAccountToken twin.

import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0"
import { timingSafeEqual } from "../_shared/auth.ts"
import { notifyOwner } from "../_shared/credits.ts"

const PACKAGE_NAME = "com.roro.futurevoice"

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status, headers: { "Content-Type": "application/json" },
  })
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "method not allowed" })

  const secret = Deno.env.get("GOOGLE_RTDN_SECRET")
  const saEmail = Deno.env.get("GOOGLE_SA_EMAIL")
  const saKeyPem = Deno.env.get("GOOGLE_SA_KEY_PEM")
  if (!secret || !saEmail || !saKeyPem) {
    // Not armed. 503 so a mis-early Pub/Sub subscription retries later
    // instead of acking data loss.
    return json(503, { error: "google billing not configured" })
  }
  const given = new URL(req.url).searchParams.get("secret") ?? ""
  if (!timingSafeEqual(given, secret)) return json(403, { error: "forbidden" })

  // ── 2. RTDN envelope ──
  let envelope: { message?: { data?: string } }
  try { envelope = await req.json() } catch { return json(400, { error: "invalid body" }) }
  const data = envelope.message?.data
  if (!data) return json(400, { error: "missing message.data" })
  let notification: {
    packageName?: string
    testNotification?: unknown
    subscriptionNotification?: {
      purchaseToken?: string; subscriptionId?: string; notificationType?: number
    }
  }
  try {
    notification = JSON.parse(new TextDecoder().decode(
      Uint8Array.from(atob(data), (c) => c.charCodeAt(0))))
  } catch { return json(400, { error: "undecodable notification" }) }

  if (notification.testNotification) return json(200, { received: "test" })
  if (notification.packageName && notification.packageName !== PACKAGE_NAME) {
    console.warn("RTDN for foreign package", notification.packageName)
    return json(200, { received: true })
  }
  const sub = notification.subscriptionNotification
  if (!sub?.purchaseToken) return json(200, { received: true })   // voided etc. — ack, handle later

  try {
    // ── 3. Verify with Google ──
    const accessToken = await serviceAccountToken(saEmail, saKeyPem)
    const resp = await fetch(
      `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${PACKAGE_NAME}` +
        `/purchases/subscriptionsv2/tokens/${encodeURIComponent(sub.purchaseToken)}`,
      { headers: { Authorization: `Bearer ${accessToken}` } },
    )
    if (!resp.ok) {
      const detail = await resp.text()
      console.error("play api", resp.status, detail.slice(0, 300))
      // 4xx = the token is bad forever, ack; 5xx = retry.
      return json(resp.status >= 500 ? 502 : 200, { received: true })
    }
    const purchase = await resp.json() as {
      subscriptionState?: string
      externalAccountIdentifiers?: { obfuscatedExternalAccountId?: string }
      lineItems?: Array<{
        productId?: string; expiryTime?: string
        autoRenewingPlan?: {
          autoRenewEnabled?: boolean
          // Korea's consent before a trial or a lower price steps up to the
          // regular one (in force since 2026-02-03 on Play).
          priceStepUpConsentDetails?: { state?: string; consentDeadlineTime?: string }
        }
        offerDetails?: { offerId?: string | null }
      }>
      startTime?: string
    }

    const userId = purchase.externalAccountIdentifiers?.obfuscatedExternalAccountId
    if (!userId) {
      console.warn("purchase without obfuscatedExternalAccountId", sub.purchaseToken.slice(0, 12))
      return json(200, { received: true })
    }
    const line = purchase.lineItems?.[0]
    const productId = line?.productId ?? sub.subscriptionId
    if (!productId) return json(200, { received: true })

    const db = createClient(
      Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!)
    const { data: plan } = await db.from("subscription_plans")
      .select("id").eq("google_product_id", productId).maybeSingle()
    if (!plan) {
      console.error("no plan for google product", productId)
      return json(200, { received: true })
    }

    // subscriptionState → our status. CANCELED is still ENTITLED until
    // expiry (auto-renew off ≠ access off) — that is what
    // cancel_at_period_end is for.
    const state = purchase.subscriptionState ?? ""
    const status =
      state === "SUBSCRIPTION_STATE_ACTIVE" ? "active" :
      state === "SUBSCRIPTION_STATE_CANCELED" ? "active" :
      state === "SUBSCRIPTION_STATE_IN_GRACE_PERIOD" ? "grace" :
      "expired"
    // A trial line carries an offerId; mirrored into trial_ends_at so the
    // trial is metered at the DAILY allowance exactly as on Apple.
    const isTrial = Boolean(line?.offerDetails?.offerId)

    const { error } = await db.from("user_subscriptions").upsert({
      user_id: userId,
      plan_id: plan.id,
      source: "google",
      google_purchase_token: sub.purchaseToken,
      status,
      current_period_start: purchase.startTime ?? null,
      current_period_end: line?.expiryTime ?? null,
      trial_ends_at: isTrial ? line?.expiryTime ?? null : null,
      cancel_at_period_end: line?.autoRenewingPlan
        ? line.autoRenewingPlan.autoRenewEnabled === false : false,
      updated_at: new Date().toISOString(),
    })
    if (error) {
      if (error.code === "23503") {   // account deleted — ack, don't retry
        console.warn("user gone, dropping google event")
        return json(200, { received: true })
      }
      throw new Error(`user_subscriptions upsert: ${error.message}`)
    }

    // Play waiting on the learner's consent before it charges (Korea), the
    // same fact apple-webhook records (20261018170000). Every notification
    // re-reads the whole purchase, so a missing field means nothing is
    // pending. Its own update: a database without the columns costs this
    // record, never the entitlement above.
    const consent = line?.autoRenewingPlan?.priceStepUpConsentDetails
    const waiting = consent?.state === "CONSENT_STATE_PENDING" || consent?.state === "PENDING"
    const { error: consentErr } = await db.from("user_subscriptions")
      .update(waiting
        ? { price_consent_due_at: consent?.consentDeadlineTime ?? line?.expiryTime ?? null }
        : { price_consent_pending_since: null, price_consent_due_at: null })
      .eq("user_id", userId)
    if (consentErr) console.error("price consent update", consentErr.message)
    else if (waiting) {
      await db.from("user_subscriptions")
        .update({ price_consent_pending_since: new Date().toISOString() })
        .eq("user_id", userId)
        .is("price_consent_pending_since", null)
    }

    // The owner hears about a subscriber leaving, as on apple-webhook
    // (2026-10-16). RTDN types: developer.android.com/google/play/billing/rtdn-reference
    const head = LOSS_HEADLINE[sub.notificationType ?? 0]
    if (head) {
      const { data: who } = await db.auth.admin.getUserById(userId)
      await notifyOwner([
        `[nawana] ${head} (Google Play)`,
        `누구: ${who?.user?.email ?? userId.slice(0, 8)}`,
        `무엇: ${[plan.id, isTrial ? "체험" : null].filter(Boolean).join(" · ")}`,
        line?.expiryTime ? `이용 기간 끝: ${line.expiryTime.slice(0, 10)}` : null,
      ].filter(Boolean).join("\n"))
    }
    return json(200, { received: true })
  } catch (e) {
    console.error("google-webhook", e)
    return json(500, { error: "internal" })   // Pub/Sub retries
  }
})

/** RTDN subscription notification types worth a ping to the owner. */
const LOSS_HEADLINE: Record<number, string> = {
  3: "🚪 구독 취소(자동 갱신 끔)",
  5: "⚠️ 갱신 결제 실패(보류)",
  6: "⚠️ 갱신 결제 실패(유예 기간)",
  7: "↩️ 취소 철회(다시 시작)",
  12: "💸 구독 회수됨",
  13: "⌛ 구독 만료",
}

/** Service-account OAuth token via a self-signed RS256 JWT (Web Crypto). */
async function serviceAccountToken(email: string, keyPem: string): Promise<string> {
  const now = Math.floor(Date.now() / 1000)
  const b64url = (b: Uint8Array | string) => {
    const bytes = typeof b === "string" ? new TextEncoder().encode(b) : b
    let s = ""
    for (const byte of bytes) s += String.fromCharCode(byte)
    return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "")
  }
  const header = b64url(JSON.stringify({ alg: "RS256", typ: "JWT" }))
  const claims = b64url(JSON.stringify({
    iss: email,
    scope: "https://www.googleapis.com/auth/androidpublisher",
    aud: "https://oauth2.googleapis.com/token",
    iat: now, exp: now + 3600,
  }))
  const pem = keyPem.replace(/-----[A-Z ]+-----/g, "").replace(/\s+/g, "")
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0))
  const key = await crypto.subtle.importKey(
    "pkcs8", der, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"])
  const signature = new Uint8Array(await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(`${header}.${claims}`)))
  const assertion = `${header}.${claims}.${b64url(signature)}`
  const resp = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: `grant_type=${encodeURIComponent("urn:ietf:params:oauth:grant-type:jwt-bearer")}&assertion=${assertion}`,
  })
  if (!resp.ok) throw new Error(`token exchange ${resp.status}: ${(await resp.text()).slice(0, 200)}`)
  return (await resp.json() as { access_token: string }).access_token
}
