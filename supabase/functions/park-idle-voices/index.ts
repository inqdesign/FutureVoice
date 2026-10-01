// Park the voices nobody is paying for.
//
// ElevenLabs holds a fixed number of custom voices for the WHOLE account
// (Pro: 160), and every learner's clone is one. A learner who stopped paying,
// or never started and stopped coming, keeps a slot forever unless something
// gives it back. This is that something. Rules and reasons:
// `20260928140000_park_idle_voices.sql` (`parkable_voice_owners`).
//
// Parking = delete every voice of the user upstream, then stamp `parked_at` on
// the active row. The user, their rows, their talks and every audio file on
// their phone stay. The phone rebuilds the voice from its own recording at the
// next call tap the account can pay for (`VoiceRevival` in the app).
//
// Never unannounced (2026-10-01): two days before a voice qualifies, a row in
// `voice_park_notices` fixes the date and a push names it; the voice is
// parked only after that date, and only for the same idle stretch.
//
// Not user-callable: `verify_jwt = false`, and the caller proves itself with
// CLEANUP_SECRET in X-Cleanup-Secret — the same secret the anonymous sweep
// uses. Unset → every request refused. `?dry=1` lists who would be announced
// and who parked, and touches nothing. Announcing needs PUSH_SECRET.

import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0"
import { timingSafeEqual } from "../_shared/auth.ts"

/// Founder's call, 2026-09-28. The SQL floors it at 7 whatever is passed.
const IDLE_DAYS = 7
/// Bounded per run so one invocation can't spend minutes in ElevenLabs calls.
const MAX_PER_RUN = 100
/// How long before the delete the learner hears about it (founder, 2026-10-01).
const WARN_LEAD_DAYS = 2
const MAX_WARN_PER_RUN = 200

