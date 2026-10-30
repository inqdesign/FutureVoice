-- Show host series: be the host selling one thing live on a home-shopping
-- channel. Product and name are made up; no digits, no price figures.
insert into public.speech_challenges (id, language, title, genre, body, target_seconds)
values
  ('5beec000-0000-4000-8000-000000000022', 'en', 'Ten minutes to glass skin', 'product',
   'Okay, everyone, Im going to do something a little embarrassing on live television. Im putting on a sheet mask. Right now. Dont laugh!

This is the Pure Petal mask. Look at it. Its dripping. Every single sheet is soaked in a full bottle of serum. Thats how much goes into one mask.

Now, Im laying it on. Forehead first, then the nose, smooth it down the cheeks, and press it around the mouth. And its cold! Oh, that feels amazing. Its like a cold drink for your face.

So heres what you do. Put it on, lie down, close your eyes, and in ten minutes, you take it off. Dont wash your face. Just pat the rest in with your fingers.

And Ill tell you what happens. Your skin drinks it all. It looks brighter, it feels bouncy, and it has that clear, dewy look. Glass skin, they call it.

Tonight, its not one box. Its three boxes. One for every night this week, one for the weekend, and one to share with your best friend. Or dont share. I wont tell.

Grab your phone. Your ten minutes start now!', 60)
on conflict (id) do nothing;
