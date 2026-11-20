// The friend-invite month on Stripe, run for real in TEST mode.
//
//   STRIPE_TEST_KEY=sk_test_... \
//     /opt/homebrew/opt/node@22/bin/node --experimental-strip-types scripts/invite-stripe-probe.mjs
//
// It calls the SAME function the server uses
// (supabase/functions/_shared/stripe-discount.ts) on subscriptions made on a
// Stripe test clock, moves the clock through two renewals and prints what
// each invoice charged. Three cases:
//   A  a plain subscription: half price once, then the regular price
//   B  a subscription that already has 10% off: both stay, then 10% alone
//   C  the same reward given twice: the coupon is there once
// Refuses anything but a test key. Everything it makes is deleted at the end.

import { addStripeCoupon, couponOf } from "../supabase/functions/_shared/stripe-discount.ts"

const key = process.env.STRIPE_TEST_KEY ?? ""
if (!/^(sk|rk)_test_/.test(key)) {
  console.error("STRIPE_TEST_KEY must be a TEST mode key (sk_test_...). Nothing was run.")
  process.exit(1)
}

async function stripe(method, path, data) {
  const res = await fetch("https://api.stripe.com/v1" + path, {
    method,
    headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/x-www-form-urlencoded" },
    body: data ? new URLSearchParams(data) : undefined,
  })
  const json = await res.json()
  if (!res.ok) throw new Error(`${method} ${path}: ${res.status} ${JSON.stringify(json.error ?? json)}`)
  return json
}

const DAY = 86400
const stamp = Date.now().toString(36)
const money = (cents, currency) => `${(cents / 100).toFixed(2)} ${currency.toUpperCase()}`
let failures = 0
function check(label, got, want) {
  const ok = got === want
  if (!ok) failures++
  console.log(`   ${ok ? "ok  " : "FAIL"} ${label}: ${got}${ok ? "" : ` (expected ${want})`}`)
}

async function advance(clock, to) {
  await stripe("POST", `/test_helpers/test_clocks/${clock}/advance`, { frozen_time: String(to) })
  for (let i = 0; i < 60; i++) {
    const c = await stripe("GET", `/test_helpers/test_clocks/${clock}`)
    if (c.status === "ready") return
    await new Promise((r) => setTimeout(r, 2000))
  }
  throw new Error("test clock never became ready")
}

async function invoices(subscription) {
  const list = await stripe("GET", `/invoices?subscription=${subscription}&limit=10`)
  return list.data.sort((a, b) => a.created - b.created)
}

async function subscriber(clock, price, extra = {}) {
  const customer = await stripe("POST", "/customers", {
    name: "invite probe", test_clock: clock,
    payment_method: "pm_card_visa", "invoice_settings[default_payment_method]": "pm_card_visa",
  })
  return stripe("POST", "/subscriptions", { customer: customer.id, "items[0][price]": price, ...extra })
}

const made = { coupons: [], clocks: [], product: null }
try {
  const start = Math.floor(Date.now() / 1000)
  const product = await stripe("POST", "/products", { name: `invite probe ${stamp}` })
  made.product = product.id
  const price = await stripe("POST", "/prices", {
    product: product.id, unit_amount: "999", currency: "eur", "recurring[interval]": "month",
  })
  const half = `probe_friend_50_${stamp}`
  const ten = `probe_web_10_${stamp}`
  await stripe("POST", "/coupons", { id: half, percent_off: "50", duration: "once" })
  await stripe("POST", "/coupons", { id: ten, percent_off: "10", duration: "forever" })
  made.coupons.push(half, ten)

  // ── A: a plain subscription ──────────────────────────────────────────
  console.log("A  plain subscription, 9.99 EUR a month")
  let clock = (await stripe("POST", "/test_helpers/test_clocks", { frozen_time: String(start) })).id
  made.clocks.push(clock)
  let sub = await subscriber(clock, price.id)
  check("coupon added", await addStripeCoupon(key, sub.id, half), null)
  await advance(clock, start + 32 * DAY)
  await advance(clock, start + 63 * DAY)
  let bills = await invoices(sub.id)
  check("first payment", money(bills[0].amount_paid, bills[0].currency), "9.99 EUR")
  check("next month (half)", money(bills[1].amount_paid, bills[1].currency), "4.99 EUR")
  check("month after", money(bills[2].amount_paid, bills[2].currency), "9.99 EUR")

  // ── B: a subscription that already has 10% off ───────────────────────
  console.log("B  subscription already carrying 10% off")
  clock = (await stripe("POST", "/test_helpers/test_clocks", { frozen_time: String(start) })).id
  made.clocks.push(clock)
  sub = await subscriber(clock, price.id, { "discounts[0][coupon]": ten })
  check("coupon added", await addStripeCoupon(key, sub.id, half), null)
  let now = await stripe("GET", `/subscriptions/${sub.id}?expand[]=discounts`)
  check("discounts on the subscription", now.discounts.map((d) => couponOf(d)).sort().join(" + "),
    [half, ten].sort().join(" + "))

  // ── C: the same reward given twice ───────────────────────────────────
  check("given again", await addStripeCoupon(key, sub.id, half), null)
  now = await stripe("GET", `/subscriptions/${sub.id}?expand[]=discounts`)
  check("half-price coupons on it", now.discounts.filter((d) => couponOf(d) === half).length, 1)

  await advance(clock, start + 32 * DAY)
  await advance(clock, start + 63 * DAY)
  bills = await invoices(sub.id)
  check("first payment (10% off)", money(bills[0].amount_paid, bills[0].currency), "8.99 EUR")
  console.log(`   info next month (10% and half): ${money(bills[1].amount_paid, bills[1].currency)}`)
  check("month after (10% off again)", money(bills[2].amount_paid, bills[2].currency), "8.99 EUR")
} catch (e) {
  failures++
  console.error("probe stopped:", e.message)
} finally {
  for (const c of made.clocks) await stripe("DELETE", `/test_helpers/test_clocks/${c}`).catch(() => {})
  for (const c of made.coupons) await stripe("DELETE", `/coupons/${c}`).catch(() => {})
  if (made.product) await stripe("POST", `/products/${made.product}`, { active: "false" }).catch(() => {})
}
console.log(failures ? `\n${failures} check(s) failed` : "\nall checks passed")
process.exit(failures ? 1 : 0)
