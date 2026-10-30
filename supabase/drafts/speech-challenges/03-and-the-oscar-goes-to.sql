-- Written for nawana: the acceptance speech everyone has rehearsed in the
-- mirror. No real film, person or award body is named.
insert into public.speech_challenges (id, language, title, genre, body, target_seconds, category)
values
  ('5beec000-0000-4000-8000-000000000018', 'en', 'And the award goes to… you', 'person',
   'Oh my goodness. Okay. I didn''t write anything, because I really didn''t think this was going to happen.

Thank you. Thank you so much. To everyone in this room, I have watched you on screen my whole life, and now you''re clapping for me. I don''t know what to do with that.

When I was a little girl, I used to stand in front of the bathroom mirror with a shampoo bottle, and I gave this exact speech. Every night. My mom would knock on the door and say, "Who are you talking to in there?" Mom, I was talking to this room.

To the cast and the crew, you were my family for a whole year, in the rain, in the cold, at four in the morning. This is yours as much as it is mine.

And to anyone watching at home, holding a shampoo bottle right now: keep practicing. Say it out loud. One day, you won''t need the bottle.

Thank you. Good night!', 60, 'acceptance')
on conflict (id) do nothing;
