// The owner hears about a subscribe tap the moment it happens.
//
// Body: { phase: "tapped" | "result", plan, source, step, trial,
//         outcome?: "purchased" | "cancelled" | "failed", price?, country? }
//
// `paywall_purchase_tapped` / `paywall_purchase_result` already land in
// `client_events` (and PostHog) for the funnel, but both are questions asked
// of a table LATER. What could not be seen at all was the tap that never
// became a charge — Korea's ₩0→정가 consent wall is refused inside Apple's
// own sheet, so the app's own data shows someone who reached the button and
// nothing else, days after the fact. This is that moment, on a phone.
//
// Three things the shape is deliberate about:
//   * The TEXT is composed here. The client names a plan and a source out of
//     a fixed vocabulary; it never hands over a string to be sent, so the one
//     client-triggered path into the owner's Telegram can't be used to write
//     to it.
//   * Every ping is recorded (`paywall_owner_ping` in client_events) and the
//     record is what enforces the per-day cap below — a signed-in account
//     looping the button must not become a phone that buzzes all night.
//   * Nothing here is allowed to matter to the caller. It answers 200 with
//     no body worth reading; the app fires it and forgets it.

import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { requireUser, handlePreflight, errorResponse, cors } from "../_shared/auth.ts"
import { notifyOwner, serviceRoleClient } from "../_shared/credits.ts"

/**
 * Pings per user per rolling 24 hours — a tap and its result are two, so
 * this is ten attempts. Above it the row is still written, silently.
 */
const MAX_PINGS_PER_DAY = 20

const PHASES = ["tapped", "result"] as const
// `unavailable` is not Apple's answer — it is OURS: the button was tapped
// with no purchasable product behind it, so Apple's sheet never opened.
const OUTCOMES = ["purchased", "cancelled", "failed", "unavailable"] as const

/** A short machine token the client chose: plan ids, sources, steps. */
function token(v: unknown, max = 40): string | null {
  if (typeof v !== "string") return null
  const s = v.trim()
  if (!s || s.length > max) return null
  return /^[A-Za-z0-9_.-]+$/.test(s) ? s : null
}

/** Free text (a localized price) — length-capped and stripped of newlines. */
function line(v: unknown, max = 24): string | null {
  if (typeof v !== "string") return null
  const s = v.replace(/\s+/g, " ").trim()
  return s ? s.slice(0, max) : null
}

Deno.serve(async (req) => {
  const pre = handlePreflight(req)
  if (pre) return pre
  if (req.method !== "POST") return errorResponse(405, "method not allowed")

  const authed = await requireUser(req)
  if (authed instanceof Response) return authed
  const { user } = authed

  let body: Record<string, unknown>
  try { body = await req.json() } catch { return errorResponse(400, "invalid json body") }

  const phase = PHASES.find((p) => p === body.phase)
  if (!phase) return errorResponse(400, "phase must be tapped or result")
  const outcome = OUTCOMES.find((o) => o === body.outcome) ?? null
  if (phase === "result" && !outcome) return errorResponse(400, "result needs an outcome")

  const plan = token(body.plan) ?? "unknown"
  const source = token(body.source) ?? "unknown"
  const step = token(body.step, 20) ?? "unknown"
  const trial = body.trial === true
  const price = line(body.price)
  const country = token(body.country, 3)

  const props = {
    phase, outcome, plan, source, step, trial,
    price, country,
    build: line(body.build, 12), version: line(body.version, 12),
  }

  try {
    const svc = serviceRoleClient()

    // The cap reads the pings this function itself wrote, not the client's
    // own funnel rows — those are inserted by a detached task that may not
    // have landed yet, and a cap has to count something it can be sure of.
    const since = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString()
    const { count } = await svc
      .from("client_events")
      .select("id", { count: "exact", head: true })
      .eq("user_id", user.id)
      .eq("event", "paywall_owner_ping")
      .gte("created_at", since)

    await svc.from("client_events").insert({
      user_id: user.id, event: "paywall_owner_ping", properties: props,
    })

    if ((count ?? 0) < MAX_PINGS_PER_DAY) {
      await notifyOwner(compose({ ...props, email: user.email, userId: user.id }))
    }
  } catch (e) {
    // A notification is never a reason to answer an error to a screen that
    // is in the middle of a purchase.
    console.error("paywall-notify failed (non-fatal)", e)
  }

  return new Response(JSON.stringify({ ok: true }), {
    status: 200, headers: { "Content-Type": "application/json", ...cors() },
  })
})

function compose(p: {
  phase: string; outcome: string | null; plan: string; source: string; step: string
  trial: boolean; price: string | null; country: string | null
  build: string | null; version: string | null
  email?: string; userId: string
}): string {
  const head = p.phase === "tapped"
    ? "구독 버튼 눌림"
    : p.outcome === "purchased" ? "✅ 결제됨"
    : p.outcome === "failed" ? "⚠️ 실패"
    : p.outcome === "unavailable" ? "🛑 살 게 없는 버튼을 눌렀음"
    : "🚫 취소"

  const who = p.email ?? `익명 계정 · ${p.userId.slice(0, 8)}`
  const what = [p.plan, p.trial ? "체험" : null, p.price, p.country]
    .filter(Boolean).join(" · ")
  const where = p.phase === "tapped" ? `${p.source} → ${p.step}` : p.source
  const build = [p.version, p.build && `(${p.build})`].filter(Boolean).join(" ")

  return [
    `[nawana] ${head}`,
    `누구: ${who}`,
    `무엇: ${what}`,
    `어디: ${where}`,
    build ? `빌드: ${build}` : null,
    `id: ${p.userId}`,
  ].filter(Boolean).join("\n")
}
