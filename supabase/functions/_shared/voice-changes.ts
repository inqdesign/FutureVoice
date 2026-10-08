// One voice change per 30 days (20261009090000_voice_changes.sql).
//
// Every voice the account adds costs one of ElevenLabs' monthly add/edits,
// so after a learner's first voice they get ONE change per rolling 30 days —
// a re-record, a saved accent or a "no accent" rebuild. The remix the app
// makes right after a clone (the accent picked in setup) belongs to that
// clone and is free; so is a parked voice rebuilt. Listening to takes is free.
//
// Lookups fail OPEN: if the status can't be read, nothing is refused.

import { billingClient } from "./credits.ts"

export type VoiceChangeKind = "first" | "default" | "revival" | "change"

/** How long after a clone its default-accent remix (and the previews made
 *  for it) still belong to it. A remix takes ~25 s; this is slack for a
 *  slow network, never a second free voice. */
const DEFAULT_WINDOW_MS = 2 * 60 * 60 * 1000

export async function changesLeft(userId: string): Promise<{ left: number; nextAt: string | null } | null> {
  const { data, error } = await billingClient().rpc("voice_change_status", { p_user_id: userId })
  if (error || !data) return null
  const d = data as { left?: number; next_at?: string | null }
  return { left: d.left ?? 1, nextAt: d.next_at ?? null }
}

/** True right after a clone whose default remix hasn't been saved yet. */
export async function defaultRemixOpen(userId: string): Promise<boolean> {
  const { data, error } = await billingClient().from("voice_changes")
    .select("kind, created_at").eq("user_id", userId)
    .order("created_at", { ascending: false }).limit(1)
  if (error || !data || data.length === 0) return false
  const last = data[0] as { kind: VoiceChangeKind; created_at: string }
  return last.kind !== "default" && Date.now() - Date.parse(last.created_at) < DEFAULT_WINDOW_MS
}

export async function recordVoiceChange(userId: string, kind: VoiceChangeKind): Promise<void> {
  const { error } = await billingClient().from("voice_changes").insert({ user_id: userId, kind })
  if (error) console.error("voice_changes insert failed", kind, error.message)
}

/** The refusal. `voice_limit_reached` in the body is what builds before 1.1.5
 *  recognise and turn into a plain "try again later" instead of raw JSON. */
export function changeLimitResponse(nextAt: string | null, headers: HeadersInit): Response {
  const h = new Headers(headers)
  h.set("Content-Type", "application/json")
  return new Response(JSON.stringify({
    error: "voice_change_limit",
    next_at: nextAt,
    detail: "voice_limit_reached",
  }), { status: 403, headers: h })
}
