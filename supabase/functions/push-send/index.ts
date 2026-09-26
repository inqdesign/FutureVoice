// Send a push notification to learners — the only thing here that holds the
// APNs key (2026-09-26).
//
// Not user-callable. There is no JWT to check (`verify_jwt = false`); the
// caller proves itself with PUSH_SECRET in X-Push-Secret, the same shape
// `cleanup-anonymous-voices` uses. Without that env var the function refuses
// every request — a thing that writes to every learner's lock screen fails
// closed, never open.
//
// Body:
//   {
//     kind: "core_arrival" | "billing" | "broadcast" | …,   // for the ledger
//     dedupe_key: "…",            // same (user, kind, dedupe_key) is sent once
//     user_ids?: string[],        // omit for everyone with a token
//     texts: { en: { title, body }, ko: { … }, … },   // picked by app_language
//     url?: "futurevoice://…",    // where a tap should land
//     collapse_id?: string
//   }
//
// The TEXTS are a map, not a string, because chrome follows the language the
// learner picked in the app and a push is chrome (see "UI text has ONE
// language" in CLAUDE.md). Each token row carries that choice; the sender
// picks by it and falls back to `en`. A caller with one language in the map
// is saying "send this to everyone in these words", which is what a founder
// writing an announcement by hand actually means.
//
// APNs facts baked in:
//   * One JWT signs every send and is good for an hour — Apple rate-limits
//     token minting hard, so it is cached in module scope and re-signed only
//     when it ages out.
//   * The HOST is decided per token, never globally: a development build
//     exists only on the sandbox host and a shipped build only on the
//     production one. Sending to the wrong one is a hard error, so the
//     install states its own environment (`device_tokens.environment`).
//   * `apns-topic` is the BUNDLE ID, which differs between the dev build and
//     the shipped app — also per token.
//   * 410 Unregistered and 400 BadDeviceToken mean the install is gone: the
//     row is deleted, which is the only way tokens are ever reaped.

import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0"
import { timingSafeEqual } from "../_shared/auth.ts"

const TEAM_ID = Deno.env.get("APNS_TEAM_ID") ?? ""
const KEY_ID = Deno.env.get("APNS_KEY_ID") ?? ""
const PRIVATE_KEY = Deno.env.get("APNS_PRIVATE_KEY") ?? ""

interface Text { title: string; body: string }
interface Row {
  token: string
  user_id: string
  bundle_id: string
  environment: string
  app_language: string | null
}

// ---------------------------------------------------------------------------
// The provider token

let cached: { jwt: string; madeAt: number } | null = null

function b64url(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes))
    .replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "")
}

/**
 * The .p8 is a PKCS#8 PEM; Web Crypto wants its DER body.
 *
 * The `\n` unescaping is not cosmetic: a PEM is multi-line and an env var is
 * one line, so the key is stored with its newlines escaped. Left in, the
 * two characters survive the whitespace strip — `n` is a base64 letter — and
 * the DER decodes into something that imports as a key and signs a token
 * Apple rejects with no explanation.
 */
function derFromPem(pem: string): Uint8Array {
  const body = pem
    .replace(/\\n/g, "\n")
    .replace(/-----[A-Z ]+-----/g, "")
    .replace(/\s+/g, "")
  return Uint8Array.from(atob(body), (c) => c.charCodeAt(0))
}

