-- Speech challenge (founder, 2026-11-16): the best friend's speech at a
-- wedding, the first of a wedding series. In all seven target languages, each
-- WRITTEN natively for that language's wedding (own names, own customs, own
-- close), never translated: drafted from the English idea, then rewritten by
-- a separate native pass per language. Read by a woman (most learners are
-- women) and the picture draws one (R2 + SpeechApp/Illustrations/
-- challenge-002E.png, uploaded for all seven ids). No digits, no em dashes,
-- no intro asks for a slow reading. Category `wedding` has no label in the
-- apps yet; an unknown key draws nothing. English lands in Season 2's draft,
-- the others in their language's live season, by the insert trigger.
--
-- ids: 5beec000-0000-4000-8000-0000000<L>002e, L = 00 en, 0a ja, 0b zh,
-- 0c ko, 0d de, 0e es, 0f fr.

-- en: English, the original. A maid-of-honor toast.
insert into public.speech_challenges (id, language, title, genre, body, sources, target_seconds, category, intro, link, reference_voice)
values
  ('5beec000-0000-4000-8000-00000000002e', 'en', 'Raise your glasses', 'person',
   'Hi everyone. For those who don''t know me, I''m Emma''s best friend, and I have known her since we were seven, when she walked up to me on the first day of school and said, "You can be my friend, but I get the swing."

She has been bossing me around ever since, and honestly? Best decision I never made.

Emma is the friend who remembers your coffee order, your mom''s birthday, and every embarrassing thing you said in two thousand twelve. She is also the friend who once got us lost for three hours because she "had a feeling" about a shortcut.

So when she called me last year and said, "I met someone, and I have a feeling," I was worried. Very worried.

But then I met Daniel. And I watched him listen to her tell a story he had already heard four times, laughing at all the right moments. And I thought, okay. This shortcut might actually lead somewhere.

Emma, you have held my hand through every breakup, every bad haircut, every move to a new city. You were always the first person I called. Today, I''m a little sad that I''m not your first call anymore. But I''m so, so happy that it''s him.

Daniel, take care of her. She will still get you lost. Just hold her hand while she does.

So please, everyone, raise your glasses. To Emma and Daniel, and to every shortcut that leads you home.',
   '[]'::jsonb, 90, 'wedding',
   '{"en": "You’re the bride’s best friend, giving a speech at her wedding. Make the room laugh first, then let it go quiet when you talk to her.", "ko": "신부의 가장 친한 친구가 되어 결혼식에서 축사를 해요. 처음엔 하객들을 웃기고, 친구에게 직접 말을 건넬 때는 식장이 조용해지도록 진심을 담아 보세요.", "ja": "新婦の親友として、結婚式でスピーチをします。まずは会場を笑わせて、新婦に語りかけるところでは、しんと静まるくらい気持ちを込めて。", "de": "Du bist die beste Freundin der Braut und hältst eine Rede auf ihrer Hochzeit. Bring den Saal erst zum Lachen, und wenn du sie direkt ansprichst, darf es ganz still werden.", "es": "Eres la mejor amiga de la novia y das un discurso en su boda. Primero haz reír a todos, y cuando le hables a ella, deja que el salón se quede en silencio.", "fr": "Tu es la meilleure amie de la mariée et tu fais un discours à son mariage. Fais d’abord rire la salle, puis laisse le silence s’installer quand tu t’adresses à elle.", "zh-Hant": "你是新娘最好的朋友，要在她的婚禮上致辭。先逗全場笑，對她說話的時候，讓整個會場安靜下來。", "zh-Hans": "你是新娘最好的朋友，要在她的婚礼上致辞。先把全场逗笑，对她说话的时候，让整个会场安静下来。"}'::jsonb,
   null, 'female')
on conflict (id) do nothing;

