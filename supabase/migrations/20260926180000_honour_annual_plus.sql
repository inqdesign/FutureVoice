-- ---------------------------------------------------------------------------
-- The one Plus ANNUAL subscriber keeps what the card said (2026-09-26).
--
-- d48b0216 signed up on 09-24, hit the free-call wall, saw the paywall four
-- times and bought Plus ANNUAL at €149.99 from a card that read
-- "Talking — No limit". Apple charges them 09-27 08:11 CEST, hours after the
-- bounded plans land. The founder is writing to them before the money moves
-- (`scripts/plus-annual-cap-mail.py`) and the mail promises this account is
-- left on what it bought, so the row has to say that BEFORE the mail goes.
--
-- Their stamp has been moved twice today by the "a trial converts into
-- today's plan" rule (`20260926130000`, then `20260926150000`) — right for
-- every future trial, wrong for this one person, because what they were sold
-- is not what a trial started today would be sold. A promise made on a
-- purchase screen outranks a stamping rule.
--
-- So: Plus as it stood on 2026-09-24 — no talk ceiling, 120 scenes — pinned
-- onto the row, which every meter reads before the plan. It is also the last
-- row this can ever apply to: intro offers are deleted, so no further trial
-- can start, and the annual plans are off sale.
--
-- Run this BEFORE the mail. The mail script refuses to send while the row
-- disagrees with it (`guard()`).
-- ---------------------------------------------------------------------------

update public.user_subscriptions
   set monthly_seconds = 108000,   -- descriptive on an uncapped row; the
                                   -- fair-use flag reads it (1,800 min)
       talk_unlimited  = true,
       monthly_scenes  = 120
 where user_id = 'd48b0216-9438-482d-87c1-4947063c6ff1';
