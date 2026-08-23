# Future Voice — marketing landing page

Static pages, no build step. Everything (CSS/JS) is inlined.

> **배포 상태 (2026-08-20): 루트는 아직 베타 모집 페이지다.** 새 풀 페이지는
> `.next.html`로 대기 중 — 공개 결정 전에는 `index.next.html`/`ko.next.html`을
> `index.html`/`ko.html` 위로 올리지 말 것.

- `index.html` — LIVE: the beta waitlist page (= `beta.html`, audio-play PostHog tracking added 2026-08-20)
- `ko.html` — LIVE parity: the July marketing page as deployed (unlinked, kept so no live URL changes)
- `index.next.html` — the NEW English marketing page, work in progress (launch swaps this to index.html)
- `ko.next.html` — the NEW Korean marketing page (the design lead — Korean is finalized first, then ported to en). App screens live in `shots/` (see shots/README.md for the slot map the user fills)
- `beta.html` — same as the live root, kept under its own name
- `waitlist.html` — an older minimal waitlist page, kept and `noindex`ed

## Replacing mockups with real captures

The phone frames are CSS mockups of the app. To swap in a real screenshot or
screen recording: add `<img class="shot" src="…">` or
`<video class="shot" src="…" autoplay muted loop playsinline>` as the FIRST
child of the `.screen` div and delete the mockup markup after it. The frame,
bezel, and Dynamic Island stay; the capture fills the screen
(1179×2556 or any 19.5:9 capture works — `object-fit: cover`).

## Preview

```bash
open web/index.html
```

## Deploy

Any static host works. Point the project root at `web/`:

- **Vercel**: `vercel --cwd web` (or set Root Directory to `web` in the dashboard, framework preset "Other").
- **Cloudflare Pages**: build command none, output directory `web`.

## Web billing (Stripe → Supabase → app)

**The pricing section is always visible** — it states the plans and sends people
to the App Store, which is the only place the app is sold at launch. What
`BILLING.enabled` gates is just the BUY BUTTON: flipping it hides the App Store
CTA (`[data-store-cta]`) and reveals the Stripe one (`.p-buy[data-tier]`). It
used to hide the whole section, so a page selling an iOS app showed no price at
all until a payment integration nobody needs at launch was configured.

Prices, tier names and pool figures live in `PLANS` in each page's inline module
script — keep them in step with `docs/launch-billing.md` and
`subscription_plans.monthly_seconds` / `monthly_scenes`. The Korean page prints
Apple's won price points and the English page EUR, because at launch Apple
charges in local currency; **when `BILLING.enabled` flips, Stripe charges EUR
everywhere and the won figures have to be revisited.**

Stripe flow:

```
site → Sign in with Apple (Supabase OAuth, same identity as the app)
     → stripe-checkout Edge Function → Stripe Checkout
Stripe → stripe-webhook Edge Function → user_subscriptions + grant_credits()
app   → reads the same tables — no app changes needed
```

Go-live checklist, in order:

1. **Migration** — apply `supabase/migrations/20260703120000_stripe_web_billing.sql`
   (adds `stripe_price_id` to plans, `source`/`stripe_*` to user_subscriptions).
2. **Stripe** — create Products/Prices for the plans you want to sell on web,
   then fill `subscription_plans.stripe_price_id` for each. Enable Stripe Tax.
3. **Secrets** — `supabase secrets set STRIPE_SECRET_KEY=sk_... STRIPE_WEBHOOK_SECRET=whsec_... SITE_URL=https://<domain>`
4. **Deploy functions** — `supabase functions deploy stripe-checkout` and
   `supabase functions deploy stripe-webhook --no-verify-jwt`.
5. **Stripe webhook endpoint** — `https://<project>.supabase.co/functions/v1/stripe-webhook`
   with events: `checkout.session.completed`, `invoice.paid`,
   `customer.subscription.updated`, `customer.subscription.deleted`.
6. **Apple web sign-in** — Supabase Dashboard → Auth → Providers → Apple: add a
   Services ID (same Apple team as the app, so the web login resolves to the
   SAME Supabase user as Sign in with Apple in the app) and add the site to
   Auth → URL Configuration → Redirect URLs.
7. **Page config** — in both pages fill `BILLING.supabaseUrl` /
   `supabaseAnonKey`, set `enabled: true`, and make `PLANS` quote the real
   Stripe prices (EUR) rather than the App Store price points.

Notes:
- Never link to this page's checkout from **inside** the iOS app (App Review).
- Credits are granted on `invoice.paid`, idempotent by invoice id — Stripe
  retries are safe.
- A Stripe **customer portal** (self-serve cancel/upgrade) is a sensible
  follow-up: add a `stripe-portal` function that creates a portal session.

## Before launch

- [x] `APP_STORE_URL` is filled in BOTH `.next` pages (`https://apps.apple.com/app/id6792794655` — Apple ID of `com.roro.futurevoice`). All CTAs (`[data-appstore]`, 7 per page) pick it up automatically, **including the two pricing-card buttons**, and get `target=_blank` once it is not `#`.
- [ ] Re-check the pricing figures against `subscription_plans` (Light 150 min / 60 scenes; Plus has NO talk cap since `20260821120000` — its card says "No limit" and only its scene count is a number, **120 since `20260823140000`**) and the prices against `docs/launch-billing.md`.
- [ ] Add an `og:image` (1200x630) and reference it in the meta tags.
- [x] Privacy policy page + footer link (`privacy.html` / `privacy-ko.html`).

## Conventions

- Fonts: Fraunces (display / "Future you" voice lines, italic) + Schibsted Grotesk (body), via Google Fonts.
- Colors are CSS variables in `:root` — paper `#F7F1E6`, ink `#221D17`, signal red `#E0472B`, dark `#1C1712`.
- No emojis anywhere; icons are inline SVG strokes.
- Company name in legal/footer text is always "Dear RoRo".
