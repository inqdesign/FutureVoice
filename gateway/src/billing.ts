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
  /** Every second this call has counted, sent or not — what the app's
   *  call clock and its ring show, so the clock says what the call costs
   *  (2026-10-25: the app counted on its own rule and the two disagreed). */
  private counted = 0
  /** Learner speech already reported, against the session's running total —
   *  each tick carries the difference. A record beside the bill, never part
   *  of it: `seconds` is what is charged. */
  private speechSent = 0
  /** Seconds of call not yet reported, at FULL length — beside `billable`,
   *  which is what they cost. The two differ only on a pronunciation call
   *  (`rateFor`); every tick carries both, so the ring, the routine and the
   *  usage page count the time practiced while the pool pays the rate. */
  private callPending = 0
  private tickN = 0
  private timer: number | null = null
  private flushing = false
  private walled = false
  /** `stop` ran while a flush was in flight: flush again once it lands, or
   *  the last batch (up to a flush interval) was never sent (2026-10-21). */
  private stopped = false
  private lastSendOk = true
  /** The verified caller, once the gateway knows it. From then on a tick is
   *  sent as the SERVER (service role + this id) and no longer rides on the
   *  learner's access token, which lives an hour: a call that outlived it,
   *  or one opened on a token about to expire, answered 401 on every later
   *  tick and ran unbilled to the session ceiling (2026-11-20). */
  private userId: string | null = null
  setUser(id: string): void { this.userId = id }

  /** ~voiceGraceSeconds on the client: how recently the learner must have
   *  been heard for a second to count as theirs. */
  static readonly graceMs = 6000
  /** Flush cadence. 15 s keeps a killed DO's unbilled tail small without
   *  hammering the edge function. */
  private static readonly flushEveryMs = 15_000

  /** What one second of each kind of call costs (founder, 2026-11-04: a
   *  pronunciation lesson spends talk time fast, so it costs half). Every
   *  other kind, and a call that didn't say, costs a whole second. */
  static rateFor(mode: string | null): number {
    return mode === "pron" ? 0.5 : 1
  }

  constructor(private env: Env,
              private token: string,
              private sessionKey: string,
              private language: string | null,
              private isBillable: () => boolean,
              private onWall: (code: WallCode) => void,
              /** The session's running learner-speech seconds (`speechSeconds`). */
              private speech: () => number = () => 0,
              /** Called when `counted` moves (≤ once a second). */
              private onCount: (seconds: number) => void = () => {},
              /** The call's kind ("free" · "tutor" · "pron"), on every tick
               *  for the usage page's split; null when the app didn't say. */
              private mode: () => string | null = () => null) {}

  /** Charge 1 s before the opener speaks — same trick as the classic path's
   *  preflight tick, so an empty allowance surfaces BEFORE the greeting
   *  instead of granting a free minute per fresh session. */
  async preflight(): Promise<WallCode | null> {
    return this.send(1, true)
  }

  start(): void {
    if (this.timer !== null) return
    let sinceFlush = 0
    this.timer = setInterval(() => {
      if (this.isBillable()) {
        this.billable += TalkBilling.rateFor(this.mode())
        this.callPending += 1
        this.counted += 1
        // Whole seconds: the app reads a fractional total as no report at
        // all (the clock froze at 0:05, 2026-10-25).
        this.onCount(Math.floor(this.counted))
      }
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
    this.stopped = true
    void this.flush()
  }

  private async flush(): Promise<void> {
    if (this.flushing || this.walled) return
    // talk-tick takes 1–600 s per call. A backlog past that (re-queued after
    // failed sends) was refused as a 400 and re-queued forever, so the rest
    // of the call was never billed (2026-10-21) — send it in slices.
    const seconds = Math.min(600, Math.floor(this.billable))
    if (seconds < 1) return
    this.flushing = true
    this.billable -= seconds
    const spoke = Math.max(0, Math.floor(this.speech() - this.speechSent))
    this.speechSent += spoke
    const call = Math.min(1200, Math.floor(this.callPending))
    this.callPending -= call
    const wall = await this.send(seconds, false, spoke, call)
    this.flushing = false
    if (wall) {
      this.walled = true
      this.onWall(wall)
      return
    }
    // The call ended while this one was in flight, or a backlog remains:
    // send the rest now rather than never.
    // Only after a send that LANDED: a failing one (an expired token) would
    // otherwise retry in a tight loop after the call is over.
    if (this.stopped && this.lastSendOk && this.billable >= 1) void this.flush()
  }

  /** One talk-tick call. Returns a wall code on 402, null on success.
   *  A transport failure puts the seconds back for the next flush — the
   *  idempotency key was already consumed by the attempt counter, so a
   *  retried batch can never double-bill. */
  /** `preflight` says this is the tick that OPENS a call, which is the one
   *  the minimum-call floor is judged at: a free pool with under a minute
   *  left cannot carry a conversation, so the server closes it here and the
   *  tap answers with the paywall instead of a call that dies in seconds
   *  (20260920180000). Mid-call ticks are never judged that way — that would
   *  throw away time the learner still has. */
  private async send(seconds: number, preflight = false,
                     spoke: number | null = null,
                     call: number | null = null): Promise<WallCode | null> {
    this.tickN += 1
    try {
      const post = (asServer: boolean) => fetch(`${this.env.SUPABASE_URL}/functions/v1/talk-tick`, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${asServer ? this.env.SUPABASE_SERVICE_ROLE_KEY : this.token}`,
          apikey: this.env.SUPABASE_ANON_KEY,
          "Content-Type": "application/json",
          "X-Idempotency-Key": `gw:${this.sessionKey}:${this.tickN}`,
        },
        body: JSON.stringify({
          ...(asServer ? { user_id: this.userId } : {}),
          seconds,
          session_id: this.sessionKey,
          language: this.language,
          preflight,
          ...(spoke !== null ? { learner_seconds: Math.min(spoke, 600) } : {}),
          ...(this.mode() ? { mode: this.mode() } : {}),
          // The call time these seconds paid for, when it differs from what
          // was charged — a record for the ring, never the price.
          ...(call !== null && call !== seconds ? { call_seconds: call } : {}),
        }),
      })
      // As the server once the caller is verified. A talk-tick from before
      // it knew the server answers 401 (nothing written, the key unspent):
      // the learner's own token then, as before.
      let r = await post(this.userId !== null)
      if (r.status === 401 && this.userId !== null) r = await post(false)
      if (r.status === 402) {
        const body = (await r.json().catch(() => ({}))) as { error?: string }
        return body.error === "daily_cap_reached"
          ? "daily_cap_reached"
          : "insufficient_credits"
      }
      this.lastSendOk = r.ok
      if (!r.ok) {
        console.log(`billing: talk-tick ${r.status} — re-queueing ${seconds}s`)
        this.billable += seconds
        if (spoke) this.speechSent -= spoke
        if (call) this.callPending += call
      }
      return null
    } catch (e) {
      this.lastSendOk = false
      console.log(`billing: talk-tick failed (${String(e)}) — re-queueing ${seconds}s`)
      this.billable += seconds
      if (spoke) this.speechSent -= spoke
      if (call) this.callPending += call
      return null
    }
  }
}