async function providerToken(): Promise<string> {
  // Apple invalidates a token refreshed more than once every 20 minutes and
  // rejects one older than an hour. 50 minutes sits between both walls.
  const now = Math.floor(Date.now() / 1000)
  if (cached && now - cached.madeAt < 50 * 60) return cached.jwt

  const key = await crypto.subtle.importKey(
    "pkcs8", derFromPem(PRIVATE_KEY),
    { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"])
  const header = b64url(new TextEncoder().encode(
    JSON.stringify({ alg: "ES256", kid: KEY_ID })))
  const claims = b64url(new TextEncoder().encode(
    JSON.stringify({ iss: TEAM_ID, iat: now })))
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" }, key,
    new TextEncoder().encode(`${header}.${claims}`))
  const jwt = `${header}.${claims}.${b64url(new Uint8Array(signature))}`
  cached = { jwt, madeAt: now }
  return jwt
}

// ---------------------------------------------------------------------------

function textFor(texts: Record<string, Text>, language: string | null): Text | null {
  if (!language) return texts.en ?? null
  // "zh-Hant" before "zh": a script-qualified choice is a different language
  // here, not a dialect of one (LanguageCatalog, CLAUDE.md).
  return texts[language] ?? texts[language.split("-")[0]] ?? texts.en ?? null
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("method not allowed", { status: 405 })

  const secret = Deno.env.get("PUSH_SECRET")
  if (!secret || !timingSafeEqual(req.headers.get("X-Push-Secret") ?? "", secret)) {
    return new Response("forbidden", { status: 403 })
  }
  if (!TEAM_ID || !KEY_ID || !PRIVATE_KEY) {
    return new Response("apns key not configured", { status: 503 })
  }

  let payload: {
    kind?: string; dedupe_key?: string; user_ids?: string[]
    texts?: Record<string, Text>; url?: string; collapse_id?: string
  }
  try { payload = await req.json() } catch { return new Response("bad json", { status: 400 }) }

  const kind = (payload.kind ?? "").trim()
  const dedupeKey = (payload.dedupe_key ?? "").trim()
  const texts = payload.texts ?? {}
  if (!kind || !dedupeKey || Object.keys(texts).length === 0) {
    return new Response("kind, dedupe_key and texts are required", { status: 400 })
  }

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false } })

  let query = admin.from("device_tokens")
    .select("token,user_id,bundle_id,environment,app_language")
  if (payload.user_ids?.length) query = query.in("user_id", payload.user_ids)
  const { data: rows, error } = await query.returns<Row[]>()
  if (error) return new Response(`tokens: ${error.message}`, { status: 500 })

  const jwt = await providerToken()
  let sent = 0, skipped = 0, reaped = 0
  const failures: Record<string, number> = {}

  for (const row of rows ?? []) {
    const text = textFor(texts, row.app_language)
    if (!text) { skipped++; continue }

    // The ledger is the gate, and it is claimed BEFORE the send: a row that
    // exists means "already said". A send that then fails is not retried by
    // this function — a notification nobody can see twice is worth more than
    // one that might arrive twice.
    const claim = await admin.from("push_sends")
      .insert({ user_id: row.user_id, kind, dedupe_key: dedupeKey })
    if (claim.error) { skipped++; continue }   // unique violation = already told

    const host = row.environment === "sandbox"
      ? "api.sandbox.push.apple.com" : "api.push.apple.com"
    const headers: Record<string, string> = {
      authorization: `bearer ${jwt}`,
      "apns-topic": row.bundle_id,
      "apns-push-type": "alert",
      "apns-priority": "10",
      "content-type": "application/json",
    }
    if (payload.collapse_id) headers["apns-collapse-id"] = payload.collapse_id

    const res = await fetch(`https://${host}/3/device/${row.token}`, {
      method: "POST",
      headers,
      body: JSON.stringify({
        aps: { alert: { title: text.title, body: text.body }, sound: "default" },
        url: payload.url ?? null,
      }),
    })

    if (res.ok) { sent++; continue }
    const reason = (await res.text().catch(() => "")).slice(0, 200)
    failures[`${res.status}`] = (failures[`${res.status}`] ?? 0) + 1
    // The install is gone. This is the ONLY thing that removes a token.
    if (res.status === 410 || reason.includes("BadDeviceToken")) {
      await admin.from("device_tokens").delete().eq("token", row.token)
      reaped++
    }
    // The claim stays. A token Apple refused is not owed a second attempt on
    // the next cron tick; the sender would loop on the same dead rows forever.
  }

  return Response.json({ sent, skipped, reaped, failures })
})
