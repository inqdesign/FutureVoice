-- Show host series: be the host selling one thing live on a home-shopping
-- channel. Product and name are made up; no digits, no price figures.
insert into public.speech_challenges (id, language, title, genre, body, target_seconds, category)
values
  ('5beec000-0000-4000-8000-00000000001d', 'en', 'You will sleep like a baby', 'product',
   'Raise your hand if you woke up tired this morning. Yeah. Me too. Every single morning. Until I found this.

This is the Cloud Nine pillow. Go on, look at it. Now watch what happens when I press my hand in. Slowly, slowly, and it holds my hand like a hug. And when I let go, it comes right back. Like magic.

Side sleeper? It keeps your neck straight. Back sleeper? It holds your head like a cloud. And if you sleep on your tummy, dont worry, we thought of you, too.

And heres my favorite part. It stays cool. All night long. No more flipping the pillow over at three in the morning to find the cold side.

Our viewers have been writing in all week, and I want to read you just one. She says, "I slept through the night for the first time in years. My husband thinks Im a new person." I love that.

So tonight, buy one, and well send you a second one free. One for you, and one for the person who keeps stealing yours. The phones are open now!', 60, 'show_host')
on conflict (id) do nothing;
