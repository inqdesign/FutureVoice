-- ---------------------------------------------------------------------------
-- One bar, not two.
--
-- The club shipped with an asymmetric pair: 28 of 30 days to get IN, 5 of 7 to
-- STAY. The asymmetry was deliberate — a seat was meant to be loose so a
-- missed day cost nothing — and it turned out to be the thing nobody could
-- hold in their head. Three numbers (28/30, 5/7, and the 4-minute day) is two
-- numbers too many for a rule a learner is supposed to live by, and the loose
-- keep bar quietly let a seat be held by someone doing barely more than half
-- of what the people waiting outside were doing.
--
-- So: the same bar everywhere. Last 30 days, 28 of them over the daily
-- minutes. To qualify, to keep a seat, and to stay eligible while waiting for
-- one. There is now exactly one sentence to learn, and it is true for
-- everyone in every state.
--
-- No schema change and no function change: the settlement, the promotion
-- ordering and the return path all read their windows from this table, which
-- is what the config row is for.
--
-- WHAT THIS DOES TO LIVE MEMBERS: at the next settlement, a seated member
-- whose last 30 days hold fewer than 28 met days is released. Under 5/7 they
-- could be at ~21/30 and keep the seat; now they can't. Releases still happen
-- before promotions, so nobody is displaced by an arrival — they simply stop
-- clearing the bar they now share with everyone else.
-- ---------------------------------------------------------------------------

update public.core_club_config
   set keep_window_days   = entry_window_days,
       keep_required_days = entry_required_days,
       updated_at         = now()
 where id;

comment on column public.core_club_config.keep_required_days is
  'Held equal to entry_required_days since 20260815140000: one bar for '
  'qualifying, for keeping a seat, and for staying eligible while waiting. '
  'Splitting them again means teaching a learner two rules.';