-- ko: Korean 축사: guests in 해요/합니다, the bride in 반말, closes on applause (no glasses raised in a Korean ceremony hall).
insert into public.speech_challenges (id, language, title, genre, body, sources, target_seconds, category, intro, link, reference_voice)
values
  ('5beec000-0000-4000-8000-0000000c002e', 'ko', '그네는 내가 먼저야', 'person',
   '안녕하세요. 저는 신부 지은이의 이십 년 지기 친구, 박소연입니다. 귀한 걸음 해 주신 하객 여러분, 진심으로 감사드립니다.

지은이를 처음 만난 건 초등학교 일 학년 입학식 날이었어요. 처음 보는 애가 제 앞에 오더니 이러더라고요. "너 나랑 친구 하자. 근데 그네는 내가 먼저야." 그날부터 지금까지, 저는 그네를 양보하며 살고 있습니다.

지은이는 친구 어머님 생신까지 챙기는, 정 많은 친구예요. 그런데 길치예요. 대학교 때 제주도에서 "나 지름길 알 것 같아" 한 마디에, 저희는 세 시간을 헤맸습니다.

그래서 작년에 지은이가 "나 누구 만났는데, 이번엔 느낌이 와" 했을 때, 솔직히 좀 무서웠어요. 그 느낌을 제가 알거든요.

그런데 민준 씨를 만나 보니 알겠더라고요. 지은이가 네 번째 하는 얘기를 처음 듣는 것처럼 웃으면서 들어 주는 사람이었어요. 아, 이번 지름길은 진짜 맞는 길이구나 싶었습니다.

지은아. 내가 헤어졌을 때도, 이사하고 혼자 울던 밤에도, 늘 네가 옆에 있었어. 무슨 일 생기면 제일 먼저 전화하는 사람이 너였는데, 이제 네 첫 번째 전화는 내가 아니겠다. 조금 서운해. 근데 그 사람이 민준 씨라서, 나 정말 기뻐.

민준 씨, 우리 지은이 잘 부탁드려요. 앞으로도 길은 자주 잃을 거예요. 그럴 때마다 손만 꼭 잡아 주세요.

두 사람이 함께 걷는 길이 언제나 집으로 이어지길 바라며, 하객 여러분, 신랑 신부에게 큰 박수 부탁드립니다. 감사합니다.',
   '[]'::jsonb, 90, 'wedding',
   '{"en": "You’re the bride’s best friend, giving a speech at her wedding. Make the room laugh first, then let it go quiet when you talk to her.", "ko": "신부의 가장 친한 친구가 되어 결혼식에서 축사를 해요. 처음엔 하객들을 웃기고, 친구에게 직접 말을 건넬 때는 식장이 조용해지도록 진심을 담아 보세요.", "ja": "新婦の親友として、結婚式でスピーチをします。まずは会場を笑わせて、新婦に語りかけるところでは、しんと静まるくらい気持ちを込めて。", "de": "Du bist die beste Freundin der Braut und hältst eine Rede auf ihrer Hochzeit. Bring den Saal erst zum Lachen, und wenn du sie direkt ansprichst, darf es ganz still werden.", "es": "Eres la mejor amiga de la novia y das un discurso en su boda. Primero haz reír a todos, y cuando le hables a ella, deja que el salón se quede en silencio.", "fr": "Tu es la meilleure amie de la mariée et tu fais un discours à son mariage. Fais d’abord rire la salle, puis laisse le silence s’installer quand tu t’adresses à elle.", "zh-Hant": "你是新娘最好的朋友，要在她的婚禮上致辭。先逗全場笑，對她說話的時候，讓整個會場安靜下來。", "zh-Hans": "你是新娘最好的朋友，要在她的婚礼上致辞。先把全场逗笑，对她说话的时候，让整个会场安静下来。"}'::jsonb,
   null, 'female')
on conflict (id) do nothing;

