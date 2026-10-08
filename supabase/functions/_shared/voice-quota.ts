// The account's monthly voice creations, kept for new learners (2026-10-08).
//
// ElevenLabs counts every voice ADDED to the account against a monthly
// allowance (`voice_add_edit_counter` / `max_voice_add_edits`: Pro 290) —
// deleting a voice gives nothing back, so it is not the slot count. Every
// clone, re-record, saved accent remix and server default-accent remix spends
// one. On 2026-10-08 the account stood at 274/290 three days before the
// reset, and a handful of learners re-recording or trying accents could
// have spent the rest, leaving the next signup unable to make a voice at all
// — onboarding stuck at its first server step.
//
// So below `VOICE_QUOTA_RESERVE` remaining (default 12) only a learner's FIRST
// clone is made; everything else is refused until the reset. Fails OPEN: if
// the counter can't be read, nothing is refused — a lookup hiccup must not
// stop a voice the account could have made.

let cached: { at: number; remaining: number } | null = null

/** Voices the account can still add this month, or null if unknown. */
export async function voicesLeft(apiKey: string): Promise<number | null> {
  if (cached && Date.now() - cached.at < 60_000) return cached.remaining
  try {
    const r = await fetch("https://api.elevenlabs.io/v1/user/subscription", {
      headers: { "xi-api-key": apiKey },
    })
    if (!r.ok) return null
    const s = await r.json() as { voice_add_edit_counter?: number; max_voice_add_edits?: number }
    if (typeof s.voice_add_edit_counter !== "number" || typeof s.max_voice_add_edits !== "number") return null
    const remaining = s.max_voice_add_edits - s.voice_add_edit_counter
    cached = { at: Date.now(), remaining }
    return remaining
  } catch {
    return null
  }
}

/** True when what is left is held for first clones. */
export async function reservedForNewLearners(apiKey: string): Promise<boolean> {
  const reserve = Number(Deno.env.get("VOICE_QUOTA_RESERVE") ?? "12")
  const left = await voicesLeft(apiKey)
  if (left === null || !Number.isFinite(reserve)) return false
  const held = left <= reserve
  if (held) console.log("voice-quota: holding the rest for first clones", { left, reserve })
  return held
}

/** The refusal. 503 with a body every build shows as an error message. */
export function reservedResponse(headers: HeadersInit): Response {
  const h = new Headers(headers)
  h.set("Content-Type", "application/json")
  return new Response(JSON.stringify({
    error: "voice_quota_reserved",
    message: "Making a new voice is paused for a few days. Your current voice keeps working.",
  }), { status: 503, headers: h })
}
