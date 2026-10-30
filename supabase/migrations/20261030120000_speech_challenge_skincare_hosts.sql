-- The skincare show-host set (founder, 2026-10-30): sunscreen, sheet mask,
-- night cream, newest last so the cream leads the list. From the drafts.
insert into public.speech_challenges (id, language, title, genre, body, target_seconds, published_at)
values
  ('5beec000-0000-4000-8000-000000000023', 'en', 'The one step everybody skips', 'product',
   'Can I ask you a question? Whats the most important thing you put on your skin every morning? Moisturizer? Serum? Nope. Its sunscreen. And I know, I know, most of us skip it.

Because sunscreen is sticky. Its heavy. It makes you look like a ghost in every photo. Right? Not this one.

This is the Daylight Veil sunscreen. Look how I put it on. Two lines on my finger, thats all you need. Spread it out, and watch. Gone. No white cast, no greasy shine, and it smells like nothing at all.

It goes on like a light lotion, and it works like a primer, so your makeup stays put all day. On the beach, in the car, by the window at the office. Yes, the sun gets you through the window, too.

And heres the truth nobody tells you. Most of the lines and dark spots on your face? Theyre from the sun. So this little bottle is the best anti-aging you will ever buy.

Tonight, you get two big bottles and a stick for your bag, so you can put it on again after lunch.

Your future skin is going to thank you. Call now!', 60, now() - interval '2 minutes')
on conflict (id) do nothing;

insert into public.speech_challenges (id, language, title, genre, body, target_seconds, published_at)
values
  ('5beec000-0000-4000-8000-000000000022', 'en', 'Ten minutes to glass skin', 'product',
   'Okay, everyone, Im going to do something a little embarrassing on live television. Im putting on a sheet mask. Right now. Dont laugh!

This is the Pure Petal mask. Look at it. Its dripping. Every single sheet is soaked in a full bottle of serum. Thats how much goes into one mask.

Now, Im laying it on. Forehead first, then the nose, smooth it down the cheeks, and press it around the mouth. And its cold! Oh, that feels amazing. Its like a cold drink for your face.

So heres what you do. Put it on, lie down, close your eyes, and in ten minutes, you take it off. Dont wash your face. Just pat the rest in with your fingers.

And Ill tell you what happens. Your skin drinks it all. It looks brighter, it feels bouncy, and it has that clear, dewy look. Glass skin, they call it.

Tonight, its not one box. Its three boxes. One for every night this week, one for the weekend, and one to share with your best friend. Or dont share. I wont tell.

Grab your phone. Your ten minutes start now!', 60, now() - interval '1 minute')
on conflict (id) do nothing;

insert into public.speech_challenges (id, language, title, genre, body, target_seconds, published_at)
values
  ('5beec000-0000-4000-8000-000000000020', 'en', 'Wake up glowing', 'product',
   'Ladies and gentlemen, before I say anything, look at my face. Up close. No filter, no foundation, nothing. Just my real skin, at the end of a very long day.

Two weeks ago, my skin was tired. Dry around the nose, rough on the cheeks, and these little lines by my eyes every time I smiled. Sound familiar?

This is the Morning Dew night cream. Watch how I use it. Clean skin, a little bit, the size of a pea. Warm it between your fingers, and press it in. Dont rub. Press. Forehead, cheeks, chin, and a tiny bit under the eyes.

Feel how light that is? It smells like fresh cucumber, and it disappears like water. No sticky pillow, no shiny face.

And while you sleep, it does the work. It holds the moisture in all night, so in the morning your skin is soft, plump and smooth, and your makeup goes on like silk. Some mornings, honestly, I skip the makeup.

Tonight, you get the big jar, a travel size for your bag, and a free eye cream. Three for the price of one.

Your skin works hard for you every day. Give it one good night. Call now!', 60, now())
on conflict (id) do nothing;

