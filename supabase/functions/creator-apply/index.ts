// A creator-program application, from nawana.app/creators.
//
// The page has only the anon key, which passes verify_jwt and proves nothing.
// creator_apply() does the validating and is granted to the service role
// alone. This function is the door in front of it, and the one place that can
// tell the founder someone applied.
//
// The Telegram line is composed from the form's fixed choices. Nothing the
// applicant typed reaches it, the same rule as owner-watch.
//
// Deploy:  supabase functions deploy creator-apply

import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0"
import { notifyOwner } from "../_shared/credits.ts"
import { sendReceived } from "./mail.ts"

const ALLOWED_ORIGINS = new Set(["https://nawana.app", "https://www.nawana.app"])

const LANGUAGE: Record<string, string> = {
  en: "영어", de: "독일어", ja: "일본어", es: "스페인어", fr: "프랑스어", zh: "중국어", ko: "한국어",
}
const CADENCE: Record<string, string> = {
  daily: "매일", weekdays: "평일마다", three: "주 3번", custom: "직접 정함",
}
const STAGE: Record<string, string> = {
  not_started: "시작 전", small: "팔로워 적음", running: "운영 중",
}

function cors(req: Request): Record<string, string> {
  const origin = req.headers.get("Origin") ?? ""
  // Local previews of the page may post too; only the anon key is involved.
  const allowed = ALLOWED_ORIGINS.has(origin) || /^http:\/\/localhost(:\d+)?$/.test(origin)
  return {
    "Access-Control-Allow-Origin": allowed ? origin : "https://nawana.app",
    "Access-Control-Allow-Headers": "authorization, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Vary": "Origin",
  }
}

function reply(req: Request, body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...cors(req) },
  })
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: cors(req) })
  if (req.method !== "POST") return reply(req, { error: "method" }, 405)

  const body = await req.json().catch(() => null) as Record<string, unknown> | null
  if (!body || typeof body !== "object") return reply(req, { error: "bad_payload" }, 400)

  // The hidden field only a script fills in. It is told it succeeded.
  if (typeof body.website === "string" && body.website.trim() !== "") {
    return reply(req, { ok: true })
  }

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false } },
  )
  // A guestbook line from the foot of the page. The alert says only that one
  // came: the line itself is read (and hidden if need be) in the admin.
  // A guestbook line changed by its writer: the database checks the line was
  // written by this browser. No alert; the admin shows the current text.
  if (body.kind === "note_edit") {
    const { error } = await admin.rpc("creator_note_edit", {
      p_id: String(body.id ?? ""), p_client: String(body.client ?? ""),
      p_body: String(body.body ?? ""),
      p_name: String(body.name ?? "").slice(0, 40) || null,
      p_color: typeof body.color === "string" ? body.color.slice(0, 12) : null,
    })
    if (error) {
      const known = ["bad_note", "bad_client", "bad_word", "not_yours", "busy"].find((c) => error.message.includes(c))
      if (!known) console.error("creator_note_edit failed", error.message)
      return reply(req, { error: known ?? "invalid" }, known === "busy" ? 429 : known === "not_yours" ? 403 : 400)
    }
    return reply(req, { ok: true })
  }
  if (body.kind === "note") {
    const day = Number(body.day)
    const { data, error } = await admin.rpc("creator_note_add", {
      p_body: String(body.body ?? ""), p_client: String(body.client ?? ""),
      p_day: Number.isInteger(day) && day >= 1 && day <= 100000 ? day : null,
      p_name: String(body.name ?? "").slice(0, 40) || null,
      // The band colour; the database keeps only the six it knows.
      p_color: typeof body.color === "string" ? body.color.slice(0, 12) : null,
    })
    if (error) {
      const known = ["bad_note", "bad_client", "bad_word", "taken", "too_many", "busy"].find((c) => error.message.includes(c))
      if (!known) console.error("creator_note_add failed", error.message)
      return reply(req, { error: known ?? "invalid" }, known === "busy" || known === "too_many" ? 429 : 400)
    }
    await notifyOwner("크리에이터 페이지 방명록에 새 글이 왔어요\nhttps://nawana.app/admin/creators")
    // The id goes back to the writer's browser, which keeps it so the line can be changed later.
    return reply(req, { ok: true, id: (data as { id?: string } | null)?.id ?? null })
  }

  // Cohort 1 takes applications through 19 November, Seoul time (the page's
  // APPLY_UNTIL). The guestbook above stays open.
  // Local time, not strict (founder, 2026-11-12): open until 19 November has ended in the last time zone.
  if (Date.now() >= Date.parse("2026-11-20T00:00:00-12:00")) return reply(req, { error: "closed" }, 410)

  // The page asks for an email; so does this door. It is where the "we have it" mail goes.
  const email = String(body.email ?? "").trim().toLowerCase()
  if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email) || email.length > 254) return reply(req, { error: "bad_email" }, 400)

  const { data, error } = await admin.rpc("creator_apply", { p: body })
  if (error) {
    const known = ["bad_payload", "bad_contact", "bad_email", "no_consent", "busy"]
      .find((c) => error.message.includes(c))
    if (!known) console.error("creator_apply failed", error.message)
    return reply(req, { error: known ?? "invalid" }, known === "busy" ? 429 : 400)
  }

  const result = data as { ok: boolean; new: boolean; waiting: number }
  // Which page the form came from (/en/creators sends "en"). The database keeps
  // the same answer; it decides the language of the mail below.
  const pageLang: "en" | "ko" = body.page_lang === "en" ? "en" : "ko"
  if (result.new) {
    const level = /^(a1|a2|b1|b2|c1|c2)$/.test(String(body.level)) ? " " + String(body.level).toUpperCase() : ""
    const language = (LANGUAGE[String(body.language)] ?? "?") + level
    const cadence = CADENCE[String(body.cadence)] ?? "?"
    const stage = STAGE[String(body.stage)] ?? "?"
    const PLAN: Record<string, string> = { light: "Light", plus: "Plus", max: "Max" }
    const en = pageLang === "en" ? " · EN" : ""
    await notifyOwner(
      (body.kind === "challenger"
        ? `챌린저 신청이 들어왔어요 · ${language} · ${PLAN[String(body.plan)] ?? "?"}${en}\n`
        : `크리에이터 지원이 들어왔어요 · ${language} · ${cadence} · ${stage}${en}\n`) +
      `읽을 지원서 ${result.waiting}건\nhttps://nawana.app/admin/creators`,
    )
  }
  // A challenger pays right after applying. The page carries this id into the
  // checkout so the payment lands on this application; it goes only to the
  // browser that just sent the form, and into the mail to the address given.
  let challengerId: string | null = null
  if (body.kind === "challenger") {
    const { data: row } = await admin.from("creator_applications")
      .select("id").eq("email", email).eq("kind", "challenger").maybeSingle()
    challengerId = row?.id ?? null
  }
  // The "we have it" mail: once, for a new application. A second send of the
  // same form brings no second mail. A challenger's carries the way back to the checkout.
  if (result.new) {
    await sendReceived(email, String(body.name ?? ""), body.kind === "challenger" ? "challenger" : "creator", challengerId, String(body.country ?? ""), pageLang)
  }
  if (body.kind === "challenger") return reply(req, { ok: true, id: challengerId })
  return reply(req, { ok: true })
})
