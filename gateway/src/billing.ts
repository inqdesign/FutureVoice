// Server-side talk metering — the gateway charges, the client only draws.
//
// The classic path trusts the app's TalkMeter to tick `talk-tick`; on this
// path a modified client could connect to the gateway directly and never
// tick, so the DO meters the call itself. Same billing rule as
// ConversationView.isBillableMoment, read off what the SESSION knows: the
// fluent self is speaking (or a reply is being written), or the learner is
// audibly mid-utterance. Silence is free.
//
// It spends through the SAME `talk-tick` edge function, with the caller's
// own JWT — so the 402 semantics, idempotency ledger, Core per-language
// ledger and per-day pools are all the ones the rest of billing already
// uses. Idempotency keys are namespaced "gw:" so a gateway tick can never
// collide with a legacy client tick.

import type { Env } from "./supabase"

export type WallCode = "insufficient_credits" | "daily_cap_reached"

export class TalkBilling {
  private billable = 0
  private tickN = 0
  private timer: number | null = null
  private flushing = false
  private walled = false

  /** ~voiceGraceSeconds on the client: how recently the learner must have
   *  been heard for a second to count as theirs. */
  static readonly graceMs = 6000
  /** Flush cadence. 15 s keeps a killed DO's unbilled tail small without
   *  hammering the edge function. */
  private static readonly flushEveryMs = 15_000

  constructor(private env: Env,
              private token: string,
              private sessionKey: string,
              private language: string | null,
              private isBillable: () => boolean,
              private onWall: (code: WallCode) => void) {}

  /** Charge 1 s before the opener speaks — same trick as the classic path's
   *  preflight tick, so an empty allowance surfaces BEFORE the greeting
   *  instead of granting a free minute per fresh session. */
  async preflight(): Promise<WallCode | null> {
    return this.send(1)
  }

  start(): void {
    if (this.timer !== null) return
    let sinceFlush = 0
    this.timer = setInterval(() => {
      if (this.isBillable()) this.billable += 1
      sinceFlush += 1000
      if (sinceFlush >= TalkBilling.flushEveryMs) {
        sinceFlush = 0
        void this.flush()
      }
    }, 1000) as unknown as number
  }

  /** Final flush; safe to call more than once. */
  stop(): void {
    if (this.timer !== null) { clearInterval(this.timer); this.timer = null }
    void this.flush()
  }

  private async flush(): Promise<void> {
    if (this.flushing || this.walled) return
    const seconds = Math.floor(this.billable)
    if (seconds < 1) return
    this.flushing = true
    this.billable -= seconds
    const wall = await this.send(seconds)
    this.flushing = false
    if (wall) {
      this.walled = true
      this.onWall(wall)
    }
  }

  /** One talk-tick call. Returns a wall code on 402, null on success.
   *  A transport failure puts the seconds back for the next flush — the
   *  idempotency key was already consumed by the attempt counter, so a
   *  retried batch can never double-bill. */
  private async send(seconds: number): Promise<WallCode | null> {
    this.tickN += 1
    try {
      const r = await fetch(`${this.env.SUPABASE_URL}/functions/v1/talk-tick`, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${this.token}`,
          apikey: this.env.SUPABASE_ANON_KEY,
          "Content-Type": "application/json",
          "X-Idempotency-Key": `gw:${this.sessionKey}:${this.tickN}`,
        },
        body: JSON.stringify({
          seconds,
          session_id: this.sessionKey,
          language: this.language,
        }),
      })
      if (r.status === 402) {
        const body = (await r.json().catch(() => ({}))) as { error?: string }
        return body.error === "daily_cap_reached"
          ? "daily_cap_reached"
          : "insufficient_credits"
      }
      if (!r.ok) {
        console.log(`billing: talk-tick ${r.status} — re-queueing ${seconds}s`)
        this.billable += seconds
      }
      return null
    } catch (e) {
      console.log(`billing: talk-tick failed (${String(e)}) — re-queueing ${seconds}s`)
      this.billable += seconds
      return null
    }
  }
}