-- ja: Japanese 友人代表スピーチ: set order, no 忌み言葉 (別れ, 帰る, 最後, 重ね言葉), ends on the closing greeting, not 乾杯.
insert into public.speech_challenges (id, language, title, genre, body, sources, target_seconds, category, intro, link, reference_voice)
values
  ('5beec000-0000-4000-8000-0000000a002e', 'ja', '親友からの祝辞', 'person',
   '彩花さん、拓也さん、ご結婚おめでとうございます。ご両家の皆様にも、心よりお祝い申し上げます。新婦の小学校からの友人、中村由佳と申します。

彩花さんとは、小学一年生の入学式で出会いました。知らない女の子がずんずん歩いてきて、いきなり「友達になってあげる。でも、ブランコは私が先ね」。それ以来ずっと彩花さんのペースですが、それが私の人生で一番いい出会いでした。

彩花さんは、友達の好きな飲み物も、私が昔言った恥ずかしい一言も、ぜんぶ覚えている人です。そして修学旅行の京都で、「こっちのほうが近い気がする」と言って、私を三時間、路地裏に連れ回した人でもあります。

ですから去年、「すごく素敵な人に会ったの。なんか、そんな気がするの」と電話をもらったとき、正直、心配しました。あの「気がする」ですから。

でも、拓也さんに会って安心しました。拓也さんがもう聞いたことのある彩花さんの話を、ちゃんと笑うところで笑って、楽しそうに聞いていたんです。ああ、今度の近道は、ちゃんとたどり着く道だなと思いました。

彩花。受験の前の夜も、仕事でへこんだ日も、いつも電話に出てくれたよね。何かあると真っ先に電話するのは、彩花だった。これからは、彩花の一番は拓也さんだね。ちょっとだけ寂しいけど、それが拓也さんで、本当にうれしい。

拓也さん。彩花はこれからも、自信満々で近道をすると思います。そのときは、どうか手をつないで、一緒に歩いてあげてください。

お二人で歩く道が、どんな近道よりもあたたかい道になりますように。お二人の末永いお幸せを心よりお祈りして、お祝いの言葉とさせていただきます。本日は、本当におめでとうございます。',
   '[]'::jsonb, 90, 'wedding',
   '{"en": "You’re the bride’s best friend, giving a speech at her wedding. Make the room laugh first, then let it go quiet when you talk to her.", "ko": "신부의 가장 친한 친구가 되어 결혼식에서 축사를 해요. 처음엔 하객들을 웃기고, 친구에게 직접 말을 건넬 때는 식장이 조용해지도록 진심을 담아 보세요.", "ja": "新婦の親友として、結婚式でスピーチをします。まずは会場を笑わせて、新婦に語りかけるところでは、しんと静まるくらい気持ちを込めて。", "de": "Du bist die beste Freundin der Braut und hältst eine Rede auf ihrer Hochzeit. Bring den Saal erst zum Lachen, und wenn du sie direkt ansprichst, darf es ganz still werden.", "es": "Eres la mejor amiga de la novia y das un discurso en su boda. Primero haz reír a todos, y cuando le hables a ella, deja que el salón se quede en silencio.", "fr": "Tu es la meilleure amie de la mariée et tu fais un discours à son mariage. Fais d’abord rire la salle, puis laisse le silence s’installer quand tu t’adresses à elle.", "zh-Hant": "你是新娘最好的朋友，要在她的婚禮上致辭。先逗全場笑，對她說話的時候，讓整個會場安靜下來。", "zh-Hans": "你是新娘最好的朋友，要在她的婚礼上致辞。先把全场逗笑，对她说话的时候，让整个会场安静下来。"}'::jsonb,
   null, 'female')
on conflict (id) do nothing;

