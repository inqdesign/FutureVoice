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
 *  user's voice id. */
export async function ownsVoice(env: Env, userId: string, voiceId: string): Promise<boolean> {
  if (PRESET_VOICE_IDS.has(voiceId)) return true
  const url = `${env.SUPABASE_URL}/rest/v1/voice_clones` +
    `?user_id=eq.${encodeURIComponent(userId)}` +
    `&elevenlabs_voice_id=eq.${encodeURIComponent(voiceId)}` +
    `&select=id&limit=1`
  const r = await fetch(url, {
    headers: {
      apikey: env.SUPABASE_SERVICE_ROLE_KEY,
      Authorization: `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}`,
    },
  })
  if (!r.ok) return false
  const rows = (await r.json()) as unknown[]
  return Array.isArray(rows) && rows.length > 0
}
