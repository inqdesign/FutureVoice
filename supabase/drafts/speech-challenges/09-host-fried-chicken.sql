-- Show host series: be the host selling one thing live on a home-shopping
-- channel. Product and name are made up; no digits, no price figures.
insert into public.speech_challenges (id, language, title, genre, body, target_seconds)
values
  ('5beec000-0000-4000-8000-00000000001e', 'en', 'Listen to that crunch', 'product',
   'Okay, Im sorry, I cant talk yet, because this just came out of the fryer and I have to try it. Give me one second.

Did you hear that? Turn your volume up. Let me do it again. That crunch! That is the sound of the crispiest chicken you will ever eat, and you can make it at home.

Golden on the outside, so juicy on the inside, look, look at that! Its dripping. And the secret is the batter. Double coated, so it stays crispy even the next morning. Yes, I tested it. Cold, straight out of the fridge, at midnight. Still crunchy.

It comes in two flavors. Original, for the classic people. And sweet and spicy, for the brave ones. Honestly? Get both. Youll thank me on Friday night.

Just put it in the air fryer, wait a few minutes, and dinner is done. No mess, no oil splashing everywhere, and the kids will think you ordered it.

Every box we had in the warehouse yesterday is already gone, and this is the last batch tonight. So call now, and Friday night is sorted!', 60)
on conflict (id) do nothing;
