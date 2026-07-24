// Account deletion — Apple Guideline 5.1.1(v) requires in-app account deletion.
//
// POST, no body. Deletes, in order:
//   1. Every ElevenLabs voice clone the user owns (best-effort — a dangling
//      clone must not block the deletion, but we log failures).
//   2. Any active Stripe web subscription (immediate cancel — the account is
//      gone, so there is nothing left to bill against). Apple subscriptions
//      are managed by Apple; the client copy tells users to cancel there.
//   3. The auth user itself via the service role. Every user table
//      (profiles, voice_clones, user_credits, user_subscriptions, referrals,
//      beta monitoring) references auth.users ON DELETE CASCADE, so this one
//      call wipes the rest.

import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0"
import { requireUser, handlePreflight, errorResponse, cors } from "../_shared/auth.ts"

Deno.serve(async (req) => {
  const pre = handlePreflight(req)
  if (pre) return pre
  if (req.method !== "POST") return errorResponse(405, "method not allowed")

  const authed = await requireUser(req)
  if (authed instanceof Response) return authed
  const { user } = authed

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  )

  // 1) ElevenLabs clones — the voice must not outlive the account.
  const elevenKey = Deno.env.get("ELEVENLABS_API_KEY")
  const { data: clones } = await admin
    .from("voice_clones")
    .select("elevenlabs_voice_id")
    .eq("user_id", user.id)
  if (elevenKey) {
    for (const clone of clones ?? []) {
      if (!clone.elevenlabs_voice_id) continue
      const res = await fetch(
        `https://api.elevenlabs.io/v1/voices/${clone.elevenlabs_voice_id}`,
        { method: "DELETE", headers: { "xi-api-key": elevenKey } },
      )
      // 404 = already gone (e.g. deleted after a re-record) — that's fine.
      if (!res.ok && res.status !== 404) {
        console.error("account-delete: voice delete failed",
          clone.elevenlabs_voice_id, res.status, await res.text())
      }
    }
  }

  // 2) Stripe web subscription — cancel immediately so no orphaned billing.
  const stripeKey = Deno.env.get("STRIPE_SECRET_KEY")
  if (stripeKey) {
    const { data: sub } = await admin
      .from("user_subscriptions")
      .select("stripe_subscription_id")
      .eq("user_id", user.id)
      .maybeSingle()
    if (sub?.stripe_subscription_id) {
      const res = await fetch(
        `https://api.stripe.com/v1/subscriptions/${sub.stripe_subscription_id}`,
        { method: "DELETE", headers: { Authorization: `Bearer ${stripeKey}` } },
      )
      // resource_missing = already canceled — fine. Anything else is logged
      // but doesn't block deletion; Stripe's dunning would fail on the next
      // cycle anyway and this is the user's explicit deletion request.
      if (!res.ok && res.status !== 404) {
        console.error("account-delete: stripe cancel failed",
          sub.stripe_subscription_id, res.status, await res.text())
      }
    }
  }

  // 3) The auth user — cascades every user table.
  const { error } = await admin.auth.admin.deleteUser(user.id)
  if (error) return errorResponse(500, "auth delete failed", error.message)

  return new Response(JSON.stringify({ ok: true }), {
    status: 200,
    headers: { "Content-Type": "application/json", ...cors() },
  })
})
