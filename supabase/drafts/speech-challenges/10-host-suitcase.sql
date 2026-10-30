-- Show host series: be the host selling one thing live on a home-shopping
-- channel. Product and name are made up; no digits, no price figures.
insert into public.speech_challenges (id, language, title, genre, body, target_seconds, category)
values
  ('5beec000-0000-4000-8000-00000000001f', 'en', 'Go ahead, stand on it', 'product',
   'Everyone, I want you to remember the worst airport moment of your life. The broken wheel. The handle that wont come down. The suitcase that comes out of the carousel looking like it lost a fight.

Never again. This is the Featherlight suitcase. And Im going to prove it to you right now.

First, Im lifting it with one finger. One finger! Now, Im going to drop it on the floor. Hard. Look. Not a scratch. And now, the big one. Im going to stand on it. Are you watching? Im standing on it, and its fine!

The wheels spin all the way around, so it glides next to you like a little dog. Theres a pocket for your laptop, a pocket for your shoes, and a hidden pocket for your passport, so youll never have that panic at the gate again.

And tonight, you get the big one for checking in and the small one for the cabin. Pick your color. We have black, navy, and this gorgeous mint, which is almost gone.

Your next trip starts with this phone call. Call now!', 60, 'show_host')
on conflict (id) do nothing;
