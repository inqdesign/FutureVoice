-- Speech challenge: a REAL acceptance speech (founder, 2026-11-04).
-- Michelle Yeoh, Best Actress, 95th Academy Awards, 12 March 2023, the
-- famous part in her own words (transcript: rev.com), cut short: the
-- thank-yous to the studio and crew and to her family in Hong Kong are left
-- out, "84" is spelled out and "KL" dropped (the scorer reads a digit or an
-- abbreviation more than one way). Excerpt + attribution, text only; retire
-- it if the rights holder asks. Runs after 20261104130000 (category, intro).
insert into public.speech_challenges (id, language, title, genre, body, sources, target_seconds, category, intro)
values
  ('5beec000-0000-4000-8000-000000000024', 'en', 'This is history in the making', 'person',
   'Thank you. Thank you.

For all the little boys and girls who look like me, watching tonight, this is the beacon of hope and possibilities. This is proof that dreams, dream big, and dreams do come true. And ladies, don''t let anybody tell you you are ever past your prime. Never give up.

I have to dedicate this to my mom, all the moms in the world, because they are really the superheroes. And without them, none of us will be here tonight.

She''s eighty-four, and I''m taking this home to her. She''s watching right now in Malaysia, with my family and friends. I love you guys. I''m bringing this home to you.

Thank you to the Academy. This is history in the making. Thank you.',
   '["Michelle Yeoh, Oscar acceptance speech (Best Actress), 2023, excerpt"]'::jsonb, 45,
   'acceptance',
   '{"en": "Michelle Yeoh’s speech from 2023, when she became the first Asian woman to win the Oscar for Best Actress. Picture the statue in your hand: say the first line to every kid watching, slow down when you get to your mom, and let the last line ring out.", "ko": "2023년, 아시아 여성 최초로 오스카 여우주연상을 받은 양자경의 수상 소감이에요. 트로피를 손에 든 순간처럼, 첫 문장은 지켜보는 아이들에게, 엄마 이야기는 천천히, 마지막 한 줄은 크게 말해 보세요.", "ja": "2023年、アジア人女性として初めてアカデミー主演女優賞を受けたミシェル・ヨーのスピーチです。トロフィーを手にしたつもりで、最初の一文は見ている子どもたちに、お母さんの話はゆっくり、最後の一言は力強く話してみましょう。", "de": "Michelle Yeohs Dankesrede von 2023, als sie als erste Asiatin den Oscar als beste Hauptdarstellerin gewann. Stell dir die Statue in deiner Hand vor: Sag den ersten Satz zu allen Kindern, die zuschauen, sprich langsamer, wenn es um deine Mutter geht, und lass den letzten Satz richtig klingen.", "es": "El discurso de Michelle Yeoh en 2023, cuando se convirtió en la primera mujer asiática en ganar el Óscar a mejor actriz. Imagina la estatuilla en tu mano: dile la primera frase a cada niño que te está viendo, habla más despacio cuando llegues a tu mamá y deja que la última frase resuene.", "fr": "Le discours de Michelle Yeoh en 2023, quand elle est devenue la première femme asiatique à remporter l’Oscar de la meilleure actrice. Imagine la statuette dans ta main : adresse la première phrase à tous les enfants qui regardent, ralentis quand tu parles de ta mère, et laisse la dernière phrase résonner.", "zh-Hant": "楊紫瓊在 2023 年成為第一位獲得奧斯卡最佳女主角的亞洲女性，這是她的得獎感言。想像獎座就在你手上：第一句說給正在看的孩子們聽，講到媽媽時放慢，最後一句大聲說出來。", "zh-Hans": "杨紫琼在 2023 年成为第一位获得奥斯卡最佳女主角的亚洲女性，这是她的获奖感言。想象奖杯就在你手上：第一句说给正在看的孩子们听，讲到妈妈时放慢，最后一句大声说出来。"}'::jsonb)
on conflict (id) do nothing;
