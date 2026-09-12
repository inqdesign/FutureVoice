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
`subscription_plans.monthly_seconds` / `monthly_scenes`. **Each page charges the
currency it prints**: the checkout call passes `CURRENCY` (ko page `krw`, en
page `usd`), and the Stripe Prices must carry a `currency_options` entry for
both — see step 2 below. A page must never show a number Stripe won't charge.

Stripe flow (minutes-native: the subscription ROW is the entitlement — the
webhook grants nothing, ever):

```
site → Sign in with Apple (Supabase OAuth, same identity as the app)
     → stripe-checkout Edge Function → Stripe Checkout (7-day trial iff no
       subscription row has ever existed for the user — parity with Apple's
       one-intro-offer rule)
Stripe → stripe-webhook Edge Function → user_subscriptions upsert
       (plan resolved from the subscription's live PRICE, so portal
        plan changes stay correct; checkout metadata is only the fallback)
site "구독 관리" → stripe-portal Edge Function → Stripe-hosted portal
       (cancel / plan change / card — a web sub can't be cancelled in
        the App Store, so this link ships WITH the buy button, never later)
app  → reads the same tables — no app changes needed
```

Double-subscription guard: `user_subscriptions` is one row per user, so
`stripe-checkout` returns **409** when an entitled row already exists —
`already_subscribed` (Stripe: use the portal) or `store_subscription_active`
(Apple/Google: cancel there first). Both pages show a specific message for
each; without the guard a web purchase would charge twice and overwrite the
store entitlement.

Go-live checklist, in order:

1. **Migration** — `20260703120000_stripe_web_billing.sql` is applied (adds
   `stripe_price_id` to plans, `source`/`stripe_*` to user_subscriptions;
   the `source` check was widened later by the Google scaffold migration).
2. **Stripe** — create 1 Product per tier with 4 Prices total
   (light/plus × monthly/annual). Each Price: **USD base + `currency_options`
   for `krw`** (Apple's hand-set won figures: ₩15,000 / ₩110,000 / ₩29,000 /
   ₩209,000 — from `docs/launch-billing.md`) and optionally `eur`.
   Multi-currency options can only be set via the API/CLI, not the dashboard
   form. Enable **Stripe Tax with tax-INCLUSIVE behaviour** so the charged
   total equals the printed price, as it does on the App Store.
3. **Catalog** — fill `subscription_plans.stripe_price_id` for the four plans.
4. **Secrets** — `supabase secrets set STRIPE_SECRET_KEY=sk_... STRIPE_WEBHOOK_SECRET=whsec_... SITE_URL=https://<domain>`
5. **Deploy functions** — `supabase functions deploy stripe-checkout stripe-portal`
   and `supabase functions deploy stripe-webhook --no-verify-jwt`.
6. **Stripe webhook endpoint** — `https://<project>.supabase.co/functions/v1/stripe-webhook`
   with events: `checkout.session.completed`, `invoice.paid`,
   `customer.subscription.updated`, `customer.subscription.deleted`.
7. **Customer portal** — Stripe Settings → Billing → Customer portal: enable
   cancel + plan switching among the four Prices, save the default
   configuration (stripe-portal uses it).
8. **Apple web sign-in** — DONE 2026-09-03 via `scripts/apple-web-signin.py`:
   Services ID `com.roro.futurevoice.web` (team PXS8Q4NT67), key `G5Q9Y57N22`
   (.p8 in `~/Documents/AuthKey collection/`). The client-id list order is
   LOAD-BEARING: GoTrue uses the FIRST id as the web OAuth client_id, so the
   Services ID leads and the bundle ids follow (they only validate native
   id_tokens). **Secret expires 2027-03-01 — re-run the script to renew.**
8b. **Google web sign-in** — the pages offer it next to Apple (`[data-signin]`
   chooser). One **web-type** OAuth client serves the site AND Android
   (Credential Manager's serverClientId = the same id). Create it in Google
   Cloud console (redirect URI `https://<project>.supabase.co/auth/v1/callback`),
   download the client JSON, then `python3 scripts/google-web-signin.py` —
   it enables the provider via the Management API. Google's secret does not
   expire. Until configured, the Google link dead-ends (launch-web.sh warns).
9. **Page config** — DONE 2026-09-03: both `.next` pages carry
   `enabled: true`. Nothing sells until the pages are promoted to the root,
   which is `scripts/launch-web.sh` (preflight + swap + deploy + smoke).
10. **Verify after launch** (all four rehearsed server-side on 2026-09-03
    with a throwaway user — checkout URLs in krw/usd/eur, both 409 branches,
    portal 404; what remains needs a real card): fresh user gets the 7-day
    trial (₩0) and a `trialing` row; Apple-subscribed user gets the 409
    message; portal cancel flips the row to `cancel_at_period_end`; a portal
    plan switch updates `plan_id`.

Notes:
- **Shared Stripe account (Dear RoRo)** — the same account already bills
  humhumhum (tips) and DeskSquat (licenses). `STRIPE_SECRET_KEY` is the same
  account-wide `sk_...`; the **webhook signing secret is per endpoint**, so
  FutureVoice's endpoint gets its own `whsec_...` (never reuse DeskSquat's).
  Every webhook on the account sees every matching event, so each project
  filters to its own: DeskSquat by payment-link id, humhumhum by
  `metadata.kind === "tip"`, FutureVoice by `metadata.project === "futurevoice"`
  + `user_id` (set at checkout, skipped quietly otherwise). Keep that
  convention for anything new on the account.
- Never link to this page's checkout from **inside** the iOS app (App Review).
- The webhook returns 500 on handler failure so Stripe retries; the upsert is
  idempotent (keyed on user_id), so retries are safe.
- Trials: `status='trialing'` is metered pro-rated 7/30 server-side, same as
  an Apple trial — nothing extra to configure.

## Before launch

- **Launch day is one command**: `bash scripts/launch-web.sh` — preflight
  (billing flag, webhook health, price ids), promotes `.next` → root, deploys
  to Vercel, smoke-tests the live page, prints the 4 real-money checks.
- [x] `APP_STORE_URL` is filled in BOTH `.next` pages (`https://apps.apple.com/app/id6792794655` — Apple ID of `com.roro.futurevoice`). All CTAs (`[data-appstore]`, 7 per page) pick it up automatically, **including the two pricing-card buttons**, and get `target=_blank` once it is not `#`.
- [ ] Re-check the pricing figures against `subscription_plans` (Light 150 min / 60 scenes; Plus has NO talk cap since `20260821120000` — its card says "No limit" and only its scene count is a number, **120 since `20260823140000`**) and the prices against `docs/launch-billing.md`.
- [ ] Add an `og:image` (1200x630) and reference it in the meta tags.
- [x] Privacy policy page + footer link (`privacy.html` / `privacy-ko.html`).

## Conventions

- Fonts: Fraunces (display / "Future you" voice lines, italic) + Schibsted Grotesk (body), via Google Fonts.
- Colors are CSS variables in `:root` — paper `#F7F1E6`, ink `#221D17`, signal red `#E0472B`, dark `#1C1712`.
- No emojis anywhere; icons are inline SVG strokes.
- Company name in legal/footer text is always "Dear RoRo".