interface Candidate { user_id: string; rule: string; balance: number; idle_since: string }

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("method not allowed", { status: 405 })
  }
  const secret = Deno.env.get("CLEANUP_SECRET")
  if (!secret || !timingSafeEqual(req.headers.get("X-Cleanup-Secret") ?? "", secret)) {
    return new Response("forbidden", { status: 403 })
  }
  const params = new URL(req.url).searchParams
  const dry = params.get("dry") === "1"
  // `?rule=spent` parks only rule A (nothing left to spend). Used while the
  // App Store build is one that cannot re-clone by itself: for those learners
  // the paywall is the right answer on any build, whereas rule B's free
  // minutes would be stranded until the new build lands (2026-09-28).
  const onlyRule = params.get("rule")

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  )
  const elevenKey = Deno.env.get("ELEVENLABS_API_KEY")
  if (!elevenKey && !dry) {
    return new Response(JSON.stringify({ error: "server missing ELEVENLABS_API_KEY" }), { status: 500 })
  }

  // Two steps over one candidate list (`20261001120000_voice_park_notice`):
  // ANNOUNCE two days before a voice would qualify, PARK once the announced
  // date has passed. Never the second without the first.
  const { data: candidates, error } = await admin.rpc("voice_parking_candidates", {
    p_limit: 2000,
  })
  if (error) {
    console.error("park-idle-voices: lookup failed", error)
    return new Response(JSON.stringify({ error: error.message }), { status: 500 })
  }
  const all = ((candidates ?? []) as Candidate[])
    .filter((r) => !onlyRule || r.rule === onlyRule)

  const { data: noticeRows } = await admin
    .from("voice_park_notices")
    .select("user_id, idle_since, park_after")
    .in("user_id", all.map((r) => r.user_id))
  const notices = (noticeRows ?? []) as { user_id: string; idle_since: string; park_after: string }[]
  const noticeFor = (r: Candidate) => notices.find((n) =>
    n.user_id === r.user_id && Date.parse(n.idle_since) === Date.parse(r.idle_since))

  const now = Date.now()
  const day = 86_400_000
  const toWarn: Candidate[] = []
  const rows: Candidate[] = []
  for (const r of all) {
    const idleFor = now - Date.parse(r.idle_since)
    const notice = noticeFor(r)
    if (!notice) {
      if (idleFor >= (IDLE_DAYS - WARN_LEAD_DAYS) * day) toWarn.push(r)
    } else if (now >= Date.parse(notice.park_after) && idleFor >= IDLE_DAYS * day) {
      rows.push(r)
    }
  }
  rows.splice(MAX_PER_RUN)
  toWarn.splice(MAX_WARN_PER_RUN)

  if (dry) {
    return json({
      dry: true,
      warn: toWarn.map((r) => ({ ...r, ...parkDate(r.idle_since, now) })),
      park: rows,
    })
  }

  const pushSecret = Deno.env.get("PUSH_SECRET")
  if (!pushSecret) {
    return new Response(JSON.stringify({ error: "server missing PUSH_SECRET" }), { status: 500 })
  }

  let warned = 0
  let pushed = 0
  for (const r of toWarn) {
    const { date, parkAfter } = parkDate(r.idle_since, now)
    const { error: insErr } = await admin.from("voice_park_notices").insert({
      user_id: r.user_id, idle_since: r.idle_since, rule: r.rule,
      park_after: parkAfter.toISOString(),
    })
    if (insErr) {
      // A duplicate means another run announced this stretch already.
      console.error("park-idle-voices: notice failed", r.user_id, insErr.message)
      continue
    }
    warned++
    const sent = await announce(r, date, pushSecret)
    pushed += sent
    if (sent) {
      await admin.from("voice_park_notices").update({ pushed: sent })
        .eq("user_id", r.user_id).eq("idle_since", r.idle_since)
    }
  }

  let parkedUsers = 0
  let deletedVoices = 0
  const failed: string[] = []

  for (const row of rows) {
    // Every voice the user still has a row for: the active one, and any
    // replaced one whose own delete never landed (those hold a slot too).
    const { data: clones } = await admin
      .from("voice_clones")
      .select("id, elevenlabs_voice_id, is_active")
      .eq("user_id", row.user_id)

    let upstreamOK = true
    for (const clone of clones ?? []) {
      if (!clone.elevenlabs_voice_id) continue
      const res = await fetch(
        `https://api.elevenlabs.io/v1/voices/${clone.elevenlabs_voice_id}`,
        { method: "DELETE", headers: { "xi-api-key": elevenKey! } },
      )
      // A DELETE on a voice that is already gone answers 400
      // `voice_does_not_exist`, not 404 (see cleanup-anonymous-voices).
      const body = res.ok ? "" : await res.text()
      const alreadyGone = res.status === 404 ||
        (res.status === 400 && body.includes("voice_does_not_exist"))
      if (res.ok || alreadyGone) {
        deletedVoices++
      } else {
        upstreamOK = false
        console.error("park-idle-voices: voice delete failed",
          clone.elevenlabs_voice_id, res.status, body.slice(0, 300))
      }
    }

    // A voice still alive upstream is NOT marked parked: the next run tries
    // again, and until then the learner's voice simply keeps working.
    if (!upstreamOK) {
      failed.push(row.user_id)
      continue
    }

    const { error: upErr } = await admin
      .from("voice_clones")
      .update({ parked_at: new Date().toISOString() })
      .eq("user_id", row.user_id)
      .eq("is_active", true)
      .is("parked_at", null)
    if (upErr) {
      console.error("park-idle-voices: stamp failed", row.user_id, upErr.message)
      failed.push(row.user_id)
      continue
    }
    parkedUsers++
    console.log(`park-idle-voices: parked ${row.user_id} rule=${row.rule} idle_since=${row.idle_since}`)
  }

  return json({ candidates: all.length, warned, pushed, scanned: rows.length,
                parkedUsers, deletedVoices, failed })
})

function json(body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status: 200, headers: { "Content-Type": "application/json" },
  })
}

/// The day named in the push, and the moment parking may happen.
///
/// The phone's time zone is unknown here, so the date is a UTC calendar day
/// at least WARN_LEAD_DAYS away, and parking waits until noon UTC of the day
/// AFTER it — past the end of that date everywhere from UTC-12 to UTC+12.
/// The push says "after <date>", which is then true wherever they are.
function parkDate(idleSince: string, now: number): { date: Date; parkAfter: Date } {
  const day = 86_400_000
  const earliest = Math.max(Date.parse(idleSince) + IDLE_DAYS * day, now + WARN_LEAD_DAYS * day)
  const d = new Date(earliest)
  const date = new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()))
  const parkAfter = new Date(date.getTime() + day + 12 * 3_600_000)
  return { date, parkAfter }
}

