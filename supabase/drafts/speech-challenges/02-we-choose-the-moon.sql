-- John F. Kennedy, address at Rice University, Houston, 12 September 1962.
-- A US president's official speech is a federal work: public domain.
-- Excerpts in the speech's order; "35 years ago" is spelled out (digits are
-- read more than one way and the scorer would mark the reading wrong).
insert into public.speech_challenges (id, language, title, genre, body, sources, target_seconds, category)
values
  ('5beec000-0000-4000-8000-000000000017', 'en', 'We choose to go to the Moon', 'person',
   'We set sail on this new sea because there is new knowledge to be gained, and new rights to be won, and they must be won and used for the progress of all people.

But why, some say, the Moon? Why choose this as our goal? And they may well ask, why climb the highest mountain? Why, thirty-five years ago, fly the Atlantic?

We choose to go to the Moon. We choose to go to the Moon in this decade and do the other things, not because they are easy, but because they are hard; because that goal will serve to organize and measure the best of our energies and skills, because that challenge is one that we are willing to accept, one we are unwilling to postpone, and one we intend to win.

Many years ago the great British explorer George Mallory, who was to die on Mount Everest, was asked why did he want to climb it. He said, "Because it is there." Well, space is there, and we''re going to climb it.',
   '["John F. Kennedy, address at Rice University, Houston, 1962"]'::jsonb, 60, 'famous_speech')
on conflict (id) do nothing;
