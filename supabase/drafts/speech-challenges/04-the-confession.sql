-- Written for nawana: the heroine's big confession at the end of every
-- romantic comedy. Original text; no film is quoted.
insert into public.speech_challenges (id, language, title, genre, body, target_seconds)
values
  ('5beec000-0000-4000-8000-000000000019', 'en', 'Wait. Don''t get on that plane.', 'person',
   'Wait. Please, just wait. Don''t get on that plane. Not yet.

I ran all the way here, and I don''t even know what I''m going to say, so just let me say it.

You were right. I was scared. Every time you got close, I found a reason to be busy, or tired, or angry about something that didn''t matter. Because if I let you in and you left, I didn''t know what I''d do.

But you''re leaving anyway. And standing here, I realized that losing you because I was scared is so much worse than losing you because I tried.

So I''m trying. This is me, trying. I miss you when you''re in the next room. I laugh at your terrible jokes when you''re not even there. And I don''t want a life where I have to tell someone about you in the past tense.

I''m not asking you to stay. I''m just asking you to know. I love you. That''s it. That''s the whole speech.', 60)
on conflict (id) do nothing;
