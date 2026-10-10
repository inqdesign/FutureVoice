-- ---------------------------------------------------------------------------
-- The Android closed-test codes give Light, not Plus.
--
-- `20261002120000_android_tester_comp_codes` minted 15 one-month Plus codes
-- for the closed test. What a tester is asked for is two weeks of two or
-- three calls a week — well inside Light's 150 minutes — and a Plus month
-- fully used costs ~$22 upstream against ~$5.7 for Light, so the founder
-- moved them to Light on 2026-10-07, before a single one was redeemed.
--
-- Only unredeemed codes move: a code someone has already used keeps the plan
-- it was handed out as.
-- ---------------------------------------------------------------------------

update public.comp_codes
   set plan_id = 'light_monthly'
 where note like 'android tester%'
   and plan_id = 'plus_monthly'
   and redeemed_count = 0;
