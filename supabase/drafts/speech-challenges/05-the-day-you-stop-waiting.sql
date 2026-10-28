-- Written for nawana: a graduation speech in the spirit of the famous ones,
-- in its own words. No line of any real commencement speech is used.
insert into public.speech_challenges (id, language, title, genre, body, target_seconds)
values
  ('5beec000-0000-4000-8000-00000000001a', 'en', 'The day you stop waiting', 'person',
   'Graduates, I''m going to keep this short, because I remember sitting where you are, and I remember not listening to a single word.

So here''s just one thing.

For most of my life, I was waiting. Waiting until I was good enough. Waiting until I had more money, more time, more experience. Waiting for someone to tell me I was ready.

Nobody ever did. Nobody ever will. That''s the secret nobody tells you at graduation: there is no moment when you feel ready. There''s only the moment you decide to start anyway.

The best things in my life began on days I was sure I would fail. My first job, my first business, the first time I said "I love you." Every one of them, I started before I was ready.

So don''t wait for permission. Don''t wait for the perfect plan. Pick the thing that scares you a little, and start it badly. You can fix badly. You can''t fix never.

Congratulations. Now go start something.', 60)
on conflict (id) do nothing;
