-- A 50-minute pack anyone can buy, no subscription needed (2026-10-02,
-- founder decision).
--
-- The learner it is for: someone who spent the twenty free minutes in a night
-- (one did — three calls, one of 16 minutes), looked at the plans for thirty
-- seconds and left. A month's subscription was the only thing on offer.
-- Now the paywall's ladder carries a "without a subscription" rung:
-- 50 minutes, ₩5,900 / $4.99, one time, no expiry.
--
-- Priced ABOVE Light per minute (₩118 against ₩100) so three packs cost more
-- than a month of Light, and the second purchase points at the plan. At full
-- use 50 min costs ~$1.5 against ~$3.3 net in Korea.
--
-- `com.roro.futurevoice.talk_100` was built on 2026-09-26 for subscribers
-- and never went on sale (no App Store product). It is switched off so ONE
-- pack is on offer everywhere: `TalkTopUpService` takes the smallest active
-- row, so builds that only show the pack on the spent-pool sheet show this
-- one too. Nothing was ever bought under it, and `apply_talk_topup` only
-- grants a product whose row is active, so no receipt can be orphaned.
--
-- The pack lands in `user_credits.balance` like invite minutes (ledger kind
-- `topup`). Anything that trims free balances must leave `topup` seconds
-- alone — they were paid for.
--
-- Needs the App Store consumable `com.roro.futurevoice.talk_50` created and
-- submitted with the build that draws the ladder (its first consumable must
-- ride with an app version). Until it has a price the row draws nothing.

insert into public.talk_topups (apple_product_id, google_product_id, seconds, is_active)
values ('com.roro.futurevoice.talk_50', 'talk_50', 3000, true)
on conflict (apple_product_id) do update set seconds = excluded.seconds, is_active = true;

update public.talk_topups
   set is_active = false
 where apple_product_id = 'com.roro.futurevoice.talk_100';
