-- Every challenge published before categories gets one (founder, 2026-11-04),
-- read off its genre: the short explainer talks and the in-flight
-- announcements. A challenge that already has a category is left alone.
update public.speech_challenges set category = 'short_talk'
 where category is null and genre = 'explainer';
update public.speech_challenges set category = 'in_flight'
 where category is null and genre = 'briefing';
