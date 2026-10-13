// Move every learner's voice to Cartesia from the server (2026-10-13).
//
// voice-move moves ONE learner, when their app asks. This does the same for
// any learner, called by an operator with the service-role key — so the
// whole base moves at once instead of waiting for each phone (founder:
// "모든 유저의 음성을 바로 가져오고 싶어"). The app adopts the new id on its
// next launch (`restoreVoiceCloneFromCloud`), as after any server-side swap.
//
// One learner per request: `{ user_id, dry? }`. A dry run reads everything
// and answers what it WOULD do (source recording, accent) without cloning.
//
// The accent the moved voice speaks (founder, same day):
//   - learning German → standard German, whatever was picked before;
//   - an ElevenLabs accent remix → that accent, carried over;
//   - no accent → General American (English learners). Japanese and Korean
//     have one accent each, so they stay plain.
// Every moved voice also gets standard German added, so a German line is
// spoken in it by default (cartesia.defaultAccent) even after the learner
// switches language.
//
// The recording it is cloned from: the active voice's own sample when it is
// a plain clone; for an accent remix (which keeps no recording) the newest
// earlier plain clone of the same learner that still exists upstream; and
// only then the remix's own sample, which already carries the accent.
//
// Parked voices move only from the operator's archive (their ElevenLabs
// voice is gone); without it the app's revival flow rebuilds them. The old ElevenLabs
// voice is NOT deleted here — it is the way back if a move sounds wrong.

import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0"
import * as cartesia from "../_shared/cartesia.ts"
import { MPEGDecoder } from "npm:mpg123-decoder@1.0.3"

type ElVoice = {
  category?: string
  description?: string | null
  labels?: Record<string, string> | null
  samples?: { sample_id: string }[] | null
}

