// Session-scoped Supabase glue: verify the caller once, check voice
// ownership once. This is the whole point of the gateway vs the per-turn
// edge functions — these round trips happen ONCE per call, not per line.

export interface Env {
  CALL_SESSION: DurableObjectNamespace
  SUPABASE_URL: string
  SUPABASE_ANON_KEY: string
  /** Service-role key, used ONLY for the voice_clones ownership read —
   *  the same query the elevenlabs-tts edge function makes. */
  SUPABASE_SERVICE_ROLE_KEY: string
  GEMINI_API_KEY: string
  ELEVENLABS_API_KEY: string
  /** Half-cascade Live model ("models/..."); see README before changing. */
  GEMINI_LIVE_MODEL?: string
  /** Model that re-reads an utterance the live transcriber wrote in the
   *  wrong script (see reread.ts). Default gemini-3.1-flash-lite. */
  GEMINI_REREAD_MODEL?: string
  /** Reply model override. Exists so a bad model release rolls back without
   *  a deploy, and so the reply-failure path can be exercised on purpose. */
  GEMINI_REPLY_MODEL?: string
  /** Hedge target when the reply model stalls (default flash-lite). */
  GEMINI_REPLY_FALLBACK_MODEL?: string
  /** ElevenLabs streaming output format; pcm_44100 needs a Pro plan. */
  ELEVEN_OUTPUT_FORMAT?: string
  /** "1" allows unauthenticated sessions — `wrangler dev` ONLY, never set
   *  on the deployed worker. */
  DEV_ALLOW_ANON?: string
}

/** The four counterpart preset voices (VoicePreset.catalog) — mirror of the
 *  allowlist in supabase/functions/elevenlabs-tts. Keep in sync. */
const PRESET_VOICE_IDS = new Set([
  "NDTYOmYEjbDIVCKB35i3", "UgBBYS2sOqTuMpoF3BR0",
  "FF59babHL8N8gfTgtBMT", "L0Dsvb3SLTyegXwtm47J",
  // The same four slots voiced natively for Korean and Japanese learners
  // (VoicePreset.speaking, 2026-09-28): Sian, KO-Calm, Han, Joon.
  "5n5gqmaQi9Ewevrz7bOS", "L4az9Gb378GIycFl2nAB",
  "8jHHF8rMqMlg8if2mOUe", "AKF7f2y1L8ktV5vxXILw",
])

/** Resolve the Supabase access token to a user id, or null. */
export async function verifyUser(env: Env, token: string): Promise<string | null> {
  const r = await fetch(`${env.SUPABASE_URL}/auth/v1/user`, {
    headers: {
      apikey: env.SUPABASE_ANON_KEY,
      Authorization: `Bearer ${token}`,
    },
  })
  if (!r.ok) return null
  const user = (await r.json()) as { id?: string }
  return user?.id ?? null
}

/** May this user speak with this voice? Same deepfake rule as the TTS edge
 *  function: a preset voice, or a clone row owned by the user — never another
 *  user's voice id. `parked` = their own clone, deleted upstream because
 *  nobody was paying for it (park-idle-voices): answered as a spent pool, not
 *  as a forbidden voice, so the app shows its paywall. */
export async function ownsVoice(env: Env, userId: string, voiceId: string): Promise<"ok" | "forbidden" | "parked"> {
  if (PRESET_VOICE_IDS.has(voiceId)) return "ok"
  const url = `${env.SUPABASE_URL}/rest/v1/voice_clones` +
    `?user_id=eq.${encodeURIComponent(userId)}` +
    `&elevenlabs_voice_id=eq.${encodeURIComponent(voiceId)}` +
    `&select=id,parked_at&limit=1`
  const r = await fetch(url, {
    headers: {
      apikey: env.SUPABASE_SERVICE_ROLE_KEY,
      Authorization: `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}`,
    },
  })
  if (!r.ok) return "forbidden"
  const rows = (await r.json()) as { parked_at?: string | null }[]
  if (!Array.isArray(rows) || rows.length === 0) return "forbidden"
  return rows[0]?.parked_at ? "parked" : "ok"
}

/** One 0-delta `usage_ledger` row with what a call cost upstream (2026-10-08).
 *
 *  The call's Gemini work — the live transcriber and every reply — goes
 *  straight to Google from here, so until this the ledger saw none of it and
 *  the cost views measured about a quarter of the Gemini bill. Same two RPCs
 *  the `gemini` edge function uses: `record_free_usage` writes the row (keyed,
 *  so a retry can't double it), `record_provider_usage` merges the token
 *  counts in the keys `usage_cost_component` prices. Never throws: a lost row
 *  is a hole in a dashboard, never a failed call. */
export async function recordGeminiUsage(
  env: Env, userId: string, idempotencyKey: string,
  purpose: string, model: string, usage: Record<string, number | boolean>,
): Promise<void> {
  const rpc = (fn: string, body: unknown) => fetch(`${env.SUPABASE_URL}/rest/v1/rpc/${fn}`, {
    method: "POST",
    headers: {
      apikey: env.SUPABASE_SERVICE_ROLE_KEY,
      Authorization: `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  })
  try {
    const row = await rpc("record_free_usage", {
      p_user_id: userId, p_action: "gemini", p_purpose: purpose, p_source_fn: "gateway",
      p_idempotency_key: idempotencyKey, p_metadata: { model, purpose },
      // Counting, not limiting: the call's own meter is the limit.
      p_daily_cap: 1_000_000,
    })
    if (!row.ok) { console.log(`ledger ${purpose}: ${row.status} ${(await row.text()).slice(0, 160)}`); return }
    const merged = await rpc("record_provider_usage", { p_idempotency_key: idempotencyKey, p_usage: usage })
    if (!merged.ok) console.log(`ledger ${purpose} usage: ${merged.status} ${(await merged.text()).slice(0, 160)}`)
  } catch (e) {
    console.log(`ledger ${purpose} failed: ${String(e).slice(0, 120)}`)
  }
}
