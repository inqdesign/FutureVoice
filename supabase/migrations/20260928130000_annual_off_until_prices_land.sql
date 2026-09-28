-- ---------------------------------------------------------------------------
-- Annual comes OFF sale again until the App Store prices actually change
-- (2026-09-28; applied by hand the same day).
--
-- `20260926170000` put annual back on sale while the "2 months free" prices
-- were still only SCHEDULED in App Store Connect (start 2026-09-29). So the
-- paywall sold the old table beside the new monthly: in the US Light annual
-- $79.99 against $9.99 ("4 months free") and Plus annual $143.99 against the
-- $24.99 monthly that took effect today ("Save 52%"). That migration's own
-- header said to run it only after the prices changed.
--
-- Turn it back on with a NEW migration once Apple's price schedule shows the
-- 2026-09-29 rows live (read them — don't assume the date).
-- ---------------------------------------------------------------------------

update public.subscription_plans
   set is_active = false
 where period = 'annual';
