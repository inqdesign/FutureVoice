// The three moments, on the owner's phone, while they are happening.
//
// A signup, a subscription, and a learner meeting the paywall. All three are
// already written to tables by paths that exist; nothing here asks the app
// for anything, so no build has to ship for this to start working and a
// purchase path added later is watched the day it writes its first row.
//
// `owner_alerts_claim()` does the thinking (see the migration): it finds what
// has not been announced, CLAIMS it, and hands it over. This function is only
// the sentence and the send. Consequences of that split, both deliberate:
//
//   * A claimed alert is never retried. Telegram being down loses a message
//     rather than delivering it at 3am with four copies behind it.
//   * The TEXT is composed here, from columns. Nothing a learner can type
//     reaches the owner's Telegram.
//
// Not user-callable: called by pg_cron every minute, which has no Supabase
// JWT, so authenticity is CLEANUP_SECRET in X-Cleanup-Secret and an unset
// secret refuses everything.
//
// `{"test": true}` in the body sends one message and touches nothing else —
// the wiring check, so "is Telegram connected at all?" is never answered by
// waiting for a stranger to sign up.

import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0"
import { timingSafeEqual } from "../_shared/auth.ts"
import { notifyOwner } from "../_shared/credits.ts"

/// Alerts per run. A minute that produces more than this is a backlog, and
/// the next minute takes the rest — a phone that buzzes fifty times in a row
/// is worse than one that buzzes fifty times over a minute.
const MAX_PER_RUN = 20

/// Accounts that are the owner's own test fixtures. They are MARKED, never
/// hidden: seeing your own test signup arrive is how you know the pipeline
/// works. Kept in step with `admin/src/assemble.ts`.
const TEST_IDS = new Set([
  "ecd78251-49c4-4e18-a156-6fbe90fd6e3b",
  "c5a85f25-a631-47c5-b32b-fb5bc89c551e",
  "5692cfc2-13ec-4f7e-a3bc-31daee02e28f",
  "b28ca7b1-dbd8-46de-bfd2-5857e05665bc",
])

type Alert = { kind: string; key: string; payload: Record<string, unknown> }

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("method not allowed", { status: 405 })

  const secret = Deno.env.get("CLEANUP_SECRET")
  if (!secret || !timingSafeEqual(req.headers.get("X-Cleanup-Secret") ?? "", secret)) {
    return new Response("forbidden", { status: 403 })
  }

  let body: Record<string, unknown> = {}
  try { body = await req.json() } catch { /* pg_cron sends {} */ }

  if (body.test === true) {
    const ok = await notifyOwner(
      `[nawana] 🔔 알림 배선 확인\n이 메시지가 보이면 텔레그램은 연결돼 있습니다.\n${new Date().toISOString()}`,
    )
    return json({ ok, test: true })
  }

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  )

  const { data, error } = await admin.rpc("owner_alerts_claim", { p_limit: MAX_PER_RUN })
  if (error) {
    console.error("owner-watch: claim failed", error)
    return json({ ok: false, error: error.message }, 500)
  }

  const alerts = (data ?? []) as Alert[]
  let sent = 0
  for (const alert of alerts) {
    const text = compose(alert)
    if (!text) continue
    if (await notifyOwner(text)) sent++
  }
  if (alerts.length) console.log(`owner-watch: ${sent}/${alerts.length} sent`)
  return json({ ok: true, claimed: alerts.length, sent })
})

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status, headers: { "Content-Type": "application/json" },
  })
}

function compose({ kind, payload }: Alert): string | null {
  const p = payload ?? {}
  const userId = String(p.user_id ?? "")
  const who = (p.email as string | null) ?? `익명 계정 · ${userId.slice(0, 8)}`
  const tag = TEST_IDS.has(userId) ? " (내 테스트 계정)" : ""

  const lines: (string | null)[] = []
  switch (kind) {
    case "signup":
      lines.push(`[nawana] 🆕 새 유저 가입${tag}`,
                 `누구: ${who}`,
                 `어떻게: ${p.provider ?? "?"} 로그인`)
      break

    case "subscription": {
      const trial = p.status === "trialing"
      lines.push(`[nawana] ${trial ? "🎁 체험 시작" : "💳 구독 시작"}${tag}`,
                 `누구: ${who}`,
                 `무엇: ${p.plan ?? "?"} · ${p.source ?? "?"}`,
                 trial && p.trial_ends_at ? `체험 종료: ${day(p.trial_ends_at)}` : null)
      break
    }

    case "paywall": {
      const n = Number(p.count ?? 1)
      lines.push(`[nawana] 👀 페이월을 봤습니다${tag}`,
                 `누구: ${who}`,
                 `어디: ${p.source ?? "?"}`,
                 n > 1 ? `오늘 ${n}번째 (하루 한 번만 알립니다)` : null)
      break
    }

    default:
      return null
  }
  lines.push(`id: ${userId}`)
  return lines.filter(Boolean).join("\n")
}

function day(v: unknown): string {
  const d = new Date(String(v))
  return Number.isNaN(d.getTime()) ? String(v) : d.toISOString().slice(0, 16).replace("T", " ") + " UTC"
}