-- zh: Chinese 伴娘致辞: 各位来宾 opening, the window seat instead of a swing, no 分/散/离, closes on 举杯 with 新婚快乐、白头偕老.
insert into public.speech_challenges (id, language, title, genre, body, sources, target_seconds, category, intro, link, reference_voice)
values
  ('5beec000-0000-4000-8000-0000000b002e', 'zh', '她的感觉，这次对了', 'person',
   '各位来宾，各位亲友，大家好！我是新娘晓雨的闺蜜，也是今天的伴娘，苏静。

我和晓雨从一年级就认识了。开学第一天，她走到我面前说："你可以当我同桌，但是靠窗的位置归我。"从那天起，她就一直管着我，一管就是二十年。说实话，我挺乐意的。

晓雨是那种会记住你爱喝哪家奶茶、记住你妈妈生日的朋友。她也是那种会跟你说"我感觉这条小路肯定近"，然后带着你在山里绕了三个小时的朋友。

所以去年她给我打电话说："我遇到一个人，我感觉就是他。"我心里一紧。她的感觉，我是领教过的。

后来我见到了子默。晓雨给他讲一个他已经听过四遍的故事，他还是听得特别认真，每个笑点都笑得刚刚好。那一刻我就想，这一次，她的感觉终于对了。

晓雨，这么多年，我每次难过，每次剪坏头发，每次一个人去新的城市，你都在。我有什么事，第一个想到的永远是你。今天我有一点点舍不得，因为以后你第一个想到的，就不是我了。但我真的真的特别开心，那个人是他。

子默，晓雨就交给你了。她以后还是会带你走错路，没关系，你牵好她的手就行。

现在，请大家举起酒杯，祝晓雨和子默新婚快乐，白头偕老，以后这一路不管怎么走，都是回家的路！干杯！',
   '[]'::jsonb, 90, 'wedding',
   '{"en": "You’re the bride’s best friend, giving a speech at her wedding. Make the room laugh first, then let it go quiet when you talk to her.", "ko": "신부의 가장 친한 친구가 되어 결혼식에서 축사를 해요. 처음엔 하객들을 웃기고, 친구에게 직접 말을 건넬 때는 식장이 조용해지도록 진심을 담아 보세요.", "ja": "新婦の親友として、結婚式でスピーチをします。まずは会場を笑わせて、新婦に語りかけるところでは、しんと静まるくらい気持ちを込めて。", "de": "Du bist die beste Freundin der Braut und hältst eine Rede auf ihrer Hochzeit. Bring den Saal erst zum Lachen, und wenn du sie direkt ansprichst, darf es ganz still werden.", "es": "Eres la mejor amiga de la novia y das un discurso en su boda. Primero haz reír a todos, y cuando le hables a ella, deja que el salón se quede en silencio.", "fr": "Tu es la meilleure amie de la mariée et tu fais un discours à son mariage. Fais d’abord rire la salle, puis laisse le silence s’installer quand tu t’adresses à elle.", "zh-Hant": "你是新娘最好的朋友，要在她的婚禮上致辭。先逗全場笑，對她說話的時候，讓整個會場安靜下來。", "zh-Hans": "你是新娘最好的朋友，要在她的婚礼上致辞。先把全场逗笑，对她说话的时候，让整个会场安静下来。"}'::jsonb,
   null, 'female')
on conflict (id) do nothing;

-- de: German Trauzeugin speech: Liebe … liebe Gäste opening, the Abifeier, a hike, closes on Auf das Brautpaar.
insert into public.speech_challenges (id, language, title, genre, body, sources, target_seconds, category, intro, link, reference_voice)
values
  ('5beec000-0000-4000-8000-0000000d002e', 'de', 'Rede der Trauzeugin', 'person',
   'Liebe Lena, lieber Jonas, liebe Gäste,

für alle, die mich noch nicht kennen: Ich bin Sophie, Lenas Trauzeugin. Ich kenne Lena, seit wir sieben waren. Am ersten Schultag kam sie auf mich zu und sagte: „Du darfst meine Freundin sein. Aber die Schaukel gehört mir.“ Seitdem bestimmt sie, wo es langgeht. Und ehrlich gesagt? Das war die beste Entscheidung, die ich nie getroffen habe.

Lena merkt sich, wie du deinen Kaffee trinkst, wann deine Mutter Geburtstag hat und jeden peinlichen Satz von unserer Abifeier. Sie hat uns aber auch beim Wandern drei Stunden im Kreis geführt, weil sie bei einer Abkürzung „so ein Gefühl“ hatte.

Als sie mich letztes Jahr anrief und sagte: „Ich hab jemanden kennengelernt, und ich hab so ein Gefühl“, da war ich besorgt. Sehr besorgt.

Dann habe ich Jonas kennengelernt. Ich habe gesehen, wie er ihr zuhört, wenn sie eine Geschichte zum vierten Mal erzählt, und genau an den richtigen Stellen lacht. Und ich dachte: Okay. Diese Abkürzung führt vielleicht wirklich irgendwohin.

Lena, du warst bei jeder Trennung da, bei jedem missglückten Haarschnitt, bei jedem Umzug in eine neue Stadt. Du warst immer die Erste, die ich angerufen habe. Heute bin ich ein bisschen traurig, dass ich nicht mehr dein erster Anruf bin. Aber ich bin so, so froh, dass er es ist.

Jonas, pass gut auf sie auf. Sie wird dich trotzdem in die Irre führen. Halt dann einfach ihre Hand.

Und jetzt bitte ich euch alle: Erhebt eure Gläser. Auf Lena und Jonas, und auf jede Abkürzung, die nach Hause führt. Auf das Brautpaar!',
   '[]'::jsonb, 90, 'wedding',
   '{"en": "You’re the bride’s best friend, giving a speech at her wedding. Make the room laugh first, then let it go quiet when you talk to her.", "ko": "신부의 가장 친한 친구가 되어 결혼식에서 축사를 해요. 처음엔 하객들을 웃기고, 친구에게 직접 말을 건넬 때는 식장이 조용해지도록 진심을 담아 보세요.", "ja": "新婦の親友として、結婚式でスピーチをします。まずは会場を笑わせて、新婦に語りかけるところでは、しんと静まるくらい気持ちを込めて。", "de": "Du bist die beste Freundin der Braut und hältst eine Rede auf ihrer Hochzeit. Bring den Saal erst zum Lachen, und wenn du sie direkt ansprichst, darf es ganz still werden.", "es": "Eres la mejor amiga de la novia y das un discurso en su boda. Primero haz reír a todos, y cuando le hables a ella, deja que el salón se quede en silencio.", "fr": "Tu es la meilleure amie de la mariée et tu fais un discours à son mariage. Fais d’abord rire la salle, puis laisse le silence s’installer quand tu t’adresses à elle.", "zh-Hant": "你是新娘最好的朋友，要在她的婚禮上致辭。先逗全場笑，對她說話的時候，讓整個會場安靜下來。", "zh-Hans": "你是新娘最好的朋友，要在她的婚礼上致辞。先把全场逗笑，对她说话的时候，让整个会场安静下来。"}'::jsonb,
   null, 'female')
