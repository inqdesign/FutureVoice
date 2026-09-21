// Delete clone recordings older than the retention window.
//
// `elevenlabs-voice-clone` writes the takes it receives into the private
// `voice-originals` bucket, because ElevenLabs' own copy dies with the voice
// and an accent pick deletes the voice seconds later. That copy exists to
// check the quality of a clone that just went wrong — not to accumulate. So
// it is kept for ONE DAY and then removed, which is what the consent screen
// and the privacy policy can then honestly say.
//
// Storage has no TTL, and deleting the `storage.objects` row alone would
// orphan the file in the backing store — the object has to go through the
// Storage API. `expired_voice_originals()` finds them in one query; this
// removes them and clears the pointer on `voice_clones`.
//
// Not user-callable: no JWT (`verify_jwt = false`), authenticity is
// CLEANUP_SECRET in X-Cleanup-Secret, and an unset secret refuses everything.

import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0"
import { timingSafeEqual } from "../_shared/auth.ts"

/// Hours a recording is kept. The window has one job: be long enough for a
/// human to look at a clone somebody complained about, and short enough to
/// state in a sentence. It must also outlast a night, or a problem reported
/// in the morning has nothing left to look at.
const RETAIN_HOURS = 24
/// Bounded per run; the leftovers go on the next hourly pass.
const MAX_PER_RUN = 500

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("method not allowed", { status: 405 })

  const secret = Deno.env.get("CLEANUP_SECRET")
  if (!secret || !timingSafeEqual(req.headers.get("X-Cleanup-Secret") ?? "", secret)) {
    return new Response("forbidden", { status: 403 })
  }

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  )

  const { data: expired, error } = await admin.rpc("expired_voice_originals", {
    p_older_than_hours: RETAIN_HOURS,
    p_limit: MAX_PER_RUN,
  })
  if (error) {
    console.error("purge-voice-originals: lookup failed", error.message)
    return new Response(JSON.stringify({ error: error.message }), { status: 500 })
  }

  const rows = (expired ?? []) as { path: string; folder: string }[]
  if (rows.length === 0) {
    return new Response(JSON.stringify({ deleted: 0 }), {
      status: 200, headers: { "Content-Type": "application/json" },
    })
  }

  const { error: rmErr } = await admin.storage
    .from("voice-originals")
    .remove(rows.map((r) => r.path))
  if (rmErr) {
    console.error("purge-voice-originals: remove failed", rmErr.message)
    return new Response(JSON.stringify({ error: rmErr.message }), { status: 500 })
  }

  // The row must stop claiming to hold a recording, or the archive script
  // spends every run asking for files that are gone.
  const folders = [...new Set(rows.map((r) => r.folder))]
  const { error: updErr } = await admin
    .from("voice_clones")
    .update({ original_path: null })
    .in("original_path", folders)
  if (updErr) console.error("purge-voice-originals: unmark failed", updErr.message)

  console.log("purge-voice-originals", { deleted: rows.length, folders: folders.length })
  return new Response(
    JSON.stringify({ deleted: rows.length, folders: folders.length }),
    { status: 200, headers: { "Content-Type": "application/json" } },
  )
})
