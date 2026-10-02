-- A third tier above Plus: Max, 1,200 min + 30 scenes a month (2026-10-02,
-- founder decision: twice Plus, at twice its price).
--
-- Asked for by a learner two days into Light (75 of 150 min, 59 min on one
-- day): "생각보다 통화량이 많아져서 600분 이상 플랜도 있었으면 좋겠습니다."
-- Before this, Plus was the end of the road — the 100-minute pack is built
-- but not on sale, so a Plus learner who emptied the pool had nothing to buy.
--
-- PRICED AT TWICE PLUS, so the bigger plan is never the dearer minute:
-- ₩58,000 / $49.99 for 1,200 min is the same ₩48 a minute as Plus's 600.
-- A first draft priced it against what these people already spend on phone
-- English (₩79,000 — the same spend as 10 min × 5 a week for 200 minutes)
-- and was dropped the same day: next to Plus on the paywall it was 2.7× the
-- price for 2× the time, which punishes the people the plan is for.
--
-- At FULL use it loses a little in Korea, as Plus does — Plus is below cost
-- there, and no Max can be both cheaper per minute than Plus and whole:
--
--   cost: 1,200 min × $0.03 = $36 (+ $3.6 if all 30 scenes are played;
--         the heaviest paying account ever played 28, most play none)
--   KR  ₩58,000 / 1.1 VAT × 0.85 ≈ $32.5 net  →  −$3.5 (−$7 with scenes)
--   US  $49.99 × 0.85             ≈ $42.5 net  →  +$6.5 (+$2.9 with scenes)
--
-- Unlike Plus, Max is bought by the people who use it all, so full use is
-- the expected case here, not the worst one. The loss is bounded per
-- account; revisit by the price of BOTH tiers if Korean Max rows pile up.
--
-- Monthly only. Annual stays a question for Plus and Max together.
--
-- INACTIVE until the build that draws the Max card is SUBMITTED, with the
-- App Store product (`com.roro.futurevoice.max_monthly`, same subscription
-- group as Light and Plus, ₩58,000 / $49.99) attached to that submission.
-- App Review has to find the plan in the app to approve it, and a product
-- waiting for review still loads in the sandbox; builds already in the store
-- hard-code two cards, so switching the row on cannot reach them. Before the
-- product exists, an active row would draw a card with no price.
--
-- Nothing else on the server changes: the webhook and `apple-claim` map a
-- transaction to its plan by `apple_product_id`, and every meter reads
-- `monthly_seconds` / `monthly_scenes` off the plan (or the row's stamp).
-- Builds before the Max card hard-code two cards and simply never show it.

insert into public.subscription_plans
  (id, tier, period, credits_per_cycle, apple_product_id, is_active,
   daily_seconds, daily_scenes, monthly_seconds, monthly_scenes,
   talk_unlimited, abuse_seconds)
values
  ('max_monthly', 'max', 'monthly', 3000, 'com.roro.futurevoice.max_monthly', false,
   2400, 1, 72000, 30, false, null)
on conflict (id) do nothing;

-- When the build is submitted with the product attached:
--   update public.subscription_plans set is_active = true where id = 'max_monthly';
