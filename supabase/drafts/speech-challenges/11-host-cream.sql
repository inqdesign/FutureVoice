-- Show host series: be the host selling one thing live on a home-shopping
-- channel. Product and name are made up; no digits, no price figures.
insert into public.speech_challenges (id, language, title, genre, body, target_seconds)
values
  ('5beec000-0000-4000-8000-000000000020', 'en', 'Wake up glowing', 'product',
   'Ladies and gentlemen, before I say anything, I want you to look at my face. Really look. No filter, no makeup, just me, at the end of a very long day.

This is what two weeks of the Morning Dew night cream does. Two weeks!

Heres how it works. Right before bed, just a little bit, the size of a pea. You warm it between your fingers, and you press it gently into your skin. Thats it. It smells like fresh cucumber, and it melts in like water.

And then you sleep. And while you sleep, it works. When you wake up, your skin feels soft, it feels plump, and it has that glow. You know the glow. The one everyone asks about.

Our customers keep telling us the same thing. "My friends asked if I went on vacation." Thats what we hear every single day.

Tonight, you get the big jar, plus a travel size for your bag, plus a free eye cream. Three for the price of one.

Its the most popular thing weve sold all year, and its almost gone. Treat yourself tonight. Youve earned it.', 60)
on conflict (id) do nothing;
