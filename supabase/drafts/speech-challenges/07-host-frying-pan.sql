-- Show host series: be the host selling one thing live on a home-shopping
-- channel. Product and name are made up; no digits, no price figures.
insert into public.speech_challenges (id, language, title, genre, body, target_seconds, category)
values
  ('5beec000-0000-4000-8000-00000000001c', 'en', 'Not a drop of oil!', 'product',
   'Good evening, everyone, and welcome back! Now, I want you to look very closely at this pan, because Im about to do something crazy.

No oil. No butter. Nothing. Im cracking an egg straight in. Listen to that sizzle. And now, watch this. A little shake, and look, it just slides right off. Like its on ice!

But thats too easy, right? So lets make it hard. This is cheese. Lots of cheese. Im going to burn it on purpose. Smell that? Thats the smell of a pan youd normally throw away. And now, one wipe with a paper towel. Gone. Completely clean.

You can put it in the dishwasher, you can put it in the oven, and you can use a metal spoon on it. Go ahead, scratch it. I dare you.

And tonight, youre not getting one pan. Youre getting the big one, the small one, and the lid, all in one box.

The counter is running, and we only have a few hundred sets left. So grab your phone and call right now, before your neighbor does!', 60, 'show_host')
on conflict (id) do nothing;
