-- ---------------------------------------------------------------------------
-- Gifted subscriptions follow today's scene rule (2026-11-03, founder).
--
-- `scene_count_billing` (20261019120000) kept every account that had a
-- subscription row on 2026-10-19 on the old "N scenes a month" count, so
-- nobody who had BOUGHT scenes lost them. Six of those rows are comps —
-- subscriptions the founder gave away (5 Light, 1 Plus), not purchases —
-- and the founder's rule is that a gift follows the current offer: a scene
-- costs five minutes of the gifted pool, like every subscription sold since
-- 10-19. The paying subscribers (source 'apple') keep their count.
--
-- Measured before writing: those six played 6 scenes in the last 30 days
-- between them, so nothing anyone is doing changes. Old builds still see a
-- count (the server charges minutes only to a build that sends
-- `scene_billing: "talk"`).
-- ---------------------------------------------------------------------------

delete from public.scene_count_billing b
 using public.user_subscriptions s
 where s.user_id = b.user_id
   and s.source = 'comp';
