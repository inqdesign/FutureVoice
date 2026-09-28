// Park the voices nobody is paying for.
//
// ElevenLabs holds a fixed number of custom voices for the WHOLE account
// (Pro: 160), and every learner's clone is one. A learner who stopped paying,
// or never started and stopped coming, keeps a slot forever unless something
// gives it back. This is that something. Rules and reasons:
// `20260928140000_park_idle_voices.sql` (`parkable_voice_owners`).
//
// Parking = delete every voice of the user upstream, then stamp `parked_at` on
// the active row. The user, their rows, their talks and every audio file on
// their phone stay. The phone rebuilds the voice from its own recording when
// the learner subscribes (or, with free minutes left, simply comes back).
//
// Not user-callable: `verify_jwt = false`, and the caller proves itself with
// CLEANUP_SECRET in X-Cleanup-Secret — the same secret the anonymous sweep
// uses. Unset → every request refused. `?dry=1` lists who would be parked and
// touches nothing, so the first run can be read before it deletes anything.

import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0"
import { timingSafeEqual } from "../_shared/auth.ts"

/// Founder's call, 2026-09-28. The SQL floors it at 7 whatever is passed.
const IDLE_DAYS = 7
/// Bounded per run so one invocation can't spend minutes in ElevenLabs calls.
const MAX_PER_RUN = 100

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("method not allowed", { status: 405 })
  }
  const secret = Deno.env.get("CLEANUP_SECRET")
  if (!secret || !timingSafeEqual(req.headers.get("X-Cleanup-Secret") ?? "", secret)) {
    return new Response("forbidden", { status: 403 })
  }
  const params = new URL(req.url).searchParams
  const dry = params.get("dry") === "1"
  // `?rule=spent` parks only rule A (nothing left to spend). Used while the
  // App Store build is one that cannot re-clone by itself: for those learners
  // the paywall is the right answer on any build, whereas rule B's free
  // minutes would be stranded until the new build lands (2026-09-28).
  const onlyRule = params.get("rule")

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  )
  const elevenKey = Deno.env.get("ELEVENLABS_API_KEY")
  if (!elevenKey && !dry) {
    return new Response(JSON.stringify({ error: "server missing ELEVENLABS_API_KEY" }), { status: 500 })
  }

  const { data: owners, error } = await admin.rpc("parkable_voice_owners", {
    p_idle_days: IDLE_DAYS,
    p_limit: MAX_PER_RUN,
  })
  if (error) {
    console.error("park-idle-voices: lookup failed", error)
    return new Response(JSON.stringify({ error: error.message }), { status: 500 })
  }
  const rows = ((owners ?? []) as { user_id: string; rule: string; balance: number; idle_since: string }[])
    .filter((r) => !onlyRule || r.rule === onlyRule)
  if (dry) {
    return json({ dry: true, count: rows.length, owners: rows })
  }

  let parkedUsers = 0
  let deletedVoices = 0
  const failed: string[] = []

  for (const row of rows) {
    // Every voice the user still has a row for: the active one, and any
    // replaced one whose own delete never landed (those hold a slot too).
    const { data: clones } = await admin
      .from("voice_clones")
      .select("id, elevenlabs_voice_id, is_active")
      .eq("user_id", row.user_id)

    let upstreamOK = true
    for (const clone of clones ?? []) {
      if (!clone.elevenlabs_voice_id) continue
      const res = await fetch(
        `https://api.elevenlabs.io/v1/voices/${clone.elevenlabs_voice_id}`,
        { method: "DELETE", headers: { "xi-api-key": elevenKey! } },
      )
      // A DELETE on a voice that is already gone answers 400
      // `voice_does_not_exist`, not 404 (see cleanup-anonymous-voices).
      const body = res.ok ? "" : await res.text()
      const alreadyGone = res.status === 404 ||
        (res.status === 400 && body.includes("voice_does_not_exist"))
      if (res.ok || alreadyGone) {
        deletedVoices++
      } else {
        upstreamOK = false
        console.error("park-idle-voices: voice delete failed",
          clone.elevenlabs_voice_id, res.status, body.slice(0, 300))
      }
    }

    // A voice still alive upstream is NOT marked parked: the next run tries
    // again, and until then the learner's voice simply keeps working.
    if (!upstreamOK) {
      failed.push(row.user_id)
      continue
    }

    const { error: upErr } = await admin
      .from("voice_clones")
      .update({ parked_at: new Date().toISOString() })
      .eq("user_id", row.user_id)
      .eq("is_active", true)
      .is("parked_at", null)
    if (upErr) {
      console.error("park-idle-voices: stamp failed", row.user_id, upErr.message)
      failed.push(row.user_id)
      continue
    }
    parkedUsers++
    console.log(`park-idle-voices: parked ${row.user_id} rule=${row.rule} idle_since=${row.idle_since}`)
  }

  return json({ scanned: rows.length, parkedUsers, deletedVoices, failed })
})

function json(body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status: 200, headers: { "Content-Type": "application/json" },
  })
}
