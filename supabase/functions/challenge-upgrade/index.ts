// A challenger moves up a size (Light → Plus or Max) by paying the difference.
//
// Called by the admin desk only (nawana-admin → here with the service-role
// key): it answers what the difference is, and when asked makes the Stripe
// checkout the founder sends to the challenger. stripe-webhook finishes it: a
// paid session with metadata.kind = "challenge_upgrade" changes the package.
//
// The rule (program/RULES.md): months of the challenge still to come, times
// the difference between the two sizes' monthly web prices, in the currency of
// where the challenger lives. Before the cohort starts that is all three
// months; a month that has begun is not counted.
//
// Deploy:  supabase functions deploy challenge-upgrade

import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import Stripe from "npm:stripe@17"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0"

// Monthly web prices [Light, Plus, Max] per currency: the App Store's price in
// that country minus the web's 10% (App Store Connect, 2026-11-12); krw, usd
// and eur are the prices the site sells. Light × 3 is what the package cost.
const MONTHLY: Record<string, [number, number, number]> = {
  aed: [35.99, 71.99, 116.99],
  aud: [13.49, 26.99, 53.99],
  brl: [53.91, 116.91, 206.91],
  cad: [11.69, 22.49, 44.99],
  chf: [8, 16, 27],
  clp: [8991, 20691, 35991],
  cny: [61, 133, 205],
  cop: [44910, 89910, 134910],
  czk: [224, 449, 899],
  dkk: [80, 161, 269],
  egp: [449.99, 899.99, 1799.99],
  eur: [8.99, 20.69, 35.99],
  gbp: [8.99, 17.99, 31.49],
  hkd: [79, 133, 259],
  huf: [4041, 8091, 13491],
  idr: [152100, 314100, 629100],
  ils: [31.41, 62.91, 89.91],
  inr: [899, 1799, 3149],
  jpy: [1350, 2700, 5400],
  krw: [13500, 26000, 40500],
  kzt: [5391, 10791, 17991],
  mxn: [179, 359, 719],
  myr: [44.91, 89.91, 134.91],
  ngn: [13410, 26910, 53910],
  nok: [116, 224, 404],
  nzd: [17.99, 35.99, 53.99],
  pen: [40.41, 80.91, 134.91],
  php: [539, 1161, 2061],
  pkr: [2610, 4410, 8910],
  pln: [44.99, 89.99, 134.99],
  qar: [35.99, 62.99, 116.99],
  ron: [44.99, 89.99, 179.99],
  sar: [35.99, 80.99, 134.99],
  sek: [116, 224, 449],
  sgd: [13.48, 26.98, 44.98],
  thb: [359, 629, 1161],
  try: [449.99, 899.99, 1799.99],
  twd: [288, 621, 1071],
  tzs: [26910, 53910, 89910],
  usd: [8.99, 22.49, 31.49],
  vnd: [269100, 539100, 899100],
  zar: [179.99, 359.99, 629.99],
}
const COUNTRY_CURRENCY: Record<string, string> = { AE: "aed", AU: "aud", BR: "brl", CA: "cad", CH: "chf", CL: "clp", CN: "cny", CO: "cop", CZ: "czk", DK: "dkk", EG: "egp", GB: "gbp", HK: "hkd", HU: "huf", ID: "idr", IL: "ils", IN: "inr", JP: "jpy", KZ: "kzt", MX: "mxn", MY: "myr", NG: "ngn", NO: "nok", NZ: "nzd", PE: "pen", PH: "php", PK: "pkr", PL: "pln", QA: "qar", RO: "ron", SA: "sar", SE: "sek", SG: "sgd", TH: "thb", TR: "try", TW: "twd", TZ: "tzs", VN: "vnd", ZA: "zar" }
const EUROZONE = new Set(["AT","BE","BG","CY","DE","EE","ES","FI","FR","GR","HR","IE","IT","LT","LU","LV","MT","NL","PT","SI","SK","AD","MC","SM","VA","ME","XK"])
const ZERO_DECIMAL = new Set(["krw", "jpy", "clp", "vnd"])
const TIER = ["light_challenge", "plus_challenge", "max_challenge"]
const SIZE = ["Light", "Plus", "Max"]

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } })

