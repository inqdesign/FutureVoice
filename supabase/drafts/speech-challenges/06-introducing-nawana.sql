-- Written for nawana: the app introduced like a launch keynote, by the
-- learner. Every claim is something the app does today (the voice clone,
-- talking with the fluent self in that voice, scenes before they happen,
-- saying a talk again the right way). No price, no plan size, no numbers.
insert into public.speech_challenges (id, language, title, genre, body, target_seconds, category)
values
  ('5beec000-0000-4000-8000-00000000001b', 'en', 'Introducing nawana', 'product',
   'Good morning, everyone. Today, I want to show you something I''ve been waiting for my whole life.

Think about the last time you tried to speak another language. You knew the words. You knew the grammar. And then someone looked at you, and everything disappeared.

The problem was never what you know. It''s that you''ve never heard yourself speak it well. Not once.

So we asked a simple question. What if you could?

This is nawana. You record your voice once, for one minute. And then you meet someone very special: you, a few years from now, already fluent. Same voice. Your voice. Speaking the language the way you''ve always wanted to.

You call your fluent self, and you just talk. About your day, your job, your plans. When you get stuck, it doesn''t judge you. It shows you how you could say it.

Got a job interview next week? Watch your fluent self do it first. Made a mistake in a call? Say the whole conversation again, the right way, out loud.

Because the fastest way to become fluent is to hear who you''re about to become.

This is nawana. Meet your fluent self.', 60, 'product_launch')
on conflict (id) do nothing;
