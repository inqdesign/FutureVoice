// The default accent, applied by the SERVER for builds that can't (2026-10-08).
//
// See 20261008180000_server_default_accent.sql for why. The catalog below is
// the server's copy of `VoiceAccentCatalog` (FutureVoice/Services/VoiceAccent
// .swift) — the default option of each language, same prompt, same sample
// line, same prompt_strength. Keep them in step.
//
// Everything here is best-effort and fails SOFT: a lookup or remix that goes
// wrong means the line is spoken with the plain clone, which is exactly what
// happened before this file existed. Nothing here may fail a synthesis.

import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.45.0"
import { reservedForNewLearners } from "./voice-quota.ts"

const PROMPT_STRENGTH = 0.3

function prompt(accent: string): string {
  return "Keep this exact same voice: the same person, timbre, pitch, age and "
    + "character. Change ONLY the accent — the speaker now has a natural, "
    + `consistent ${accent}. Do not change anything else about how the `
    + "voice sounds."
}

const DEFAULTS: Record<string, { id: string; prompt: string; sample: string }> = {
  en: {
    id: "en-US",
    prompt: prompt("General American English accent"),
    sample: "I'll grab a bottle of water and a coffee around half past eight. "
      + "I can't be late again, the bus leaves at nine, doesn't it?",
  },
  de: {
    id: "de-DE",
    prompt: prompt("Standard German accent (Hochdeutsch) as spoken in Germany"),
    sample: "Morgen früh hole ich zwei Brötchen beim Bäcker, danach fahre ich "
      + "mit dem Zug nach München. Ich rufe dich später an, okay?",
  },
}

export function hasDefaultAccent(language: string | null | undefined): boolean {
  return !!language && language.slice(0, 2) in DEFAULTS
}

// Words that say English or German and nothing else. Words both languages
// spell the same way ("die", "was", "so", "in", "an") are left out on purpose.
const EN_WORDS = new Set(["the", "and", "you", "is", "i", "i'm", "are", "what",
  "how", "to", "it", "that", "this", "my", "your", "have", "do", "we", "with",
  "today", "good", "yeah", "of", "for", "about", "it's", "don't", "can", "be"])
const DE_WORDS = new Set(["ich", "und", "nicht", "ist", "du", "der", "das",
  "bin", "mit", "wie", "auf", "ein", "eine", "wir", "hast", "habe", "heute",
  "auch", "noch", "schon", "mal", "gut", "ja", "dich", "mich", "dir", "mir",
  "für", "über", "zu", "den", "dem", "sind", "bist"])

/** The target language a line is in, when it is English or German beyond
 *  doubt; null otherwise (another language, too short to tell, mixed). The
 *  old builds this serves never say which language is being learned, but the
 *  lines they speak are always in it. */
