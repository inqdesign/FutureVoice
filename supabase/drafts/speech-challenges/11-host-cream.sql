-- Show host series: be the host selling one thing live on a home-shopping
-- channel. Product and name are made up; no digits, no price figures.
insert into public.speech_challenges (id, language, title, genre, body, target_seconds, category)
values
  ('5beec000-0000-4000-8000-000000000020', 'en', 'Wake up glowing', 'product',
   'Ladies and gentlemen, before I say anything, look at my face. Up close. No filter, no foundation, nothing. Just my real skin, at the end of a very long day.

Two weeks ago, my skin was tired. Dry around the nose, rough on the cheeks, and these little lines by my eyes every time I smiled. Sound familiar?

This is the Morning Dew night cream. Watch how I use it. Clean skin, a little bit, the size of a pea. Warm it between your fingers, and press it in. Dont rub. Press. Forehead, cheeks, chin, and a tiny bit under the eyes.

Feel how light that is? It smells like fresh cucumber, and it disappears like water. No sticky pillow, no shiny face.

And while you sleep, it does the work. It holds the moisture in all night, so in the morning your skin is soft, plump and smooth, and your makeup goes on like silk. Some mornings, honestly, I skip the makeup.

Tonight, you get the big jar, a travel size for your bag, and a free eye cream. Three for the price of one.

Your skin works hard for you every day. Give it one good night. Call now!', 60, 'show_host')
on conflict (id) do nothing;
