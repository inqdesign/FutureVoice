// Waitlist confirmation email.
//
// Fired by a Supabase Database Webhook on INSERT into public.waitlist. Sends a
// confirmation email FROM hello.dearroroapp@gmail.com via Gmail SMTP (an app
// password — the account genuinely owns the address, so no domain/DNS setup).
//
// Env (set as function secrets):
//   GMAIL_USER              hello.dearroroapp@gmail.com
//   GMAIL_APP_PASSWORD      a Gmail App Password (needs 2-Step Verification on)
//   WAITLIST_WEBHOOK_SECRET a random string; the DB webhook must send it as the
//                           x-webhook-secret header so only Supabase can trigger sends
//
// Deploy:  supabase functions deploy waitlist-confirm --no-verify-jwt

import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { SMTPClient } from "https://deno.land/x/denomailer@1.6.0/mod.ts"
import { timingSafeEqual } from "../_shared/auth.ts"

const GMAIL_USER = Deno.env.get("GMAIL_USER") ?? ""
const GMAIL_APP_PASSWORD = Deno.env.get("GMAIL_APP_PASSWORD") ?? ""
const WEBHOOK_SECRET = Deno.env.get("WAITLIST_WEBHOOK_SECRET") ?? ""

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/

function textBody(beta: boolean): string {
  return [
    "Thanks for joining nawana — learn a language with your own fluent voice.",
    "",
    beta
      ? "You asked to help test the beta. We'll send your TestFlight invite before launch."
      : "We'll email you the moment nawana launches.",
    "",
    "— nawana",
    "https://nawana.app",
  ].join("\n")
}

function htmlBody(beta: boolean): string {
  const line = beta
    ? "You asked to help test the beta. We&rsquo;ll send your TestFlight invite <strong>before launch</strong>."
    : "We&rsquo;ll email you <strong>the moment nawana launches</strong>."
  return `<!doctype html><html><body style="margin:0;background:#f4f3ef;">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f4f3ef;padding:40px 16px;">
    <tr><td align="center">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:460px;background:#ffffff;border:1px solid #e6e4dd;">
        <tr><td style="padding:36px 34px;font-family:Helvetica,Arial,sans-serif;color:#1c1814;">
          <div style="font-size:22px;font-weight:700;letter-spacing:-.01em;">nawana</div>
          <div style="font-size:11px;letter-spacing:.16em;text-transform:uppercase;color:#8a7c6d;margin-top:6px;">In beta testing</div>
          <p style="font-size:15.5px;line-height:1.6;color:#3a332e;margin:26px 0 0;">Thanks for joining — learn a language with your own fluent voice.</p>
          <p style="font-size:15.5px;line-height:1.6;color:#3a332e;margin:14px 0 0;">${line}</p>
          <p style="font-size:13px;line-height:1.6;color:#8a7c6d;margin:30px 0 0;">Wrong address or changed your mind? Just reply to this email.</p>
          <div style="margin-top:30px;padding-top:20px;border-top:1px solid #ececE6;">
            <a href="https://nawana.app" style="font-size:13px;color:#1c1814;text-decoration:none;">nawana.app &rarr;</a>
          </div>
        </td></tr>
      </table>
      <div style="font-family:Helvetica,Arial,sans-serif;font-size:11px;color:#a89f92;margin-top:16px;">Dear RoRo &middot; Munich</div>
    </td></tr>
  </table></body></html>`
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("method not allowed", { status: 405 })
  if (!GMAIL_USER || !GMAIL_APP_PASSWORD || !WEBHOOK_SECRET)
    return new Response("not configured", { status: 500 })
  if (!timingSafeEqual(req.headers.get("x-webhook-secret") ?? "", WEBHOOK_SECRET))
    return new Response("forbidden", { status: 403 })

  const payload = await req.json().catch(() => null)
  // Supabase DB webhook shape: { type, table, record: {...} }
  const rec = payload?.record ?? payload ?? {}
  const email = String(rec.email ?? "").trim()
  const wantsBeta = rec.wants_beta === true
  if (!EMAIL_RE.test(email)) return new Response("bad email", { status: 400 })

  const client = new SMTPClient({
    connection: {
      hostname: "smtp.gmail.com",
      port: 465,
      tls: true,
      auth: { username: GMAIL_USER, password: GMAIL_APP_PASSWORD },
    },
  })
  try {
    await client.send({
      from: `nawana <${GMAIL_USER}>`,
      to: email,
      replyTo: GMAIL_USER,
      subject: wantsBeta ? "You're on the nawana beta list" : "You're on the nawana list",
      content: textBody(wantsBeta),
      html: htmlBody(wantsBeta),
    })
    await client.close()
  } catch (e) {
    return new Response("send failed: " + (e as Error).message, { status: 500 })
  }
  return new Response(JSON.stringify({ ok: true }), {
    headers: { "Content-Type": "application/json" },
  })
})