export function guessAccentLanguage(text: string): "en" | "de" | null {
  const letters = text.match(/\p{L}/gu) ?? []
  if (letters.length < 8) return null
  const latin = letters.filter((c) => /[A-Za-zÀ-ÿß]/.test(c)).length
  if (latin / letters.length < 0.9) return null
  let en = 0, de = 0
  if (/[äöüß]/i.test(text)) de += 2
  for (const w of text.toLowerCase().replace(/[’]/g, "'").match(/[\p{L}']+/gu) ?? []) {
    if (EN_WORDS.has(w)) en++
    if (DE_WORDS.has(w)) de++
  }
  if (en >= 2 && en >= 2 * de) return "en"
  if (de >= 2 && de >= 2 * en) return "de"
  return null
}

type Row = {
  id: string
  user_id: string
  name: string | null
  accent_by_server: boolean | null
  speak_as_voice_id: string | null
  speak_as_language: string | null
  speak_as_started_at: string | null
}

const COLS = "id, user_id, name, accent_by_server, speak_as_voice_id, speak_as_language, speak_as_started_at"

/** Returned instead of a voice id while another request is still making
 *  this voice's remix and the wait ran out — the caller answers 503. */
export const BUSY = "__default_accent_busy__"

/** voice id → what it speaks as, once known for good (an alias, or "never").
 *  Isolate-local, like `verifiedVoiceOwners`. */
const settled = new Map<string, { language: string; voiceId: string } | null>()

/**
 * The voice to synthesize `voiceId` with when it speaks `language`: its
 * default-accent remix if it is an old build's plain clone, made now if it
 * doesn't exist yet; otherwise `voiceId` itself — or `BUSY` (see above).
 * Never throws.
 */
export async function speakAs(opts: {
  admin: SupabaseClient
  apiKey: string
  userId: string
  voiceId: string
  language: string | null
  /** false = only use a remix that already exists (the gateway). */
  create: boolean
}): Promise<string> {
  const { admin, apiKey, userId, voiceId, create } = opts
  const language = opts.language?.slice(0, 2) ?? null
  try {
    if (settled.has(voiceId)) {
      const s = settled.get(voiceId)
      return s && s.language === language ? s.voiceId : voiceId
    }
    let row = await load(admin, userId, voiceId)
    if (!row) return voiceId
    if (!row.accent_by_server) { settled.set(voiceId, null); return voiceId }
    if (row.speak_as_voice_id) {
      settled.set(voiceId, { language: row.speak_as_language ?? "", voiceId: row.speak_as_voice_id })
      return row.speak_as_language === language ? row.speak_as_voice_id : voiceId
    }
    if (!create || !language || !hasDefaultAccent(language)) return voiceId
    // The remix is a new voice; the month's last ones are for first clones.
    if (await reservedForNewLearners(apiKey)) return voiceId

    // Claim the remix. Concurrent first lines (the opener pool is warmed in
    // parallel) wait for the one that won instead of making a second voice.
    const staleBefore = new Date(Date.now() - 120_000).toISOString()
    const { data: claimed } = await admin.from("voice_clones")
      .update({ speak_as_started_at: new Date().toISOString() })
      .eq("id", row.id)
      .is("speak_as_voice_id", null)
      .or(`speak_as_started_at.is.null,speak_as_started_at.lt.${staleBefore}`)
      .select("id")
    if (!claimed || claimed.length === 0) {
      // A remix takes ~25 s upstream whatever the text (measured
      // 2026-10-08: 22–28 s). Waiting past that means the remix failed or is
      // stuck; answer BUSY rather than the plain voice, because an old build
      // CACHES what it gets (the opener pool) and would play the invented
      // accent forever. A failed warm-up is retried; a wrong one never is.
      for (let i = 0; i < 38; i++) {
        await new Promise((r) => setTimeout(r, 1000))
        row = await load(admin, userId, voiceId)
        if (row?.speak_as_voice_id) {
          return row.speak_as_language === language ? row.speak_as_voice_id : voiceId
        }
        if (row && !row.speak_as_started_at) return voiceId   // the remix gave up
      }
      return BUSY
    }

    const target = await remix(apiKey, voiceId, language, row.name ?? "Future Self")
    if (!target) {
      await admin.from("voice_clones").update({ speak_as_started_at: null }).eq("id", row.id)
      return voiceId
    }
    const accent = DEFAULTS[language].id
    await admin.from("voice_clones").insert({
      user_id: userId, elevenlabs_voice_id: target, is_active: false, name: row.name,
    })
    await admin.from("voice_clones")
      .update({ speak_as_voice_id: target, speak_as_language: language, speak_as_accent: accent })
      .eq("id", row.id)
    settled.set(voiceId, { language, voiceId: target })
    await admin.rpc("record_free_usage", {
      p_user_id: userId, p_action: "voice_remix", p_purpose: "accent_default_server",
      p_source_fn: "default-accent", p_idempotency_key: `default-accent:${voiceId}`,
      p_metadata: { source_voice_id: voiceId, voice_id: target, accent }, p_daily_cap: 50,
    }).then(() => {}, () => {})
    console.log("default-accent: remixed", { voiceId, target, accent })
    return target
  } catch (e) {
    console.error("default-accent: failed, speaking plain", voiceId, String(e).slice(0, 300))
    return voiceId
  }
}

async function load(admin: SupabaseClient, userId: string, voiceId: string): Promise<Row | null> {
  // A database without the columns yet answers with an error — that is
  // "no remix", never a failed line.
  const { data, error } = await admin.from("voice_clones").select(COLS)
    .eq("user_id", userId).eq("elevenlabs_voice_id", voiceId).limit(1).maybeSingle()
  if (error) return null
  return data as Row | null
}

async function remix(apiKey: string, voiceId: string, language: string, name: string): Promise<string | null> {
  const d = DEFAULTS[language]
  const previews = await fetch(`https://api.elevenlabs.io/v1/text-to-voice/${voiceId}/remix`, {
    method: "POST",
    headers: { "xi-api-key": apiKey, "Content-Type": "application/json" },
    body: JSON.stringify({ voice_description: d.prompt, text: d.sample, prompt_strength: PROMPT_STRENGTH }),
  })
  if (!previews.ok) {
    console.error("default-accent: previews", previews.status, (await previews.text()).slice(0, 300))
    return null
  }
  const pj = await previews.json() as { previews?: { generated_voice_id: string }[] }
  const generated = pj.previews?.[0]?.generated_voice_id
  if (!generated) return null
  const saved = await fetch("https://api.elevenlabs.io/v1/text-to-voice", {
    method: "POST",
    headers: { "xi-api-key": apiKey, "Content-Type": "application/json" },
    body: JSON.stringify({ voice_name: name, voice_description: d.prompt, generated_voice_id: generated }),
  })
  if (!saved.ok) {
    console.error("default-accent: save", saved.status, (await saved.text()).slice(0, 300))
    return null
  }
  return ((await saved.json()) as { voice_id?: string }).voice_id ?? null
}

/** Delete the remix a voice speaks as (the source is being deleted). */
export async function deleteSpeakAs(admin: SupabaseClient, apiKey: string,
                                    userId: string, voiceId: string): Promise<void> {
  try {
    const row = await load(admin, userId, voiceId)
    const target = row?.speak_as_voice_id
    if (!target) return
    const res = await fetch(`https://api.elevenlabs.io/v1/voices/${target}`,
      { method: "DELETE", headers: { "xi-api-key": apiKey } })
    const body = res.ok ? "" : await res.text()
    if (res.ok || res.status === 404 || body.includes("voice_does_not_exist")) {
      await admin.from("voice_clones").delete().eq("user_id", userId).eq("elevenlabs_voice_id", target)
      settled.delete(voiceId)
    } else {
      console.error("default-accent: delete failed", target, res.status, body.slice(0, 300))
    }
  } catch (e) {
    console.error("default-accent: delete failed", voiceId, String(e).slice(0, 300))
  }
}
