// Lands a consumable App Store purchase — a talk-minute pack — on the
// account that bought it (2026-09-26).
//
// Consumables have no server notification worth waiting for (Apple's
// ONE_TIME_CHARGE arrives for some storefronts and not others, and carries
// no appAccountToken unless the app set one), so the app hands over the
// signed transaction itself, exactly as `apple-claim` does for a
// subscription: the JWS is verified against Apple's pinned root
// (`_shared/apple-jws.ts`), then `apply_talk_topup` grants the product's
// seconds under the transaction id as the idempotency key. The app FINISHES
// the transaction only once this has answered `applied` or "already
// applied" — an unreachable server means Apple re-delivers the transaction
// on the next launch and the purchase is never lost.
//
// A JWS that another account already redeemed comes back `applied: false`:
// the ledger key is global, so the seconds cannot be minted twice whoever
// presents the receipt.
import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0"
import { requireUser, handlePreflight, errorResponse, cors } from "../_shared/auth.ts"
import { verifyAppleJWS, peekJWSUnverified, isoFromMs } from "../_shared/apple-jws.ts"

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
    console.error("apple-topup signature rejected", {
      reason: (e as Error)?.message ?? String(e),
      unverified: peekJWSUnverified(jws),
      user: userId,
    })
    return errorResponse(401, "signature verification failed")
  }

  if (tx.bundleId && tx.bundleId !== bundleId) {
    console.error("apple-topup wrong bundle", { got: tx.bundleId, want: bundleId, user: userId })
    return errorResponse(400, "wrong bundle")
  }
  if (tx.type && tx.type !== "Consumable") {
    return errorResponse(400, "not a consumable")
  }
  // A refunded purchase must not land: Apple took the money back, and the
  // app only ever presents a transaction once, so this is not a retry.
  if (typeof tx.revocationDate === "number") {
    return errorResponse(400, "transaction revoked")
  }
  const transactionId: string | undefined = tx.transactionId
  if (!transactionId) return errorResponse(400, "transaction has no transactionId")

  const db = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  )

  const { data, error } = await db.rpc("apply_talk_topup", {
    p_user_id: userId,
    p_product_id: tx.productId ?? "",
    p_store: "apple",
    p_transaction_id: transactionId,
    p_metadata: {
      price_milliunits: typeof tx.price === "number" ? tx.price : null,
      currency: tx.currency ?? null,
      storefront: tx.storefront ?? null,
      purchase_date: typeof tx.purchaseDate === "number" ? isoFromMs(tx.purchaseDate) : null,
      environment: tx.environment ?? "unknown",
      quantity: typeof tx.quantity === "number" ? tx.quantity : 1,
    },
  })
  if (error) {
    if (error.code === "P0008") {
      console.error("apple-topup unknown product", tx.productId)
      return errorResponse(400, "unknown product")
    }
    console.error("apple-topup apply failed", error.message)
    return errorResponse(500, "could not record top-up")
  }

  console.log("apple-topup", { user: userId, transactionId, product: tx.productId, ...data })
  return new Response(JSON.stringify(data), {
    status: 200,
    headers: { "Content-Type": "application/json", ...cors() },
  })
})
