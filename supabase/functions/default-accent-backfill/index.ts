// The default accent for German learners who cloned before it existed
// (2026-10-09). Who and why: `20261009150000_default_accent_backfill.sql`.
//
// Every 10 minutes (pg_cron), up to MAX_PER_RUN learners who came back since
// START and still speak German with a plain clone get the Standard German
// remix — through `speakAs`, the same code the inline path runs, so the row,
// the ledger entry and what the gateway / `elevenlabs-tts` read are identical.
//
// One remix is ~25 s upstream, so a run is a few learners, in sequence.
// Stops at once when the month's voice allowance is down to the reserve
// (`reservedForNewLearners`) — a first clone outranks an accent — and tries
// again next run; that pause is not counted as a try.
//
// Not user-callable: `verify_jwt = false`, CLEANUP_SECRET in X-Cleanup-Secret
// (unset → everything refused). `?dry=1` lists who would be remixed.

import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0"
import { timingSafeEqual } from "../_shared/auth.ts"
import { speakAs, BUSY } from "../_shared/default-accent.ts"
import { reservedForNewLearners } from "../_shared/voice-quota.ts"

/// The moment this started: "old" = the clone existed before it, "came back"
/// = their session refreshed after it.
const START = "2026-10-09T19:30:00Z"
const MAX_PER_RUN = 3

interface Candidate { user_id: string; voice_id: string; name: string | null }

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("method not allowed", { status: 405 })
  const secret = Deno.env.get("CLEANUP_SECRET")
  if (!secret || !timingSafeEqual(req.headers.get("X-Cleanup-Secret") ?? "", secret)) {
    return new Response("forbidden", { status: 403 })
  }
  const dry = new URL(req.url).searchParams.get("dry") === "1"
  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!)
  const apiKey = Deno.env.get("ELEVENLABS_API_KEY")
  const json = (body: unknown, status = 200) =>
    new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } })
  if (!apiKey) return json({ error: "server missing ELEVENLABS_API_KEY" }, 500)

  const { data, error } = await admin.rpc("default_accent_backfill_candidates",
    { p_since: START, p_limit: MAX_PER_RUN })
  if (error) return json({ error: error.message }, 500)
  const candidates = (data ?? []) as Candidate[]
  if (dry) return json({ dry: true, candidates })
  if (candidates.length === 0) return json({ remixed: [], skipped: [] })

  if (await reservedForNewLearners(apiKey)) {
    console.log("default-accent-backfill: voice allowance at the reserve, waiting", { waiting: candidates.length })
    return json({ held: true, waiting: candidates.length })
  }

  const remixed: string[] = []
  const failed: string[] = []
  for (const c of candidates) {
    // Only rows carrying the flag ever get a speak-as voice.
    await admin.from("voice_clones").update({ accent_by_server: true })
      .eq("user_id", c.user_id).eq("elevenlabs_voice_id", c.voice_id)
    const target = await speakAs({
      admin, apiKey, userId: c.user_id, voiceId: c.voice_id, language: "de", create: true,
    })
    const ok = target !== c.voice_id && target !== BUSY
    const { data: prev } = await admin.from("default_accent_backfill_log")
      .select("tries").eq("voice_id", c.voice_id).maybeSingle()
    await admin.from("default_accent_backfill_log").upsert({
      voice_id: c.voice_id, user_id: c.user_id,
      tries: ((prev as { tries?: number } | null)?.tries ?? 0) + 1,
      last_at: new Date().toISOString(), result: ok ? `remixed:${target}` : (target === BUSY ? "busy" : "failed"),
    })
    ;(ok ? remixed : failed).push(c.user_id)
    console.log("default-accent-backfill:", ok ? "remixed" : "failed", { user: c.user_id, voice: c.voice_id, target })
    // The allowance may have hit the reserve on this very remix.
    if (ok && await reservedForNewLearners(apiKey)) break
  }
  return json({ remixed, failed })
})
