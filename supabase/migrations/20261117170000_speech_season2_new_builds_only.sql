-- English Season 2 takes entries from price-list builds only (2026-11-17,
-- founder).
--
-- 20261113150000 let builds that score 7 (iOS 1.3.3 and older) enter
-- Season 2: their take was checked as scoring 7 and filed under the price
-- list with no sounds, because those builds send no per-sound counts. So a
-- take from such a build was never charged for pronunciation, and one read
-- 99 on 2026-11-17 where the same reading on a current build loses 0.4 per
-- weak sound. One board, one rule: a scoring-7 take is now refused
-- (NEEDS_UPDATE, as before 20261113150000), and the season's list is no
-- longer shown to those builds.
--
-- Entries already on the board stay as they are.

update public.speech_seasons
   set converts_from = null
 where language = 'en' and season = 2;
