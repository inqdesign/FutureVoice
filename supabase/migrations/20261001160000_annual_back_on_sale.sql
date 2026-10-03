-- Annual back on sale (2026-10-01).
--
-- `20260928130000` took it off "until Apple's price schedule shows the
-- 2026-09-29 rows live (read them — don't assume the date)". Read on
-- 2026-10-01 through the App Store Connect API, live for new buyers:
--
--   USA  Light   $9.99 / $99.99      Plus  $24.99 / $249.99
--   KOR  Light ₩15,000 / ₩149,000    Plus ₩29,000 / ₩290,000
--   DEU  Light  €9.99 / €99.99       Plus €22.99 / €229.99
--   JPN  Light ¥1,500 / ¥15,000      Plus ¥3,000 / ¥30,000
--   GBR  Light  £9.99 / £99.99       Plus £19.99 / £199.99
--
-- Ten months for a year in every one of them, so the paywall's badge reads
-- "2 months free" (`PaywallView.annualSavingLabel`).
--
-- At FULL use (150 min + 10 scenes = $5.70/mo; 600 min + 30 scenes =
-- $21.60/mo), after Apple's 15% and VAT: Light annual +$17/yr (US); Plus
-- annual −$47/yr (US), −$68 (DE), −$99 (KR). Plus monthly already loses at
-- full use, so no annual discount can make Plus annual whole; the bet is the
-- same one taken on Plus monthly. Real use says otherwise: the heaviest paying
-- account talked 173 min in the last 30 days and played no scenes — about
-- $5/mo of cost, so that account on Plus annual is ≈ +$150/yr (US).
-- Revisit when any Plus account crosses ~450 min in a period, by the POOL.

update public.subscription_plans
   set is_active = true
 where period = 'annual';