on conflict (id) do nothing;

-- es: Latin American brindis (Mexican-neutral, no vosotros): Buenas noches opening, closes on ¡Salud! ¡Que vivan los novios!
insert into public.speech_challenges (id, language, title, genre, body, sources, target_seconds, category, intro, link, reference_voice)
values
  ('5beec000-0000-4000-8000-0000000e002e', 'es', 'Brindis para Mariana', 'person',
   'Buenas noches a todos. Para quienes no me conocen, soy Valeria, la mejor amiga de Mariana. La conozco desde que teníamos siete años. El primer día de primaria se me acercó en el recreo y me dijo: "Puedes ser mi amiga, pero el columpio es mío." Y desde ese día no ha dejado de mandarme. La verdad, fue la mejor decisión que yo nunca tomé.

Mariana es la amiga que se acuerda de cómo tomas el café, del cumpleaños de tu mamá y de cada tontería que dijiste en la secundaria. También es la amiga que una vez nos tuvo perdidas tres horas en carretera porque "tenía un presentimiento" con un atajo. Así que cuando me llamó el año pasado y me dijo: "Conocí a alguien, y tengo un presentimiento", me preocupé. Pero mucho.

Luego conocí a Andrés. Lo vi escucharla contar una historia que ya le había contado cuatro veces, y reírse justo donde tocaba. Y pensé: bueno, a lo mejor este atajo sí lleva a algún lado.

Mariana, tú estuviste conmigo en cada corazón roto, en cada corte de pelo desastroso, en cada mudanza a una ciudad donde no conocía a nadie. Siempre fuiste la primera persona a la que yo llamaba. Hoy me da un poquito de tristeza saber que ya no voy a ser tu primera llamada. Pero estoy tan, tan feliz de que sea él.

Andrés, cuídamela mucho. Te va a seguir perdiendo, eso te lo garantizo. Nada más no le sueltes la mano mientras tanto.

Así que les pido a todos que levanten su copa. Por Mariana y Andrés, y por todos los atajos que terminan llevándonos a casa. ¡Salud! ¡Que vivan los novios!',
   '[]'::jsonb, 90, 'wedding',
   '{"en": "You’re the bride’s best friend, giving a speech at her wedding. Make the room laugh first, then let it go quiet when you talk to her.", "ko": "신부의 가장 친한 친구가 되어 결혼식에서 축사를 해요. 처음엔 하객들을 웃기고, 친구에게 직접 말을 건넬 때는 식장이 조용해지도록 진심을 담아 보세요.", "ja": "新婦の親友として、結婚式でスピーチをします。まずは会場を笑わせて、新婦に語りかけるところでは、しんと静まるくらい気持ちを込めて。", "de": "Du bist die beste Freundin der Braut und hältst eine Rede auf ihrer Hochzeit. Bring den Saal erst zum Lachen, und wenn du sie direkt ansprichst, darf es ganz still werden.", "es": "Eres la mejor amiga de la novia y das un discurso en su boda. Primero haz reír a todos, y cuando le hables a ella, deja que el salón se quede en silencio.", "fr": "Tu es la meilleure amie de la mariée et tu fais un discours à son mariage. Fais d’abord rire la salle, puis laisse le silence s’installer quand tu t’adresses à elle.", "zh-Hant": "你是新娘最好的朋友，要在她的婚禮上致辭。先逗全場笑，對她說話的時候，讓整個會場安靜下來。", "zh-Hans": "你是新娘最好的朋友，要在她的婚礼上致辞。先把全场逗笑，对她说话的时候，让整个会场安静下来。"}'::jsonb,
   null, 'female')
