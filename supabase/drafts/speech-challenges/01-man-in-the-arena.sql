-- Theodore Roosevelt, "Citizenship in a Republic", Paris, 23 April 1910.
-- Public domain. The "man in the arena" paragraph, word for word.
insert into public.speech_challenges (id, language, title, genre, body, sources, target_seconds, category)
values
  ('5beec000-0000-4000-8000-000000000016', 'en', 'The man in the arena', 'person',
   'It is not the critic who counts; not the man who points out how the strong man stumbles, or where the doer of deeds could have done them better.

The credit belongs to the man who is actually in the arena, whose face is marred by dust and sweat and blood; who strives valiantly; who errs, who comes short again and again, because there is no effort without error and shortcoming; but who does actually strive to do the deeds; who knows great enthusiasms, the great devotions; who spends himself in a worthy cause.

Who at the best knows in the end the triumph of high achievement, and who at the worst, if he fails, at least fails while daring greatly, so that his place shall never be with those cold and timid souls who neither know victory nor defeat.',
   '["Theodore Roosevelt, \"Citizenship in a Republic\", Sorbonne, Paris, 1910"]'::jsonb, 60, 'famous_speech')
on conflict (id) do nothing;
