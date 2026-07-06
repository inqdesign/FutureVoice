# Future Voice — marketing landing page

Static pages, no build step. Everything (CSS/JS) is inlined.

- `index.html` — English
- `ko.html` — Korean (generated from index.html; marketing copy translated, phone mockup UI stays English like the real app). When you change index.html, port the change to ko.html.

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

The pricing section is built in but **hidden** until configured (`BILLING.enabled`
in the inline module script of each page). Flow:

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
7. **Page config** — in both `index.html` and `ko.html`, fill `BILLING.supabaseUrl`
   / `supabaseAnonKey`, set `enabled: true`, and replace the PLACEHOLDER prices
   in `PLANS` with the real Stripe prices.

Notes:
- Never link to this page's checkout from **inside** the iOS app (App Review).
- Credits are granted on `invoice.paid`, idempotent by invoice id — Stripe
  retries are safe.
- A Stripe **customer portal** (self-serve cancel/upgrade) is a sensible
  follow-up: add a `stripe-portal` function that creates a portal session.

## Before launch

- [ ] Replace `TESTFLIGHT_URL` in the inline `<script>` at the bottom of `index.html` with the public TestFlight invite link. All CTAs (`[data-testflight]`) pick it up automatically.
- [ ] Add an `og:image` (1200x630) and reference it in the meta tags.
- [ ] Privacy policy page + footer link (required before App Store launch).

## Conventions

- Fonts: Fraunces (display / "Future you" voice lines, italic) + Schibsted Grotesk (body), via Google Fonts.
- Colors are CSS variables in `:root` — paper `#F7F1E6`, ink `#221D17`, signal red `#E0472B`, dark `#1C1712`.
- No emojis anywhere; icons are inline SVG strokes.
- Company name in legal/footer text is always "Dear RoRo".
