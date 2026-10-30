-- Show host series: be the host selling one thing live on a home-shopping
-- channel. Product and name are made up; no digits, no price figures.
insert into public.speech_challenges (id, language, title, genre, body, target_seconds, category)
values
  ('5beec000-0000-4000-8000-000000000021', 'en', 'The last mop you will ever buy', 'product',
   'Everybody, stop! Do not clean your floor tonight. Not until youve seen this.

Ive got ketchup. Ive got coffee. And Ive got the dirtiest muddy footprints our crew could make. This is every kitchen at dinner time, right? Now watch.

One swipe. Gone. Two swipes. Gone. Look at that floor! You could eat off that floor. Please dont, but you could.

And heres the magic. Step on this pedal, and the mop wrings itself. Your hands never touch the dirty water. Ever. And the head spins all the way around, so it gets under the sofa, behind the toilet, and into that corner nobody has cleaned since you moved in.

When youre done, just pull off the pad and throw it in the washing machine. It comes out like new.

I have three kids and a dog, and this is the only reason my house doesnt look like a disaster.

So tonight, you get the mop, the bucket, and four extra pads. Your floors, your back, and your weekends are going to thank you. Call right now, the lines are open!', 60, 'show_host')
on conflict (id) do nothing;
