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

let cached: { at: number; remaining: number; resetAt: string | null } | null = null

/** When the allowance next resets (ISO), as ElevenLabs last reported it —
 *  the subscription's renewal, `next_character_count_reset_unix`. It moves
 *  every month, so every refusal carries the current one (2026-10-10). */
export function quotaResetAt(): string | null {
  return cached?.resetAt ?? null
}

/** Voices the account can still add this month, or null if unknown.
 *  `fresh` skips the 60 s cache — after an upstream refusal, to tell a spent
 *  allowance from any other failure. */
export async function voicesLeft(apiKey: string, fresh = false): Promise<number | null> {
  if (!fresh && cached && Date.now() - cached.at < 60_000) return cached.remaining
  try {
    const r = await fetch("https://api.elevenlabs.io/v1/user/subscription", {
      headers: { "xi-api-key": apiKey },
    })
    if (!r.ok) return null
    const s = await r.json() as {
      voice_add_edit_counter?: number; max_voice_add_edits?: number
      next_character_count_reset_unix?: number
    }
    if (typeof s.voice_add_edit_counter !== "number" || typeof s.max_voice_add_edits !== "number") return null
    const remaining = s.max_voice_add_edits - s.voice_add_edit_counter
    const resetAt = typeof s.next_character_count_reset_unix === "number"
      ? new Date(s.next_character_count_reset_unix * 1000).toISOString() : null
    cached = { at: Date.now(), remaining, resetAt }
    return remaining
  } catch {
    return null
  }
}

/** Nothing left at all this month: even a first voice can't be made. */
export async function quotaSpent(apiKey: string, fresh = false): Promise<boolean> {
  const left = await voicesLeft(apiKey, fresh)
  return left !== null && left <= 0
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

/** The refusal. 503 with a body every build shows as an error message;
 *  `available_at` is when voices can be made again (builds from 2026-10-10
 *  turn it into a dated line in the app language). */
export function reservedResponse(headers: HeadersInit): Response {
  const h = new Headers(headers)
  h.set("Content-Type", "application/json")
  return new Response(JSON.stringify({
    error: "voice_quota_reserved",
    message: "Making a new voice is paused for a few days. Your current voice keeps working.",
    available_at: quotaResetAt(),
  }), { status: 503, headers: h })
}

/** The month is spent: no voice at all can be made, a first one included.
 *  A build from 2026-10-10 keeps the learner's recording, lets them in on a
 *  stand-in voice and builds theirs after `available_at`. */
export function spentResponse(headers: HeadersInit): Response {
  const h = new Headers(headers)
  h.set("Content-Type", "application/json")
  return new Response(JSON.stringify({
    error: "voice_quota_full",
    message: "Making new voices is paused for a few days. Please try again later.",
    available_at: quotaResetAt(),
  }), { status: 503, headers: h })
}
