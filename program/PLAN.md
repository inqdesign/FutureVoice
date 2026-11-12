# Cohort 1 — what has to be ready, in order

Status: ☐ not started · ◐ built, not live · ☑ live and checked (say how it was checked).
The lead keeps this file true after every step.

## 1. Before the link is shared (this week)

- ☑ Challenger payment: Stripe product `nawana_challenge`, plans, checkout in payment mode,
  webhook writes the 100 days and links the application. Live 2026-11-12 (migrations
  `20261112090000` `20261112100000` `20261112140000`, the three functions, site, admin).
- ☑ Test payment end to end, 2026-11-12: a challenger application through the live function,
  a ₩0 checkout (100% coupon) completed by the founder → `user_subscriptions` row
  (light_challenge, active, 100 days, no renewal), talk pool 150 min, the application got
  user, paid_at and "active", a second checkout refused. Not seen: a card charge with a real
  amount, the app's Usage screen, the admin page itself.
- ☑ `RESEND_API_KEY` is in the function secrets (by name). No creator receipt has been seen arriving yet.
- ☑ Page copy agrees with RULES.md (3개월 구독료 선납, Light ₩40,500 as 참가비, the 10 days on
  the house, free months after day 100, not a refund). Live 2026-11-12: nawana.app/creators
  and /ko.html are byte-identical to the local files.
- ☑ Application deadline (11-19) on the page, form and `creator-apply` close after it. Live
  2026-11-12 (function v21). Not run past the deadline.
- ☑ Light only: `plus_challenge` / `max_challenge` off the web's shelf; checkout refuses them
  ("plan is not active") and opens for `light_challenge`. Checked live 2026-11-12.
- ☐ Cohort start saved in the admin (2026-12-01).

- ◐ The payment has its own page (2026-11-12, founder): `/pay` (web/creators-pay.html, vercel
  rewrite). After the form: "메일을 확인하세요" only; the mail leads a challenger through
  joining the app, then `/pay?id=…&cur=…` → sign in → Stripe → "모두 끝났어요". Screens were
  looked at (headless Chrome, phone width). NOT seen working: the sign-in round trip and the
  jump to Stripe from the page (needs a person). Fee by country: `LOCAL_FEE` (42 currencies).

## 2. While applications come in (11-12 → 11-19)

- ◐ Desk: list, notes, statuses, mails that open already written (challenger paid / unpaid,
  creator "next cohort"). Not live until the admin deploy.
- ☐ Acceptance mail for creators that opens already written (today only a DM to copy).
- ☐ 10bliss (applied 11-11 on the old form): payment mail after the deploy.

## 3. Before day 1 (11-20 → 11-30)

- ☐ Check-in page for participants: a creator leaves the day's post link, a challenger sees
  their days and months. Mock: `web/_mock/checkin.html`. Show the founder the screen first.
- ☐ Admin reads check-ins (no more marking days by hand; the strip shows all 100 days).
- ◐ A challenger's day checks in by itself (2026-11-12): `challenge_days` + `challenge_days_put`
  (migration `20261112160000`, applied; the RPC was called on production 2026-11-12: a non-participant stores nothing, a paid challenger's days are kept, bad rows skipped, a lower resend never lowers a day, the owner reads their own rows and the anon key cannot), the admin judges talk 4 min +
  1 speech by the participant's local date with a talk-only fallback, and both apps send the
  last 14 local days (`ChallengeDays.swift` / `ChallengeDays.kt`, built, tests compiled; iOS
  tests not run, nothing exercised against the RPC, nothing committed). Owed: apply the
  migration → one real call; the consent line and privacy policy name the speech count;
  builds submitted to both stores by about 2026-11-20 (11-24 at the latest).
- ☐ Start notice to everyone (mail, 합니다체, founder approves the words).

## 4. During the 100 days

- ☐ A weekly look: who is close to losing a month, who stopped. Drafts only; the founder sends.
- ☐ Daily wall / archive of creators' posts (direction 2026-11-10, not designed).

## 5. The end (2027-03-01 → 03-10)

- ◐ Challenger reward button (0–3 months).
- ☐ Each creator ended in the admin; applications deleted as the privacy policy promises.
