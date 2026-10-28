-- The fifth speech challenge: the home-shopping show host.
--
-- Founder (2026-10-28): a challenge has to make you WANT to read it, and
-- the job-interview answer written first didn't. A show host selling one
-- lipstick live is fun to perform, everyone has seen it, and it is all
-- energy, emphasis and talking straight to the camera, which is exactly
-- what the board films.
--
-- English only for now. The product and its name are made up. No digits
-- and no price: a number is read in more than one way and the scorer would
-- mark the reading wrong, so it is "half price" and "six o'clock".

insert into public.speech_challenges (id, language, title, genre, body, target_seconds)
values
  ('5beec000-0000-4000-8000-000000000015', 'en', 'Tonight only, half price!', 'product',
   'Okay, everyone, stop what you''re doing, because this is the one you''ve been waiting for!

This is the Velvet Kiss lipstick, and I''ve been wearing it since six o''clock this morning. Look at that. I''ve had coffee, I''ve had lunch, I''ve been talking nonstop for three hours, and it hasn''t moved. Not one bit.

Watch this. I''m going to wipe it with a tissue. See? Nothing. And it doesn''t feel dry, either. It feels like nothing at all, like your favorite lip balm.

Now, tonight you get not one, not two, but four shades. A soft pink for the office, a warm nude for every day, a deep berry for date night, and this red. Ladies, this red. It''s the kind of red that makes you walk a little taller.

And here''s the best part. Tonight only, the whole set is half price.

Our phones are already lighting up, and the red is going fast. So don''t wait, don''t overthink it, just pick up the phone. You deserve this. Trust me.', 60)
on conflict (id) do nothing;
