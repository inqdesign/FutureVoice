-- The fifth speech challenge: "So, tell me about yourself."
--
-- Founder's ask (2026-10-27): something people say in English all the time.
-- The job-interview opener is the one answer nearly everyone has to give
-- out loud in English at some point, and it is the same shape everywhere:
-- who you are, one thing you did, why you are here, a line about you.
--
-- English only for now; other languages get their own row when written.
-- The speaker is a made-up product designer, so nothing claims to be the
-- learner. No digits ("five years", "twice as many"): a number is read in
-- more than one way and the scorer would mark the reading wrong.

insert into public.speech_challenges (id, language, title, genre, body, target_seconds)
values
  ('5beec000-0000-4000-8000-000000000015', 'en', 'So, tell me about yourself', 'person',
   'Sure. I''m a product designer, and for the last five years I''ve been building apps that people use every day.

I started out in graphic design, but I soon realized I cared less about how things looked and more about how they worked. So I moved into product design, and I haven''t looked back.

At my current company, I lead the design of our mobile app. Last year, we rebuilt the whole sign-up flow. We talked to dozens of users, tested every screen, and in the end, twice as many people finished signing up.

What I enjoy most is the moment a problem finally makes sense. It''s usually not on my screen. It''s when I''m sitting next to someone, watching them get stuck, and I suddenly see why.

I''m looking for my next step because I want to work on something with a bigger reach, and that''s why this role caught my eye.

Outside of work, I run, I cook, and I''m slowly learning Korean, which keeps me humble.

So that''s me, in a nutshell. I''d love to hear more about the team.', 60)
on conflict (id) do nothing;
