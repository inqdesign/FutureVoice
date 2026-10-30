-- Show host series: be the host selling one thing live on a home-shopping
-- channel. Product and name are made up; no digits, no price figures.
insert into public.speech_challenges (id, language, title, genre, body, target_seconds, category)
values
  ('5beec000-0000-4000-8000-000000000023', 'en', 'The one step everybody skips', 'product',
   'Can I ask you a question? Whats the most important thing you put on your skin every morning? Moisturizer? Serum? Nope. Its sunscreen. And I know, I know, most of us skip it.

Because sunscreen is sticky. Its heavy. It makes you look like a ghost in every photo. Right? Not this one.

This is the Daylight Veil sunscreen. Look how I put it on. Two lines on my finger, thats all you need. Spread it out, and watch. Gone. No white cast, no greasy shine, and it smells like nothing at all.

It goes on like a light lotion, and it works like a primer, so your makeup stays put all day. On the beach, in the car, by the window at the office. Yes, the sun gets you through the window, too.

And heres the truth nobody tells you. Most of the lines and dark spots on your face? Theyre from the sun. So this little bottle is the best anti-aging you will ever buy.

Tonight, you get two big bottles and a stick for your bag, so you can put it on again after lunch.

Your future skin is going to thank you. Call now!', 60, 'show_host')
on conflict (id) do nothing;
