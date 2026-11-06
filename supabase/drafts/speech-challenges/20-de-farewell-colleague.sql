-- Speech challenge, de (2026-11-06): written for that language's board,
-- not translated from another. German board: a few words on a colleague's last day, before the cake, with du.
-- Original script. No digits ("sechs Jahren", "hundertmal").
insert into public.speech_challenges (id, language, title, genre, body, sources, target_seconds, category, intro, link)
values
  ('5beec000-0000-4000-8000-000000000029', 'de', 'Auf Anna!', 'person',
   'Liebe Kolleginnen und Kollegen, liebe Anna,

ich mache es kurz, denn ich weiß, der Kuchen wartet schon.

Heute ist dein letzter Tag bei uns, und ehrlich gesagt kann ich es mir noch gar nicht vorstellen. Seit fast sechs Jahren sitzt du am Fenster gegenüber von mir. Du warst immer die Erste im Büro, und du hattest immer eine Antwort, auch wenn sonst niemand eine hatte.

Ich erinnere mich noch an meine erste Woche hier. Ich war völlig verloren, und du hast gesagt: Keine Panik, wir kriegen das hin. Diesen Satz habe ich seitdem bestimmt hundertmal von dir gehört. Und weißt du was? Wir haben es jedes Mal hingekriegt.

Du wirst uns fehlen. Deine Geduld, dein trockener Humor und, ganz ehrlich, auch dein Apfelkuchen.

Für deinen neuen Job in Hamburg wünschen wir dir alles Gute. Die Kollegen dort wissen noch gar nicht, was für ein Glück sie haben.

Und jetzt bitte alle die Gläser hoch: Auf Anna!',
   '[]'::jsonb, 60, 'short_talk',
   '{"en": "It’s a colleague’s last day, and you’re saying a few words before the cake. Keep it light and personal: one memory, one joke, then everyone raises a glass. Colleagues in a German office say du to each other.", "ko": "동료의 마지막 출근날, 케이크를 자르기 전에 한마디 하는 장면이에요. 추억 하나, 농담 하나로 가볍지만 진심 있게, 마지막엔 다 같이 잔을 들어요. 독일 회사에서는 동료끼리 du로 말해요.", "ja": "同僚の最後の出勤日、ケーキの前にひと言スピーチをする場面です。思い出をひとつ、冗談をひとつ。軽く、でも心を込めて、最後は乾杯で締めましょう。ドイツの職場では、同僚同士は du で話します。", "de": "Heute ist der letzte Arbeitstag einer Kollegin, und du sagst vor dem Kuchen ein paar Worte. Locker und persönlich: eine Erinnerung, ein Witz, und zum Schluss die Gläser hoch.", "es": "Es el último día de una compañera de trabajo y dices unas palabras antes del pastel. Que sea ligero y personal: un recuerdo, una broma y, al final, todos levantan la copa. En una oficina alemana, los compañeros se hablan de du.", "fr": "C’est le dernier jour d’une collègue, et tu dis quelques mots avant le gâteau. Reste léger et personnel : un souvenir, une blague, puis tout le monde lève son verre. Dans un bureau allemand, les collègues se tutoient (du).", "zh-Hant": "今天是同事最後一天上班，切蛋糕前你要說幾句話。輕鬆又真誠：一段回憶、一個玩笑，最後大家一起舉杯。在德國的辦公室，同事之間用 du 稱呼彼此。", "zh-Hans": "今天是同事最后一天上班，切蛋糕前你要说几句话。轻松又真诚：一段回忆、一个玩笑，最后大家一起举杯。在德国的办公室，同事之间用 du 称呼彼此。"}'::jsonb,
   null)
on conflict (id) do nothing;
