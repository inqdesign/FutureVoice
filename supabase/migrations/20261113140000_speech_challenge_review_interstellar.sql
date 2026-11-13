-- Speech challenge (founder, 2026-11-13): be a film YouTuber reviewing
-- Interstellar on a rewatch. Original script, written for nawana. Facts
-- checked the same day: Kip Thorne's equations behind the black hole and the
-- 2015 Classical and Quantum Gravity paper (James, von Tunzelmann, Franklin,
-- Thorne); the score's organ recorded at Temple Church, London; one hour on
-- Miller's planet is seven years on Earth; twenty-three years of messages;
-- 169 minutes. No ending spoilers. English Season 2: a challenge published
-- now lands in its draft season. No digits. The intro never asks for a slow
-- reading, because Season 2 scores speed. Read by a woman (founder: most
-- learners are women), and the picture draws one. `review` has no label in
-- the app yet, and an unknown category draws nothing.
insert into public.speech_challenges (id, language, title, genre, body, sources, target_seconds, category, intro, link, reference_voice)
values
  ('5beec000-0000-4000-8000-00000000002d', 'en', 'I rewatched Interstellar', 'explainer',
   'Hey everyone, welcome back. So, last night I rewatched Interstellar, for maybe the tenth time, and I need to talk about it, because it hit me harder than ever. No spoilers for the ending, I promise.

Quick setup. Earth is dying. Dust storms everywhere, crops failing, and a former pilot named Cooper leaves his kids behind to fly through a wormhole and find humanity a new home.

Now, what makes this movie special? First, the science is real. Christopher Nolan worked with the physicist Kip Thorne, and the black hole you see on screen was built from his equations. It looked so real that it ended up in scientific papers.

Second, the music. Hans Zimmer used a huge church organ, and when it kicks in during the docking scene, I swear, I forgot to breathe.

But here''s the scene that gets me every single time. They land on a planet where one hour equals seven years back on Earth. When Cooper gets back to the ship, twenty-three years of messages from his kids are waiting for him. He watches them grow up in a few minutes, and he can''t say a word back.

Is it perfect? No. Some of the dialogue is a bit heavy, and it''s almost three hours long. But I''ve never seen a movie make physics feel this personal.

So here''s my question for you. If you could send one message to someone across time, who would it be, and what would you say?',
   '[]'::jsonb, 95, 'review',
   '{"en": "You’re a film YouTuber who just rewatched Interstellar. Talk the way you would to a friend you want to see it, mean it when you get to that scene, and ask the last question like you’re waiting for the comments.", "ko": "영화 유튜버가 되어 인터스텔라를 다시 보고 리뷰해요. 좋아하는 영화를 친구에게 권하듯 신나게, 그 장면에서는 진심을 담아서, 마지막 질문은 댓글을 기다리듯이요.", "ja": "映画YouTuberになって、インターステラーを見返したレビューをします。好きな映画を友だちにすすめるように楽しく、あのシーンでは気持ちを込めて。最後の質問は、コメントを待っているつもりで。", "de": "Du machst Filmvideos auf YouTube und hast gerade Interstellar noch einmal gesehen. Erzähl es wie einer Freundin, die den Film unbedingt sehen soll, sprich die eine Szene mit Gefühl, und stell die letzte Frage so, als würdest du auf die Kommentare warten.", "es": "Tienes un canal de cine y acabas de volver a ver Interstellar. Cuéntalo como se lo contarías a una amiga a la que quieres convencer, pon el corazón en esa escena y haz la última pregunta como si esperaras los comentarios.", "fr": "Tu tiens une chaîne ciné et tu viens de revoir Interstellar. Raconte-le comme à une amie que tu veux convaincre, mets-y du cœur sur cette scène, et pose la dernière question comme si tu attendais les commentaires.", "zh-Hant": "你是電影 YouTuber，剛重看了《星際效應》。像跟朋友推薦愛看的電影一樣興奮地說，講到那一幕時要真心，最後的問題就像在等大家留言。", "zh-Hans": "你是电影博主，刚重看了《星际穿越》。像跟朋友安利喜欢的电影一样兴奋地说，讲到那一幕时要真心，最后的问题就像在等大家留言。"}'::jsonb,
   null, 'female')
on conflict (id) do nothing;