function currencyOf(country: string | null): string {
  if (!country || country === "KR") return "krw"
  if (EUROZONE.has(country)) return "eur"
  return COUNTRY_CURRENCY[country] ?? "usd"
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method" }, 405)
  // The gateway has verified the token's signature; this door is for the service role only.
  try {
    const claims = JSON.parse(atob((req.headers.get("Authorization") ?? "").split(".")[1] ?? ""))
    if (claims.role !== "service_role") return json({ error: "forbidden" }, 403)
  } catch { return json({ error: "forbidden" }, 403) }

  const body = await req.json().catch(() => ({})) as { application_id?: string; target?: string; make?: boolean }
  const to = TIER.indexOf(String(body.target ?? ""))
  if (to < 1) return json({ error: "bad_target" }, 400)

  const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } })
  const { data: app } = await db.from("creator_applications")
    .select("id, name, kind, user_id, country, paid_plan").eq("id", String(body.application_id ?? "")).maybeSingle()
  if (!app || app.kind !== "challenger" || !app.user_id) return json({ error: "not_paid" }, 409)

  const { data: sub } = await db.from("user_subscriptions")
    .select("plan_id, source, stripe_subscription_id, status").eq("user_id", app.user_id).maybeSingle()
  const from = TIER.indexOf(sub?.plan_id ?? "")
  if (!sub || sub.source !== "stripe" || sub.stripe_subscription_id || from < 0 || sub.status !== "active") return json({ error: "no_package" }, 409)
  if (to <= from) return json({ error: "not_an_upgrade" }, 409)

  // Months still to come: all three before the first day, then one fewer for each month that has begun.
  const { data: cfg } = await db.from("billing_config").select("challenge_starts_at").maybeSingle()
  const start = new Date(cfg?.challenge_starts_at ?? "")
  const begun = isNaN(start.getTime()) || Date.now() < start.getTime() ? 0 : Math.floor((Date.now() - start.getTime()) / (30 * 86_400_000)) + 1
  const months = 3 - begun
  if (months < 1) return json({ error: "too_late" }, 409)

  const currency = currencyOf(app.country)
  const prices = MONTHLY[currency] ?? MONTHLY.usd
  const cur = MONTHLY[currency] ? currency : "usd"
  const amount = Math.round((prices[to] - prices[from]) * months * 100) / 100
  const unit = ZERO_DECIMAL.has(cur) ? Math.round(amount) : Math.round(amount * 100)
  let label = `${cur.toUpperCase()} ${amount}`
  try { label = new Intl.NumberFormat("en-US", { style: "currency", currency: cur.toUpperCase(), minimumFractionDigits: Number.isInteger(amount) ? 0 : 2, maximumFractionDigits: 2 }).format(amount) } catch { /* the code and the number */ }
  const quote = { from: SIZE[from], to: SIZE[to], months, currency: cur, amount, label }
  if (!body.make) return json({ ok: true, quote })

  const stripeKey = Deno.env.get("STRIPE_SECRET_KEY")
  if (!stripeKey) return json({ error: "server missing STRIPE_SECRET_KEY" }, 500)
  const stripe = new Stripe(stripeKey, { httpClient: Stripe.createFetchHttpClient() })
  const site = Deno.env.get("SITE_URL") ?? "https://nawana.app"
  // An applicant from the English page (/en/creators) gets the checkout's words and pages in English.
  // Read on its own: a database without the column (before 20261112220000) costs
  // the English wording, never the upgrade itself.
  const { data: langRow } = await db.from("creator_applications").select("page_lang").eq("id", app.id).maybeSingle()
  const en = langRow?.page_lang === "en"
  const meta = { project: "futurevoice", kind: "challenge_upgrade", user_id: app.user_id, application_id: app.id, plan_id: TIER[to], from_plan: TIER[from] }
  try {
    const session = await stripe.checkout.sessions.create({
      mode: "payment",
      line_items: [{
        quantity: 1,
        price_data: {
          currency: cur, unit_amount: unit, tax_behavior: "inclusive",
          product_data: { name: en
            ? `nawana 100-day challenge · ${SIZE[from]} to ${SIZE[to]} (${months} ${months === 1 ? "month" : "months"})`
            : `nawana 100일 챌린지 · ${SIZE[from]}에서 ${SIZE[to]}로 (${months}개월)` },
        },
      }],
      success_url: `${site}/pay?checkout=upgraded${en ? "&lang=en" : ""}`,
      cancel_url: `${site}${en ? "/en/creators" : "/creators"}`,
      client_reference_id: app.user_id,
      metadata: meta,
      payment_intent_data: { metadata: meta },
      // The founder sends this link by hand, so it lives as long as Stripe allows.
      expires_at: Math.floor(Date.now() / 1000) + 23 * 3600,
      // deno-lint-ignore no-explicit-any
      ...({ branding_settings: { display_name: "nawana" } } as any),
    })
    return json({ ok: true, quote, url: session.url, expires_at: new Date((session.expires_at ?? 0) * 1000).toISOString() })
  } catch (e) {
    console.error("challenge-upgrade: stripe", e)
    return json({ error: "stripe", detail: e instanceof Error ? e.message.slice(0, 200) : "" }, 502)
  }
})
