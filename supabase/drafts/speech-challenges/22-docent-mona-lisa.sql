-- Speech challenge (founder, 2026-11-09): be the docent, a group in front of
-- the Mona Lisa. Original script, written for nawana. Facts checked against
-- Smithsonian, History Hit, Slate, Open Culture and CNN the same day. Written
-- for English Season 2: a challenge published now lands in its draft season.
-- No digits ("nineteen eleven"). The intro never asks for a slow reading,
-- because Season 2 scores speed. `docent` has no label in the app yet, and an
-- unknown category draws nothing.
insert into public.speech_challenges (id, language, title, genre, body, sources, target_seconds, category, intro, link)
values
  ('5beec000-0000-4000-8000-00000000002b', 'en', 'Come a little closer', 'explainer',
   'All right, everyone, come a little closer. Don''t be shy, there''s room at the front.

Most people are surprised by how small she is. And some of you are probably wondering, why this one? Why does the whole world come to see this painting, when there are bigger, brighter, more dramatic ones just down the hall?

Here''s the secret. For four hundred years, she was famous in the art world, and almost nowhere else. Then, on a quiet Monday morning in August of nineteen eleven, while the museum was closed, a man who had once worked here lifted her off the wall and walked out with the painting hidden under his work clothes.

How long do you think it took before anyone noticed she was gone? A full day.

And that is when everything changed. Newspapers around the world printed her face on the front page, so people who had never set foot in a museum suddenly knew exactly what she looked like. The police even questioned a young Pablo Picasso. And here, in this museum, crowds lined up just to stare at the empty space on the wall.

For more than two years, the whole world wondered where she was. So when she was finally found in Florence and brought back to Paris, she was no longer just a painting. She was the most famous face on earth.

So take one more look at that smile, and tell me: if no one had ever stolen her, would you be standing here today?',
   '[]'::jsonb, 90, 'docent',
   '{"en": "You’re a museum docent, and you’ve just gathered a group in front of the Mona Lisa. Tell it like a secret you can’t wait to share, talk to the faces in front of you, and ask the last question as if you really want an answer.", "ko": "미술관 도슨트가 되어 모나리자 앞에 관람객들을 모았어요. 눈앞의 사람들에게 말을 걸듯, 꼭 들려주고 싶던 비밀을 털어놓는 기분으로 읽어 보세요. 마지막 질문은 정말 대답을 기다리듯이요.", "ja": "美術館のドーセントになって、モナ・リザの前にお客さんを集めたところです。目の前の人たちに話しかけるように、とっておきの秘密を打ち明ける気分で読んでみましょう。最後の質問は、本当に答えを待っているつもりで。", "de": "Du führst durchs Museum und hast gerade eine Gruppe vor der Mona Lisa versammelt. Sprich die Leute direkt an, als würdest du ein Geheimnis verraten, und stell die letzte Frage so, als wolltest du wirklich eine Antwort.", "es": "Eres guía de museo y acabas de reunir a un grupo frente a la Mona Lisa. Háblales directamente, como quien cuenta un secreto que llevaba tiempo guardando, y haz la última pregunta como si de verdad esperaras una respuesta.", "fr": "Tu es guide de musée et tu viens de rassembler un groupe devant la Joconde. Parle aux gens en face de toi, comme si tu leur confiais un secret, et pose la dernière question comme si tu attendais vraiment une réponse.", "zh-Hant": "你是美術館的導覽員，剛把一群觀眾帶到蒙娜麗莎前面。對著眼前的人說話，像在分享一個忍不住想說的祕密；最後的問題，要像真的在等大家回答。", "zh-Hans": "你是美术馆的讲解员，刚把一群观众带到蒙娜丽莎面前。对着眼前的人说话，像在分享一个忍不住想说的秘密；最后的问题，要像真的在等大家回答。"}'::jsonb,
   null)
on conflict (id) do nothing;
