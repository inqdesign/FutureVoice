// A coupon added ON TOP of whatever a Stripe subscription already carries
// (2026-11-20, the friend-invite month).
//
// Stripe's `discounts` replaces the whole list, so sending a bare coupon
// wipes a discount the subscriber already has (the web 10%, a challenge
// package). The list is read first and sent back with the coupon added. A
// subscription that already carries this coupon is left as it is, so a
// second call for the same reward changes nothing.
//
// Returns what went wrong, or null. Plain fetch only, nothing from Deno:
// `scripts/invite-stripe-probe.mjs` runs this same file against Stripe's
// test mode.

// Stripe names a discount's coupon in two places depending on the account's
// API version: `coupon.id` (older) or `source.coupon`, an id or an object
// (2025-09 on). Both are read.
type Discount = { id: string; coupon?: { id?: string }; source?: { coupon?: string | { id?: string } } }

export function couponOf(d: Discount): string | undefined {
  const fromSource = d.source?.coupon
  return d.coupon?.id ?? (typeof fromSource === "string" ? fromSource : fromSource?.id)
}

export async function addStripeCoupon(key: string, subscriptionId: string, coupon: string): Promise<string | null> {
  const url = `https://api.stripe.com/v1/subscriptions/${subscriptionId}`
  const headers = { Authorization: `Bearer ${key}`, "Content-Type": "application/x-www-form-urlencoded" }
  const read = await fetch(`${url}?expand[]=discounts`, { headers })
  if (!read.ok) return `read ${read.status} ${await read.text()}`
  const current = await read.json()
  const kept: Discount[] = (current.discounts ?? []).filter((d: unknown) => d && typeof d === "object")
  if (kept.some((d) => couponOf(d) === coupon)) return null
  const body = new URLSearchParams()
  kept.forEach((d, i) => body.set(`discounts[${i}][discount]`, d.id))
  body.set(`discounts[${kept.length}][coupon]`, coupon)
  const res = await fetch(url, { method: "POST", headers, body })
  return res.ok ? null : `update ${res.status} ${await res.text()}`
}
