-- A REAL product launch: Steve Jobs introducing the iPhone, Macworld, 9 January
-- 2007, the opening in his words (transcript: singjupost.com) up to "here it
-- is". Years spelled the way he said them; a dash turned into commas.
-- Needs 20261104150000 (link) applied first.
insert into public.speech_challenges (id, language, title, genre, body, sources, target_seconds, category, intro, link)
values
  ('5beec000-0000-4000-8000-000000000026', 'en', 'We are calling it iPhone', 'product',
   'This is the day I''ve been looking forward to for two and a half years.

Every once in a while, a revolutionary product comes along that changes everything. And Apple has been, well, first of all, one''s very fortunate if you get to work on just one of these in your career. Apple has been very fortunate. It''s been able to introduce a few of these into the world.

In nineteen eighty-four, we introduced the Macintosh. It didn''t just change Apple. It changed the whole computer industry. In two thousand one, we introduced the first iPod. And it didn''t just change the way we all listen to music, it changed the entire music industry.

Well, today we''re introducing three revolutionary products of this class. The first one is a widescreen iPod with touch controls. The second is a revolutionary mobile phone. And the third is a breakthrough Internet communications device.

So, three things: a widescreen iPod with touch controls, a revolutionary mobile phone, and a breakthrough Internet communications device. An iPod, a phone, and an Internet communicator. An iPod, a phone... are you getting it? These are not three separate devices. This is one device, and we are calling it iPhone.

Today, Apple is going to reinvent the phone. And here it is.',
   '["Steve Jobs, iPhone introduction, Macworld 2007"]'::jsonb, 70, 'product_launch',
   '{"en": "Steve Jobs introducing the first iPhone in January 2007. Build the suspense: name the three products slowly, pause before the reveal, and say “we are calling it iPhone” as if the whole room is holding its breath.", "ko": "2007년 1월, 스티브 잡스가 첫 아이폰을 소개하는 장면이에요. 세 가지 제품은 하나씩 천천히, 공개 직전에는 잠깐 멈추고, “we are calling it iPhone”은 모두가 숨죽인 것처럼 말해 보세요.", "ja": "2007年1月、スティーブ・ジョブズが初代iPhoneを発表した場面です。三つの製品はひとつずつゆっくり、発表の直前で一呼吸おいて、「we are calling it iPhone」は会場中が息をのんでいるつもりで言ってみましょう。", "de": "Steve Jobs stellt im Januar 2007 das erste iPhone vor. Bau Spannung auf: Nenn die drei Produkte langsam, mach vor der Enthüllung eine Pause und sag „we are calling it iPhone“, als würde der ganze Saal den Atem anhalten.", "es": "Steve Jobs presenta el primer iPhone en enero de 2007. Crea expectativa: di los tres productos despacio, haz una pausa antes de revelarlo y di «we are calling it iPhone» como si toda la sala contuviera el aliento.", "fr": "Steve Jobs présente le premier iPhone en janvier 2007. Fais monter le suspense : annonce les trois produits lentement, marque une pause avant la révélation et dis « we are calling it iPhone » comme si toute la salle retenait son souffle.", "zh-Hant": "2007 年 1 月，賈伯斯發表第一支 iPhone。三樣產品一個一個慢慢說，揭曉前停一下，說「we are calling it iPhone」時，就像全場都屏住了呼吸。", "zh-Hans": "2007 年 1 月，乔布斯发布第一部 iPhone。三样产品一个一个慢慢说，揭晓前停一下，说“we are calling it iPhone”时，就像全场都屏住了呼吸。"}'::jsonb,
   'https://www.youtube.com/watch?v=x7qPAY9JqE4')
on conflict (id) do nothing;