Deno.serve(async (req) => {
  const json = (o: unknown, status = 200) => new Response(JSON.stringify(o), {
    status, headers: { "Content-Type": "application/json" },
  })
  if (req.method !== "POST") return json({ error: "method not allowed" }, 405)
  // The caller proves itself by holding a service-level key: the request's
  // own key must be able to list users (any anon or user token can't).
  const bearer = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "")
  if (!bearer) return json({ error: "unauthorized" }, 401)
  const proof = await createClient(Deno.env.get("SUPABASE_URL")!, bearer, { auth: { persistSession: false } })
    .auth.admin.listUsers({ page: 1, perPage: 1 })
  if (proof.error) return json({ error: "unauthorized" }, 401)
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? bearer
  const elKey = Deno.env.get("ELEVENLABS_API_KEY")
  if (!elKey) return json({ error: "server missing ELEVENLABS_API_KEY" }, 500)

  // `sample_b64`: a recording from the operator's local archive
  // (scripts/voice-archive.sh), for a learner whose ElevenLabs voice or
  // recording is gone upstream — "original" = their clone take, "remix" = an
  // accent remix's sample. `accent_description`: the archived voice's remix
  // prompt, read when ElevenLabs can no longer say which accent it was.
  const body = await req.json().catch(() => ({})) as {
    user_id?: string; dry?: boolean
    sample_b64?: string; sample_kind?: "original" | "remix"; accent_description?: string
    reclone?: boolean
  }
  const userId = body.user_id
  if (!userId) return json({ error: "user_id required" }, 400)
  const dry = body.dry === true
  const db = createClient(Deno.env.get("SUPABASE_URL")!, serviceKey)

  const { data: rows } = await db.from("voice_clones")
    .select("id, elevenlabs_voice_id, name, is_active, parked_at, created_at")
    .eq("user_id", userId).order("created_at", { ascending: false })
  const all = (rows ?? []) as { id: string; elevenlabs_voice_id: string; name: string | null;
    is_active: boolean; parked_at: string | null; created_at: string }[]
  const active = all.find((r) => r.is_active)
  if (!active) return json({ user_id: userId, result: "no_voice" })

  const { data: profile } = await db.from("profiles").select("target_language").eq("id", userId).maybeSingle()
  const target = ((profile as { target_language?: string } | null)?.target_language ?? "en").toLowerCase().split("-")[0]

  let lastStatus = 0
  const el = async (id: string): Promise<ElVoice | null> => {
    const r = await fetch(`https://api.elevenlabs.io/v1/voices/${id}`, { headers: { "xi-api-key": elKey } })
    lastStatus = r.status
    return r.ok ? await r.json() as ElVoice : null
  }
  // Clone the recording (cartesia.cloneVoice cleans and levels it), give it
  // the accent, and swap it in for the voice the learner is on.
  const finish = async (
    source: { voiceId: string; sampleId: string; kind: string } | null,
    accent: string | null, plan: Record<string, unknown>,
  ): Promise<Response> => {
    let bytes: Uint8Array
    if (source) {
      const audio = await fetch(
        `https://api.elevenlabs.io/v1/voices/${source.voiceId}/samples/${source.sampleId}/audio`,
        { headers: { "xi-api-key": elKey } })
      if (!audio.ok) return json({ ...plan, result: "failed", detail: `sample ${audio.status}` }, 502)
      bytes = new Uint8Array(await audio.arrayBuffer())
    } else {
      const bin = atob(body.sample_b64!)
      bytes = new Uint8Array(bin.length)
      for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i)
    }
    let clip: File
    if (bytes.length > 12 && String.fromCharCode(...bytes.subarray(0, 4)) === "RIFF") {
      clip = new File([bytes.slice().buffer as ArrayBuffer], "sample.wav", { type: "audio/wav" })
    } else {
      const decoder = new MPEGDecoder()
      await decoder.ready
      const decoded = decoder.decode(bytes)
      decoder.free()
      if (!decoded.samplesDecoded) return json({ ...plan, result: "failed", detail: "undecodable sample" }, 502)
      clip = cartesia.wavFileFromFloat(decoded.channelData, decoded.sampleRate)
    }

    const made = await cartesia.cloneVoice(clip, active.name ?? `Future ${userId.slice(0, 8)}`,
      cartesia.lineLanguage("", target))
    if (!made.ok) return json({ ...plan, result: "failed", detail: made.detail }, 502)
    if (accent && accent !== cartesia.GERMAN_DEFAULT) {
      const ok = await cartesia.ensureAccent(made.voiceId, accent)
      if (!ok.ok) {
        await cartesia.deleteVoice(made.voiceId)
        return json({ ...plan, result: "failed", detail: ok.detail }, 502)
      }
    }
    const id = accent ? `${made.voiceId}:${accent}` : made.voiceId

    // Swap only if the learner is still on the voice we read — a phone that
    // re-recorded or moved itself meanwhile wins.
    const swapped = await swap(db, userId, active.elevenlabs_voice_id, id, active.name)
    if (!swapped) {
      await cartesia.deleteVoice(made.voiceId)
      return json({ ...plan, result: "changed_meanwhile" })
    }
    console.log("voice moved by operator", plan, id)
    return json({ ...plan, result: "moved", to: id })
  }

  // Already on Cartesia. `reclone`: made again from the original recording
  // (2026-10-13 — every clone is now made from a cleaned take, so voices
  // moved before carry their room's noise); else only the accent rules.
  if (cartesia.isCartesiaVoice(active.elevenlabs_voice_id) && body.reclone) {
    const { accent: had } = cartesia.parseVoice(active.elevenlabs_voice_id)
    const accent = chooseAccent(target, had)
    let source: { voiceId: string; sampleId: string; kind: string } | null = null
    for (const r of all) {
      if (cartesia.isCartesiaVoice(r.elevenlabs_voice_id)) continue
      const v = await el(r.elevenlabs_voice_id)
      if (v?.category === "cloned" && v.samples?.[0]) {
        source = { voiceId: r.elevenlabs_voice_id, sampleId: v.samples[0].sample_id, kind: "earlier_clone" }
        break
      }
    }
    const archivedOriginal = body.sample_b64 && body.sample_kind !== "remix"
    if (!source && !archivedOriginal) return json({ user_id: userId, result: "no_recording", from: active.elevenlabs_voice_id })
    const plan = { user_id: userId, target, from: active.elevenlabs_voice_id, accent,
      source: source?.kind ?? "archive_original" }
    if (dry) return json({ ...plan, result: "would_reclone" })
    return await finish(source, accent, plan)
  }

  // Already on Cartesia: only the accent rules.
  if (cartesia.isCartesiaVoice(active.elevenlabs_voice_id)) {
    const { uuid, accent: had } = cartesia.parseVoice(active.elevenlabs_voice_id)
    const accent = chooseAccent(target, had)
    const id = accent ? `${uuid}:${accent}` : uuid
    if (dry) return json({ user_id: userId, result: "cartesia", from: active.elevenlabs_voice_id, to: id })
    const de = await cartesia.ensureAccent(uuid, cartesia.GERMAN_DEFAULT)
    if (accent && accent !== cartesia.GERMAN_DEFAULT) {
      const ok = await cartesia.ensureAccent(uuid, accent)
      if (!ok.ok) return json({ user_id: userId, result: "failed", detail: ok.detail }, 502)
    }
    if (id !== active.elevenlabs_voice_id) await swap(db, userId, active.elevenlabs_voice_id, id, active.name)
    return json({ user_id: userId, result: "cartesia", from: active.elevenlabs_voice_id, to: id, german: de.ok })
  }

  // A parked voice is gone upstream; it moves only from an archived take
  // (the new row is not parked — parking ended with Cartesia, 2026-10-12).
  if (active.parked_at && !body.sample_b64) return json({ user_id: userId, result: "parked" })

  const upstream = await el(active.elevenlabs_voice_id)
  if (!upstream && !body.sample_b64) {
    return json({ user_id: userId, result: "no_upstream_voice", status: lastStatus, from: active.elevenlabs_voice_id })
  }
  const voice: ElVoice = upstream ?? {}

  // The accent the learner hears today.
  const remixed = upstream ? voice.category === "generated" : body.sample_kind === "remix" ||
    /change only the accent/i.test(body.accent_description ?? "")
  const elAccent = remixed
    ? cartesia.accentFromDescription(upstream
      ? [voice.description ?? "", ...Object.values(voice.labels ?? {})].join(" ")
      : body.accent_description ?? "")
    : null
  const accent = chooseAccent(target, elAccent)

  // The recording to clone from.
  let source: { voiceId: string; sampleId: string; kind: string } | null = null
  if (!remixed && voice.samples?.[0]) {
    source = { voiceId: active.elevenlabs_voice_id, sampleId: voice.samples[0].sample_id, kind: "own" }
  }
  const archived = body.sample_b64
    ? { kind: body.sample_kind === "remix" ? "archive_remix" : "archive_original" } : null
  if (!source && !(archived && archived.kind === "archive_original")) {
    for (const r of all) {
      if (r.id === active.id || cartesia.isCartesiaVoice(r.elevenlabs_voice_id)) continue
      const v = await el(r.elevenlabs_voice_id)
      if (v?.category === "cloned" && v.samples?.[0]) {
        source = { voiceId: r.elevenlabs_voice_id, sampleId: v.samples[0].sample_id, kind: "earlier_clone" }
        break
      }
    }
  }
  if (!source && !archived && voice.samples?.[0]) {
    source = { voiceId: active.elevenlabs_voice_id, sampleId: voice.samples[0].sample_id, kind: "remix_sample" }
  }
  if (!source && !archived) return json({ user_id: userId, result: "no_recording", category: voice.category })

  const plan = { user_id: userId, target, from: active.elevenlabs_voice_id,
    category: upstream ? voice.category : "gone_upstream",
    el_accent: elAccent, accent, source: source?.kind ?? archived!.kind }
  if (dry) return json({ ...plan, result: "would_move" })

  return await finish(source, accent, plan)
})

/** German learners speak standard German; an accent they had is kept;
 *  otherwise English is General American, and ja/ko stay plain. */
function chooseAccent(target: string, had: string | null): string | null {
  if (target === "de") return cartesia.GERMAN_DEFAULT
  // Kept only if it is an accent OF the language being learned — a German
  // accent left on an English learner's id does nothing to an English line.
  if (had && cartesia.ACCENT_LANGUAGE[had] === target) return had
  if (target === "en") return "general-american"
  return null
}

async function swap(
  db: ReturnType<typeof createClient>, userId: string, fromId: string, toId: string, name: string | null,
): Promise<boolean> {
  const { data } = await db.from("voice_clones").update({ is_active: false })
    .eq("user_id", userId).eq("is_active", true).eq("elevenlabs_voice_id", fromId).select("id")
  if (!data || data.length === 0) return false
  const { error } = await db.from("voice_clones").insert({
    user_id: userId, elevenlabs_voice_id: toId, is_active: true, name,
  })
  if (error) {
    console.error("voice_clones insert failed", error)
    // Put the old voice back rather than leave the learner with none.
    await db.from("voice_clones").update({ is_active: true })
      .eq("user_id", userId).eq("elevenlabs_voice_id", fromId)
    return false
  }
  return true
}