/// Chrome, so it speaks the app language the install reported (`push-send`
/// picks by `device_tokens.app_language`). Title by rule: someone with
/// nothing to spend is told a plan keeps it; someone with free minutes left
/// is told opening the app does — the rule is 7 days without an open
/// (`20261001150000_park_by_last_open`). Returns how many devices were sent to.
async function announce(r: Candidate, date: Date, secret: string): Promise<number> {
  const locales: Record<string, string> = {
    en: "en-US", ko: "ko-KR", ja: "ja-JP", de: "de-DE", es: "es-ES",
    fr: "fr-FR", "zh-Hant": "zh-TW", "zh-Hans": "zh-CN",
  }
  const fmt = (lang: string) => new Intl.DateTimeFormat(locales[lang],
    { month: "long", day: "numeric", timeZone: "UTC" }).format(date)
  const spent = r.rule === "spent"
  const copy: Record<string, { spent: string; idle: string; body: (d: string) => string }> = {
    en: { spent: "Subscribe to keep your voice", idle: "Open the app once to keep your voice",
          body: (d) => `For your safety, a voice that isn't in use is deleted automatically after ${d}. You can make it again anytime.` },
    ko: { spent: "구독하면 내 목소리를 계속 쓸 수 있어요", idle: "앱을 한 번 열면 내 목소리가 그대로 남아요",
          body: (d) => `쓰지 않는 목소리는 안전을 위해 ${d} 이후 자동으로 삭제돼요. 언제든 다시 만들 수 있어요.` },
    ja: { spent: "登録すると、自分の声をそのまま使えます", idle: "アプリを一度開けば、自分の声はそのまま残ります",
          body: (d) => `使われていない声は、安全のため${d}以降に自動で削除されます。いつでも作り直せます。` },
    de: { spent: "Mit einem Abo behältst du deine Stimme", idle: "Öffne die App einmal, und deine Stimme bleibt",
          body: (d) => `Zu deiner Sicherheit wird eine ungenutzte Stimme nach dem ${d} automatisch gelöscht. Du kannst sie jederzeit neu erstellen.` },
    es: { spent: "Suscríbete y conserva tu voz", idle: "Abre la app una vez y tu voz se queda",
          body: (d) => `Por tu seguridad, una voz que no se usa se elimina automáticamente después del ${d}. Puedes volver a crearla cuando quieras.` },
    fr: { spent: "Abonne-toi pour garder ta voix", idle: "Ouvre l’app une fois, et ta voix reste",
          body: (d) => `Pour ta sécurité, une voix inutilisée est supprimée automatiquement après le ${d}. Tu peux la recréer à tout moment.` },
    "zh-Hant": { spent: "訂閱就能繼續使用你的聲音", idle: "打開 App 一次，你的聲音就會保留",
          body: (d) => `為了安全，未使用的聲音會在${d}之後自動刪除。你隨時都能重新製作。` },
    "zh-Hans": { spent: "订阅就能继续使用你的声音", idle: "打开 App 一次，你的声音就会保留",
          body: (d) => `为了安全，未使用的声音会在${d}之后自动删除。你随时都能重新制作。` },
  }
  const texts: Record<string, { title: string; body: string }> = {}
  for (const [lang, c] of Object.entries(copy)) {
    texts[lang] = { title: spent ? c.spent : c.idle, body: c.body(fmt(lang)) }
  }
  try {
    const res = await fetch(`${Deno.env.get("SUPABASE_URL")}/functions/v1/push-send`, {
      method: "POST",
      headers: { "Content-Type": "application/json", "X-Push-Secret": secret },
      body: JSON.stringify({
        kind: "voice_parking",
        dedupe_key: `park:${r.idle_since}`,
        user_ids: [r.user_id],
        texts,
        url: "futurevoice://talk",
      }),
    })
    if (!res.ok) {
      console.error("park-idle-voices: push failed", r.user_id, res.status, (await res.text()).slice(0, 200))
      return 0
    }
    return ((await res.json()) as { sent?: number }).sent ?? 0
  } catch (e) {
    console.error("park-idle-voices: push threw", r.user_id, String(e))
    return 0
  }
}
