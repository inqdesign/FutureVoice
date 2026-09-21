// Account deletion — Apple Guideline 5.1.1(v) requires in-app account deletion.
//
// POST, no body. Deletes, in order:
//   1. Every ElevenLabs voice clone the user owns (best-effort — a dangling
//      clone must not block the deletion, but we log failures).
//   2. Any active Stripe web subscription (immediate cancel — the account is
//      gone, so there is nothing left to bill against). Apple subscriptions
//      are managed by Apple; the client copy tells users to cancel there.
//   2b. Every original clone recording in the private voice-originals bucket
//      (Storage does not cascade with the auth user).
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

  // 1b) The recordings those clones were built from. Storage does NOT cascade
  // with the auth user, and the consent the learner gave says deleting the
  // account deletes the voice — so an orphaned recording here would be the
  // one promise this endpoint exists to keep, quietly broken.
  await removeVoiceOriginals(admin, user.id)

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

/**
 * Delete every object under `<user_id>/` in the private voice-originals
 * bucket. Best-effort and logged: a storage failure must not leave the
 * account itself undeleted, which is the thing Apple requires — but it is
 * loud, because what is left behind is a voice recording.
 */
async function removeVoiceOriginals(
  admin: ReturnType<typeof createClient>,
  userId: string,
): Promise<void> {
  const bucket = admin.storage.from("voice-originals")
  try {
    // One level of folders (`<user_id>/<voice_id>`), then the files in each —
    // `list` is not recursive and `remove` takes full paths only.
    const { data: folders, error } = await bucket.list(userId, { limit: 1000 })
    if (error) { console.error("account-delete: originals list failed", error.message); return }
    const paths: string[] = []
    for (const folder of folders ?? []) {
      const { data: files } = await bucket.list(`${userId}/${folder.name}`, { limit: 1000 })
      for (const f of files ?? []) paths.push(`${userId}/${folder.name}/${f.name}`)
    }
    if (paths.length === 0) return
    const { error: rmErr } = await bucket.remove(paths)
    if (rmErr) console.error("account-delete: originals remove failed", rmErr.message)
  } catch (e) {
    console.error("account-delete: originals threw", (e as Error)?.message ?? String(e))
  }
}
