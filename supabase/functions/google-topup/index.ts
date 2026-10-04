// Lands a consumable Google Play purchase — a talk-minute pack — on the
// account that bought it. The `apple-topup` twin (master plan 4.0).
//
// The app hands over the purchase token and the product id it bought; this
// asks the Play Developer API about that token before believing anything
// (never the client's word — the same rule `google-webhook` keeps), then
// `apply_talk_topup` grants the product's seconds under the purchase token as
// the idempotency key. The app CONSUMES the purchase only once this has
// answered `applied` or "already applied" — an unconsumed consumable is
// handed back by `queryPurchasesAsync` on the next launch, so a purchase made
// with no network is never lost.
//
// A token another account already redeemed comes back `applied: false`: the
// ledger key is global, so the seconds cannot be minted twice whoever
// presents the token. And unlike an Apple JWS, a Play purchase carries the
// account it was bought for (`obfuscatedExternalAccountId`, set by
// BillingService), so a token presented by anyone else is refused outright.
//
// NOT ARMED until the owner's Play Console setup (§4.4) — the same service
// account env vars as google-webhook. Until then every request is a 503 and
// the app keeps the purchase unconsumed, to retry.
import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0"
import { requireUser, handlePreflight, errorResponse, cors } from "../_shared/auth.ts"

const PACKAGE_NAME = "com.roro.futurevoice"

Deno.serve(async (req) => {
  const pre = handlePreflight(req)
  if (pre) return pre
  if (req.method !== "POST") return errorResponse(405, "method not allowed")

  const authed = await requireUser(req)
  if (authed instanceof Response) return authed
  const userId = authed.user.id

  const saEmail = Deno.env.get("GOOGLE_SA_EMAIL")
  const saKeyPem = Deno.env.get("GOOGLE_SA_KEY_PEM")
  if (!saEmail || !saKeyPem) return errorResponse(503, "google billing not configured")

  let body: any
  try { body = await req.json() } catch { return errorResponse(400, "invalid json") }
  const purchaseToken = typeof body?.purchaseToken === "string" ? body.purchaseToken : null
  const productId = typeof body?.productId === "string" ? body.productId : null
  if (!purchaseToken || !productId) return errorResponse(400, "missing purchaseToken or productId")

  // ── Ask Google about the token ──
  let purchase: {
    purchaseState?: number          // 0 purchased · 1 canceled · 2 pending
    consumptionState?: number
    orderId?: string
    purchaseTimeMillis?: string
    obfuscatedExternalAccountId?: string
    purchaseType?: number           // 0 test (licence tester) · 1 promo · 2 rewarded
    quantity?: number
    regionCode?: string
  }
  try {
    const accessToken = await serviceAccountToken(saEmail, saKeyPem)
    const resp = await fetch(
      `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${PACKAGE_NAME}` +
        `/purchases/products/${encodeURIComponent(productId)}/tokens/${encodeURIComponent(purchaseToken)}`,
      { headers: { Authorization: `Bearer ${accessToken}` } },
    )
    if (!resp.ok) {
      const detail = await resp.text()
      console.error("google-topup play api", resp.status, detail.slice(0, 300), { user: userId })
      // 4xx: the token is not a purchase of this product, now or ever.
      // 5xx: Google is down — the app keeps the purchase and retries.
      return resp.status >= 500
        ? errorResponse(502, "play unreachable")
        : errorResponse(401, "purchase not verified")
    }
    purchase = await resp.json()
  } catch (e) {
    console.error("google-topup verify failed", (e as Error)?.message ?? String(e))
    return errorResponse(502, "play unreachable")
  }

  // A cancelled (refunded / voided) purchase must not land; a pending one
  // has not been paid for yet — the app retries once it completes.
  if (purchase.purchaseState === 1) return errorResponse(400, "purchase cancelled")
  if (purchase.purchaseState !== 0) return errorResponse(409, "purchase pending")
  const owner = purchase.obfuscatedExternalAccountId
  if (owner && owner !== userId) {
    console.error("google-topup token belongs to another account", { user: userId })
    return errorResponse(403, "purchase belongs to another account")
  }

  const db = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  )

  const { data, error } = await db.rpc("apply_talk_topup", {
    p_user_id: userId,
    p_product_id: productId,
    p_store: "google",
    p_transaction_id: purchaseToken,
    p_metadata: {
      order_id: purchase.orderId ?? null,
      region: purchase.regionCode ?? null,
      purchase_date: purchase.purchaseTimeMillis
        ? new Date(Number(purchase.purchaseTimeMillis)).toISOString() : null,
      environment: purchase.purchaseType === 0 ? "test" : "production",
      quantity: typeof purchase.quantity === "number" ? purchase.quantity : 1,
    },
  })
  if (error) {
    if (error.code === "P0008") {
      console.error("google-topup unknown product", productId)
      return errorResponse(400, "unknown product")
    }
    console.error("google-topup apply failed", error.message)
    return errorResponse(500, "could not record top-up")
  }

  console.log("google-topup", { user: userId, order: purchase.orderId, product: productId, ...data })
  return new Response(JSON.stringify(data), {
    status: 200,
    headers: { "Content-Type": "application/json", ...cors() },
  })
})

/** Service-account OAuth token via a self-signed RS256 JWT (Web Crypto).
 *  A copy of google-webhook's, kept here so neither deploy depends on the
 *  other. */
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
