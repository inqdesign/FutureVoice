-- Speech challenge (founder, 2026-11-11): be the morning weather presenter,
-- a grey week ending in a sunny weekend. Original script, written for nawana;
-- a made-up forecast, no real place, date or broadcaster. English Season 2:
-- a challenge published now lands in its draft season. No digits, wind in
-- miles and temperature in Celsius as a British forecast says them. The
-- intro never asks for a slow reading, because Season 2 scores speed.
-- `weather` has no label in the app yet, and an unknown category draws nothing.
insert into public.speech_challenges (id, language, title, genre, body, sources, target_seconds, category, intro, link)
values
  ('5beec000-0000-4000-8000-00000000002c', 'en', 'Don''t put that umbrella away yet', 'explainer',
   'Good morning, everyone, and happy Friday. Let''s take a look at the weekend, because I have some good news, and I''m going to make you wait for it.

First, the not-so-good part. That band of rain that''s been sitting over us all week isn''t done yet. This morning we''re looking at heavy showers in the north and along the coast, with gusts of up to forty miles an hour by lunchtime. If you''re driving to work, give yourself a few extra minutes, and please, take the big umbrella, not the cute one.

This afternoon, temperatures will struggle to get past nine degrees, and tonight they''ll drop to around two, so if you have plants on the balcony, bring them inside.

Now, here''s the part you''ve been waiting for. Late tomorrow morning, a high pressure system moves in from the west and pushes all of this out to sea. By Saturday afternoon, we''re expecting clear blue skies, light winds, and highs of fifteen degrees. Sunday looks even better.

That''s right. After three gray weeks, the sun is finally coming back.

So, here''s my question for you. What are you going to do with the first sunny weekend in almost a month?',
   '[]'::jsonb, 75, 'weather',
   '{"en": "You’re the morning weather presenter, telling everyone getting ready for work what the weekend holds. Keep it bright and clear, and save the good news for the end.", "ko": "아침 방송 기상캐스터가 되어 주말 날씨를 전해요. 출근 준비하는 사람들에게 말하듯 밝고 또렷하게, 좋은 소식은 아껴 뒀다가 마지막에 풀어 주세요.", "ja": "朝の番組のお天気キャスターになって、週末の天気を伝えます。出かける準備をしている人に話しかけるように、明るくはっきりと。いい知らせは最後までとっておいてください。", "de": "Du moderierst das Wetter im Frühstücksfernsehen und sagst allen, die sich gerade für die Arbeit fertig machen, wie das Wochenende wird. Hell und klar, und die gute Nachricht hebst du dir bis zum Schluss auf.", "es": "Eres quien presenta el tiempo en el programa de la mañana y cuentas qué trae el fin de semana a quienes se preparan para salir. Con energía y claridad, y guarda la buena noticia para el final.", "fr": "Tu présentes la météo du matin et tu annonces le week-end à ceux qui se préparent à partir travailler. Avec entrain et clarté, et garde la bonne nouvelle pour la fin.", "zh-Hant": "你是晨間新聞的氣象主播，要告訴正在準備出門的大家週末天氣如何。語氣明亮清楚，好消息留到最後再說。", "zh-Hans": "你是早间新闻的天气预报员，要告诉正准备出门的大家周末天气怎么样。语气明快清楚，好消息留到最后再说。"}'::jsonb,
   null)
on conflict (id) do nothing;
