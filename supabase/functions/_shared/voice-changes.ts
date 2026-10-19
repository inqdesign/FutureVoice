// A record of every voice a learner makes (20261009090000_voice_changes.sql).
// It once backed a one-change-per-30-days limit; there is no limit now
// (2026-10-12), and the rows are kept as history.

import { billingClient } from "./credits.ts"

export type VoiceChangeKind = "first" | "default" | "revival" | "change"

export async function recordVoiceChange(userId: string, kind: VoiceChangeKind): Promise<void> {
  const { error } = await billingClient().from("voice_changes").insert({ user_id: userId, kind })
  if (error) console.error("voice_changes insert failed", kind, error.message)
}
