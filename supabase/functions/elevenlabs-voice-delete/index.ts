// Voice delete (named for ElevenLabs, which is gone since 2026-10-15; the
// store builds call it by this name). Deletes the Cartesia voice.
//
// Body: { voice_id: string }
// Charges 0 credits — delete is free, but we still write a ledger row for
// audit trail (handy when troubleshooting "where did my voice go").

import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { requireUser, handlePreflight, errorResponse, cors } from "../_shared/auth.ts"
import { priceFor, charge, serviceRoleClient } from "../_shared/credits.ts"
import * as cartesia from "../_shared/cartesia.ts"

const SOURCE_FN = "elevenlabs-voice-delete"

Deno.serve(async (req) => {
  const pre = handlePreflight(req)
  if (pre) return pre
  if (req.method !== "POST") return errorResponse(405, "method not allowed")

  const authed = await requireUser(req)
  if (authed instanceof Response) return authed
  const { user, supabase } = authed

  const idemKey = req.headers.get("X-Idempotency-Key")
  if (!idemKey) return errorResponse(400, "missing X-Idempotency-Key header")

  let body: { voice_id?: string }
  try { body = await req.json() } catch { return errorResponse(400, "invalid json body") }
  if (!body.voice_id) return errorResponse(400, "voice_id required")

  const { data: owned } = await supabase
    .from("voice_clones")
    .select("id")
    .eq("user_id", user.id)
    .eq("elevenlabs_voice_id", body.voice_id)
    .maybeSingle()
  if (!owned) return errorResponse(403, "voice not owned by caller")

  // Free, but creates an audit row.
  await charge({
    supabase, userId: user.id,
    action: "voice_delete",
    amount: priceFor("voice_delete"),
    sourceFn: SOURCE_FN,
    idempotencyKey: idemKey,
    metadata: { voice_id: body.voice_id },
  })

  if (cartesia.isCartesiaVoice(body.voice_id)) {
    // An accent pick hands the app a new id for the SAME Cartesia voice
    // ("<uuid>:<accent>", _shared/cartesia.ts), and the app then deletes the
    // old id. The voice itself goes only when no other id of it is live.
    const { uuid } = cartesia.parseVoice(body.voice_id)
    const { data: siblings } = await supabase.from("voice_clones").select("elevenlabs_voice_id")
      .eq("user_id", user.id).eq("is_active", true).like("elevenlabs_voice_id", `${uuid}%`)
    const stillUsed = (siblings ?? []).some((r) => r.elevenlabs_voice_id !== body.voice_id)
    if (!stillUsed) {
      const gone = await cartesia.deleteVoice(body.voice_id)
      if (!gone.ok) return errorResponse(gone.status, "cartesia upstream error", gone.detail ?? "")
    }
  }
  // An ElevenLabs id (a voice from before 2026-10-12) has nothing upstream
  // left to delete: ElevenLabs is gone (2026-10-15), and its voices with it.
  // Only the row is retired.

  await supabase
    .from("voice_clones")
    .update({ is_active: false })
    .eq("id", owned.id)

  // The recording behind the voice (20260914120000) — kept or dropped by what
  // the learner is LEFT with, because this one endpoint serves two intents the
  // wire cannot tell apart:
  //
  //   * an accent pick or a re-record deletes the OLD clone moments after a
  //     new one was inserted. A clone is still active, the learner asked for a
  //     different voice, not for their recording to be forgotten — and this is
  //     precisely the case that used to destroy the only copy in existence.
  //   * Me → delete my voice is a consent WITHDRAWAL and leaves nothing
  //     active. Then the recording goes too; keeping the source of a voice
  //     somebody just revoked would be the worst possible reading of consent.
  const { count } = await supabase
    .from("voice_clones")
    .select("id", { count: "exact", head: true })
    .eq("user_id", user.id)
    .eq("is_active", true)
  if ((count ?? 0) === 0) await removeVoiceOriginals(user.id)

  return new Response(JSON.stringify({ ok: true }), {
    status: 200,
    headers: { "Content-Type": "application/json", ...cors() },
  })
})

/** Every object under `<user_id>/` in the private voice-originals bucket. */
async function removeVoiceOriginals(userId: string): Promise<void> {
  const bucket = serviceRoleClient().storage.from("voice-originals")
  try {
    const { data: folders, error } = await bucket.list(userId, { limit: 1000 })
    if (error) { console.error("voice-delete: originals list failed", error.message); return }
    const paths: string[] = []
    for (const folder of folders ?? []) {
      const { data: files } = await bucket.list(`${userId}/${folder.name}`, { limit: 1000 })
      for (const f of files ?? []) paths.push(`${userId}/${folder.name}/${f.name}`)
    }
    if (paths.length === 0) return
    const { error: rmErr } = await bucket.remove(paths)
    if (rmErr) console.error("voice-delete: originals remove failed", rmErr.message)
  } catch (e) {
    console.error("voice-delete: originals threw", (e as Error)?.message ?? String(e))
  }
}