on conflict (id) do nothing;

-- fr: French témoin speech: Bonsoir à tous, tu with the couple, closes on Levons nos verres.
insert into public.speech_challenges (id, language, title, genre, body, sources, target_seconds, category, intro, link, reference_voice)
values
  ('5beec000-0000-4000-8000-0000000f002e', 'fr', 'Le discours de la témoin', 'person',
   'Bonsoir à tous.

Pour ceux qui ne me connaissent pas, je suis Léa, la témoin de Camille. On se connaît depuis nos sept ans. Le jour de la rentrée, elle est venue vers moi et elle m’a dit : « Tu peux être ma copine, mais la balançoire, c’est à moi. » Depuis, c’est toujours elle qui décide. Et franchement ? C’est la meilleure décision de ma vie, et ce n’est même pas moi qui l’ai prise.

Camille, c’est l’amie qui se souvient de ton café préféré, de l’anniversaire de ta mère, et de toutes les bêtises que tu as pu dire au lycée. C’est aussi celle qui nous a fait tourner en rond pendant trois heures en Bretagne parce qu’elle « sentait bien » un raccourci. Alors quand elle m’a appelée l’an dernier pour me dire : « J’ai rencontré quelqu’un, et je le sens bien », j’ai eu peur. Très peur.

Et puis j’ai rencontré Julien. Je l’ai vu écouter Camille raconter une histoire qu’il connaissait déjà par cœur, et rire pile au bon moment. Et je me suis dit : bon, pour une fois, le raccourci mène peut-être quelque part.

Camille, tu m’as tenu la main à chaque rupture, à chaque coupe de cheveux ratée, à chaque déménagement. Tu as toujours été la première personne que j’appelais. Aujourd’hui, je suis un peu triste de ne plus être ton premier appel. Mais je suis tellement, tellement heureuse que ce soit lui.

Julien, prends soin d’elle. Elle te perdra encore en route, c’est sûr. Alors tiens-lui la main pendant ce temps-là.

Levons nos verres à Camille et Julien, et à tous les raccourcis qui finissent par nous ramener chez nous.',
   '[]'::jsonb, 90, 'wedding',
   '{"en": "You’re the bride’s best friend, giving a speech at her wedding. Make the room laugh first, then let it go quiet when you talk to her.", "ko": "신부의 가장 친한 친구가 되어 결혼식에서 축사를 해요. 처음엔 하객들을 웃기고, 친구에게 직접 말을 건넬 때는 식장이 조용해지도록 진심을 담아 보세요.", "ja": "新婦の親友として、結婚式でスピーチをします。まずは会場を笑わせて、新婦に語りかけるところでは、しんと静まるくらい気持ちを込めて。", "de": "Du bist die beste Freundin der Braut und hältst eine Rede auf ihrer Hochzeit. Bring den Saal erst zum Lachen, und wenn du sie direkt ansprichst, darf es ganz still werden.", "es": "Eres la mejor amiga de la novia y das un discurso en su boda. Primero haz reír a todos, y cuando le hables a ella, deja que el salón se quede en silencio.", "fr": "Tu es la meilleure amie de la mariée et tu fais un discours à son mariage. Fais d’abord rire la salle, puis laisse le silence s’installer quand tu t’adresses à elle.", "zh-Hant": "你是新娘最好的朋友，要在她的婚禮上致辭。先逗全場笑，對她說話的時候，讓整個會場安靜下來。", "zh-Hans": "你是新娘最好的朋友，要在她的婚礼上致辞。先把全场逗笑，对她说话的时候，让整个会场安静下来。"}'::jsonb,
   null, 'female')
on conflict (id) do nothing;
