// Collect the voices of learners who never signed up.
//
// The voice-clone flow opens an ANONYMOUS Supabase session so the fluent voice
// can be built and HEARD before the app asks for an account (see
// `AuthService.startAnonymousSession`). Most of those sessions become accounts
// one screen later — Apple is linked to the same user, so nothing here ever
// sees them. The rest are people who put the phone down: a real ElevenLabs
// voice, held by a user nobody can ever sign into again, occupying a slot on a
// shared account ceiling that costs money.
//
// So: every anonymous user older than the grace window loses its clones
// upstream and is deleted, which cascades every row it owned. Grace exists
// because "anonymous" is also the state of someone mid-onboarding right now.
//
// Not user-callable. There is no JWT to check (`verify_jwt = false`), so the
// caller proves itself with CLEANUP_SECRET in X-Cleanup-Secret. Without that
// env var set the function refuses every request — a cleanup that deletes
// users must fail closed, never open.

import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0"

/// How long an unclaimed anonymous user is left alone. Generous on purpose:
/// the cost of waiting is one voice slot, the cost of being wrong is deleting
/// the voice of someone who is still reading the sign-up screen.
const GRACE_HOURS = 48
/// Bounded per run so one invocation can't spend minutes in ElevenLabs calls.
/// Anything left over is collected by the next run.
const MAX_PER_RUN = 100

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("method not allowed", { status: 405 })
  }

  const secret = Deno.env.get("CLEANUP_SECRET")
  if (!secret || req.headers.get("X-Cleanup-Secret") !== secret) {
    return new Response("forbidden", { status: 403 })
  }

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  )
  const elevenKey = Deno.env.get("ELEVENLABS_API_KEY")

  // Anonymous users past the grace window. `is_anonymous` lives on auth.users
  // and is not exposed through PostgREST, so this goes through the RPC that
  // reads it under SECURITY DEFINER.
  const { data: stale, error } = await admin.rpc("stale_anonymous_users", {
    p_older_than_hours: GRACE_HOURS,
    p_limit: MAX_PER_RUN,
  })
  if (error) {
    console.error("cleanup-anonymous-voices: lookup failed", error)
    return new Response(JSON.stringify({ error: error.message }), { status: 500 })
  }

  let deletedUsers = 0
  let deletedVoices = 0

  for (const row of (stale ?? []) as { user_id: string }[]) {
    // Voices first: deleting the user cascades the voice_clones row, and a row
    // that's gone is a voice we can no longer name upstream.
    const { data: clones } = await admin
      .from("voice_clones")
      .select("elevenlabs_voice_id")
      .eq("user_id", row.user_id)

    let upstreamOK = true
    if (elevenKey) {
      for (const clone of clones ?? []) {
        if (!clone.elevenlabs_voice_id) continue
        const res = await fetch(
          `https://api.elevenlabs.io/v1/voices/${clone.elevenlabs_voice_id}`,
          { method: "DELETE", headers: { "xi-api-key": elevenKey } },
        )
        // 404 = already gone (a re-record during onboarding replaces one).
        if (res.ok || res.status === 404) {
          deletedVoices++
        } else {
          upstreamOK = false
          console.error("cleanup-anonymous-voices: voice delete failed",
            clone.elevenlabs_voice_id, res.status, (await res.text()).slice(0, 300))
        }
      }
    }

    // A voice we failed to delete upstream keeps its user, so the next run can
    // try again with the id still on record. Deleting the user here would lose
    // the only pointer to a voice that keeps costing us a slot.
    if (!upstreamOK) continue

    const { error: delErr } = await admin.auth.admin.deleteUser(row.user_id)
    if (delErr) {
      console.error("cleanup-anonymous-voices: user delete failed", row.user_id, delErr)
      continue
    }
    deletedUsers++
  }

  return new Response(
    JSON.stringify({ scanned: (stale ?? []).length, deletedUsers, deletedVoices }),
    { status: 200, headers: { "Content-Type": "application/json" } },
  )
})
