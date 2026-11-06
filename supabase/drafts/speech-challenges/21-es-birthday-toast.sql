-- Speech challenge, es (2026-11-06): written for that language's board,
-- not translated from another. Spanish board: a brindis at a friend's thirtieth birthday dinner. Neutral
-- Spanish: tú to her, ustedes to the table, no vosotros. Original script.
insert into public.speech_challenges (id, language, title, genre, body, sources, target_seconds, category, intro, link)
values
  ('5beec000-0000-4000-8000-00000000002a', 'es', '¡Por Lucía!', 'person',
   '¿Me prestan atención un momento? Prometo que será breve.

Buenas noches a todos, y muchas gracias por venir a celebrar los treinta años de Lucía.

Para los que no me conocen: conozco a Lucía desde que teníamos seis años. Nos sentaron juntos en la escuela, y desde entonces no me ha dejado en paz. Y menos mal.

Lucía es esa amiga que llama justo cuando la necesitas. La que se acuerda de tu cumpleaños, aunque tú te olvides del suyo. Perdón, Lucía, eso fue solo una vez.

Hace unos años decidió dejar su trabajo para abrir su propia panadería. Todos le dijimos que estaba loca. Hoy hay gente esperando en la puerta todas las mañanas, así que, bueno, la loca tenía razón.

Lucía, gracias por tu risa, por tu paciencia y por todo el pan que nos regalas. Que los próximos treinta sean todavía mejores.

Así que, por favor, levanten sus copas. ¡Por Lucía! ¡Salud!',
   '[]'::jsonb, 60, 'short_talk',
   '{"en": "Your oldest friend is turning thirty, and you’re making the toast at dinner. Get everyone’s attention, tell one story, tease her a little, and end with the whole table raising their glasses.", "ko": "가장 오래된 친구의 서른 번째 생일, 저녁 자리에서 건배사를 하는 장면이에요. 모두의 주목을 모으고, 이야기 하나에 살짝 놀리기도 하다가, 마지막엔 다 같이 잔을 들어요.", "ja": "いちばん付き合いの長い友だちの三十歳の誕生日、ディナーで乾杯のスピーチをする場面です。みんなの注目を集めて、思い出話をひとつ、少しからかって、最後はみんなでグラスを上げましょう。", "de": "Deine älteste Freundin wird dreißig, und du hältst beim Abendessen den Toast. Hol dir die Aufmerksamkeit, erzähl eine Geschichte, zieh sie ein bisschen auf, und am Ende heben alle die Gläser.", "es": "Tu amiga de toda la vida cumple treinta años y te toca brindar en la cena. Pide la atención de todos, cuenta una anécdota, bromea un poco y termina con todos levantando las copas.", "fr": "Ta plus vieille amie fête ses trente ans, et c’est toi qui portes le toast au dîner. Capte l’attention de tout le monde, raconte une anecdote, taquine-la un peu, puis fais lever tous les verres.", "zh-Hant": "你認識最久的朋友滿三十歲了，晚餐時由你來敬酒致詞。先讓大家安靜下來，講一段往事，稍微調侃她一下，最後大家一起舉杯。", "zh-Hans": "你认识最久的朋友满三十岁了，晚餐时由你来敬酒致辞。先让大家安静下来，讲一段往事，稍微调侃她一下，最后大家一起举杯。"}'::jsonb,
   null)
on conflict (id) do nothing;
