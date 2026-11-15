-- The Interstellar challenge is read as a film critic, not a movie scene
-- (founder, 2026-11-15: its label read "영화 장면"). Its own category key,
-- `film_review`, named "Film critic" / 영화평론가; the speech app still draws
-- it on the film tile. A build that doesn't know the key shows no label.
update public.speech_challenges
   set category = 'film_review'
 where id = '5beec000-0000-4000-8000-00000000002d';
