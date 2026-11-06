-- Speech challenge (founder, 2026-11-06): podcast host, open a new episode
-- of your own show. Original script, written for nawana.
-- No digits ("five-minute", "half an hour").
insert into public.speech_challenges (id, language, title, genre, body, sources, target_seconds, category, intro, link)
values
  ('5beec000-0000-4000-8000-000000000025', 'en', 'Welcome back to the show', 'explainer',
   'Hey, everyone, and welcome back to Small Wins, the show about the tiny things that quietly change your life. I''m your host, and I''m so glad you''re here.

Grab a coffee and put your feet up, because today''s episode is a good one. We''re talking about the five-minute rule. Here''s the idea. When you don''t feel like doing something, you tell yourself, I''ll just do it for five minutes. That''s it. Five minutes, and then I can stop.

And here''s the funny thing. You almost never stop. Because the hardest part was never the work. It was starting.

I tried this last month with running. I hate running. I really do. But every morning I said, five minutes, just around the block. And guess what? This morning I ran for half an hour, and I didn''t even notice.

So today, I''ve got a guest who used this little trick to write an entire book. But first, a quick question for you. What''s the one thing you keep putting off? Hold that thought, because by the end of this episode, you''re going to start it.

Let''s get into it.',
   '[]'::jsonb, 60, 'podcast',
   '{"en": "You’re opening a new episode of your own podcast. Talk to one listener with headphones on, not to a crowd: relaxed and warm, with a smile in your voice.", "ko": "내 팟캐스트의 새 에피소드를 여는 장면이에요. 많은 사람이 아니라 이어폰을 낀 한 사람에게 말하듯, 편하고 다정하게, 목소리에 미소를 담아 말해 보세요.", "ja": "自分のポッドキャストの新しいエピソードを始める場面です。大勢ではなく、イヤホンで聴いているひとりに話しかけるように、リラックスして温かく、声に笑顔をのせてみましょう。", "de": "Du eröffnest eine neue Folge deines eigenen Podcasts. Sprich nicht zu einem Publikum, sondern zu einer Person mit Kopfhörern: locker, herzlich und mit einem Lächeln in der Stimme.", "es": "Abres un nuevo episodio de tu propio pódcast. No le hables a una multitud, sino a una persona con los auriculares puestos: con calma, con calidez y con una sonrisa en la voz.", "fr": "Tu ouvres un nouvel épisode de ton propre podcast. Ne parle pas à une foule, mais à une seule personne qui t’écoute avec ses écouteurs : sur un ton détendu et chaleureux, avec le sourire dans la voix.", "zh-Hant": "你正在為自己的 Podcast 開場新的一集。不是對一大群人，而是對戴著耳機的那一個人說話：輕鬆、溫暖，讓聲音帶著笑意。", "zh-Hans": "你正在为自己的播客开场新的一集。不是对一大群人，而是对戴着耳机的那一个人说话：轻松、温暖，让声音带着笑意。"}'::jsonb,
   null)
on conflict (id) do nothing;
