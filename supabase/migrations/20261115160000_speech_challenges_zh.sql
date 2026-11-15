-- Simplified Chinese becomes a selectable target language (2026-11-13), so it
-- gets its own Season 1 and the ten challenges English has, each WRITTEN in
-- Mandarin rather than translated (same rule as `20261010150000`,
-- `20261015160000`, `20261113160000`): the same role, shape, length and
-- ending, said the way that job is done in Chinese. Simplified characters
-- only, every number in characters, no Arabic digits. Same category key and
-- reference voice as each English original (null there reads as female).
-- Lengths sit near the Mandarin rate band's midpoint (`SpeechLibrary.rateBand`,
-- 230 to 260 characters a minute) times the English target_seconds.
--
-- Ids: ...0000000b00NN, NN the English original's last two digits.
--
--   * ...0000000b0001 is the bundled sample. Its title and body are
--     byte-identical to `builtInTitles["zh"]` / `builtInBodies["zh"]`. It can
--     NOT take the app's current id for it (`builtInId("zh")` =
--     ...00000000000b): that id is already the ENGLISH "Nervous? Say you're
--     excited" row (`20261018120000`), so an insert under it would be skipped
--     by `on conflict`. The app's suffix for "zh" has to move to
--     "0000000b0001" for the sample and this challenge to be one script.
--   * ...0000000b0005, the ageing study: the same claims as the other
--     languages' copies, checked again on 2026-11-15 (Amoruso et al., Nature
--     Aging, 10 Nov 2025: 86,149 people aged 51 to 90 in 27 countries; Bak et
--     al. 2014, Lothian Birth Cohort; Berggren et al. 2020, 11 weeks of
--     Italian). "更有可能", not "两倍": two is the odds ratio (2.11), the
--     relative risk is 1.43.
--   * ...0000000b000b, Brooks 2014 (J Exp Psychol Gen 143(3)): "I am excited"
--     said aloud before a speech, raters judged those speakers more confident
--     and persuasive; the anxiety stayed. The caveat about later studies is
--     the English row's, naming none.
--   * ...0000000b0010, the cabin announcement in the Chinese airline register
--     (女士们、先生们 / 请您 / 我谨代表机长和全体机组人员). The airline is the
--     app's own name, written 纳瓦纳航空 so the scorer has characters to read;
--     no flight number. Beijing to London about eleven hours (CA937 is
--     scheduled at 11 h 05 min).
--   * ...0000000b0020, home-shopping night cream: a made-up product (晨露晚霜),
--     the TV-shopping register (各位观众朋友们 / 拨打屏幕下方的电话).
--   * ...0000000b0024, acceptance: NOT Michelle Yeoh's speech. An original
--     speech for a fictional actress, the first from her small county town
--     to win Best Actress. No real names, ceremony, film or place.
--   * ...0000000b0025, podcast host, an original show (《小小胜利》) and the
--     five-minute rule. No facts.
--   * ...0000000b002b, the Mona Lisa docent. Checked 2026-11-15 (History Hit,
--     History.com): stolen Monday 21 August 1911 while the Louvre was closed,
--     by a former Louvre worker (Peruggia) who hid it under his work smock;
--     missed until the next day; Picasso questioned; found in Florence in
--     December 1913, back in Paris in January 1914.
--   * ...0000000b002c, the weather presenter, a made-up forecast with no real
--     place or date, in Chinese forecast phrasing (雨带 / 阵风可达八级 /
--     东移入海 / 最高气温). Forty miles an hour is about 17.9 m/s, Beaufort 8.
--   * ...0000000b002d, the film critic, keeping the mainland title
--     《星际穿越》. Checked 2026-11-15: the black hole was rendered from Kip
--     Thorne's equations and published (James, von Tunzelmann, Franklin,
--     Thorne, Class. Quantum Grav. 32 065001, 2015); the organ is Temple
--     Church's in London (Roger Sayer); one hour on the planet is seven years
--     on Earth; twenty-three years of messages; 169 minutes. No ending spoilers.
--
-- Intros: written for each challenge in all eight app languages; the five
-- later roles (show host, podcast, docent, weather, film critic) reuse the
-- English row's intro, which describes the role, not the language. None asks
-- for a slow reading.
--
-- New rows go to the language's newest season (`speech_challenge_set_season`),
-- which is the Season 1 inserted first.


insert into public.speech_seasons (language, season, min_scoring, opened_at)
values ('zh', 1, 2, now())
on conflict (language, season) do nothing;

insert into public.speech_challenges (id, language, title, genre, body, sources, target_seconds, category, intro, link, reference_voice)
values
  ('5beec000-0000-4000-8000-0000000b0001', 'zh', '为什么要大声练？', 'explainer',
   '你有没有过这样的经历？一句话在脑子里明明想得好好的，一说出口就乱了。

说话是一种技能，不只是知识。单词和语法你都懂，可是如果你的嘴从来没有真正把这句话说过一遍，到了关键时刻，它就会卡住。所以，练习一定要出声。

大声说出来，也更容易记住。有研究发现，我们对自己说过的话，比只看过的内容记得更牢。

再给自己录个音听听，你会发现很多平时注意不到的东西：自己说话到底有多快，“嗯”“呃”说了多少次，一句话说到最后，声音是不是越来越小。

做报告、参加面试，哪怕是第一次跟陌生人聊天，练得越多就越轻松。你刚才大声读完这段话的这一分钟，就是你的第一次练习。',
   '[]'::jsonb, 60, 'short_talk',
   '{"en": "A short talk on why practice has to happen out loud. Talk as if you’re winning the room over, and give the last line a little smile.", "ko": "왜 소리 내어 연습해야 하는지 들려주는 짧은 강연이에요. 듣는 사람을 설득하듯 말하고, 마지막 문장은 살짝 웃으면서 마무리해 보세요.", "ja": "なぜ声に出して練習するのかを伝える、短いトークです。聞いている人を説得するつもりで話し、最後の一文は少し笑顔で締めくくってみましょう。", "de": "Ein kurzer Vortrag darüber, warum man laut üben muss. Sprich so, als wolltest du dein Publikum überzeugen, und sag den letzten Satz mit einem kleinen Lächeln.", "es": "Una charla breve sobre por qué hay que practicar en voz alta. Habla como si quisieras convencer al público y di la última frase con una pequeña sonrisa.", "fr": "Un court exposé sur pourquoi il faut s’entraîner à voix haute. Parle comme si tu voulais convaincre ton public, et dis la dernière phrase avec un petit sourire.", "zh-Hant": "一段短短的分享，講為什麼練習一定要出聲。像要說服台下的人一樣說，最後一句帶點笑意收尾。", "zh-Hans": "一段简短的分享，讲为什么练习一定要出声。像要说服台下的人一样说，最后一句带点笑意收尾。"}'::jsonb,
   null, 'female'),

  ('5beec000-0000-4000-8000-0000000b0005', 'zh', '学外语能让人老得慢一点吗？', 'explainer',
   '你可能听过这种说法：学一门外语，能让人老得慢一点。听起来好得有点不像真的，那我们就来看看，研究到底是怎么说的。

二〇二五年，学术期刊《自然·衰老》发表了一项很大的研究。研究人员分析了欧洲二十七个国家、八万六千多名五十一岁到九十岁的人。结果发现，只会说一种语言的人，更有可能老得比预期快。而且，会说的语言越多，这种风险就越低。

不过，有一点一定要注意。这类研究只能说明两者有关联，不能证明谁是原因。会说好几种语言的人，在别的方面可能本来就不一样。

那么，年纪大了再开始学，还有用吗？苏格兰的一项研究发现，成年以后才学第二语言的人，到了老年，表现也比他们小时候的测试成绩预测的要好。可是在瑞典的一项实验里，老人们上了十一周意大利语课，记忆力并没有变化。

说实话，现在还没有确定的答案。但是，一门新的语言会给你一个理由，去跟新的人说话。这总不会有坏处吧。',
   '["https://doi.org/10.1038/s43587-025-01000-2", "https://doi.org/10.1002/ana.24158"]'::jsonb, 75, 'short_talk',
   '{"en": "A short talk on what the research really says about languages and ageing. Sound curious rather than certain, as if you’re weighing the evidence with your listeners, and end on a warm note.", "ko": "언어와 노화에 대해 연구가 실제로 뭐라고 하는지 전하는 짧은 강연이에요. 단정하지 말고 궁금해하는 목소리로, 듣는 사람과 함께 근거를 따져 보듯 말하고, 마지막은 따뜻하게 마무리해 보세요.", "ja": "言語と老化について、研究が本当は何と言っているのかを伝える短いトークです。言い切らずに、聞き手と一緒に根拠を確かめるように話し、最後は温かく締めくくりましょう。", "de": "Ein kurzer Vortrag darüber, was die Forschung wirklich über Sprachen und das Altern sagt. Klinge neugierig statt sicher, als würdest du die Belege gemeinsam mit deinem Publikum abwägen, und hör mit einem warmen Satz auf.", "es": "Una charla breve sobre lo que de verdad dice la investigación sobre los idiomas y el envejecimiento. Habla con curiosidad, no con certeza, como si sopesaras las pruebas junto con tu público, y termina con calidez.", "fr": "Un court exposé sur ce que la recherche dit vraiment des langues et du vieillissement. Parle avec curiosité plutôt qu’avec certitude, comme si tu pesais les preuves avec ton public, et termine sur une note chaleureuse.", "zh-Hant": "一段短短的分享，談研究對語言和老化到底怎麼說。別說得太篤定，像跟聽眾一起掂量證據那樣帶著好奇去說，最後一句說得溫暖一點。", "zh-Hans": "一段简短的分享，谈研究对语言和衰老到底怎么说。别说得太笃定，像跟听众一起掂量证据那样带着好奇去说，最后一句说得温暖一点。"}'::jsonb,
   null, 'female'),

  ('5beec000-0000-4000-8000-0000000b000b', 'zh', '紧张的时候，就说你很兴奋', 'explainer',
   '心跳得飞快，手心冰凉，马上就要当着大家的面讲话了。这种时候，我们大多会对自己说同一句话：冷静，冷静。可如果这句话恰恰是错的呢？

二〇一四年，哈佛商学院的研究者艾莉森·伍德·布鲁克斯做了一个实验。她请参加的人对着摄像机做一段简短的演讲。开始之前，一部分人要大声说：“我很平静。”另一部分人要说：“我很兴奋。”

然后，再请别人看这些视频来打分。结果，说了“我很兴奋”的人，看起来更自信，也更有说服力。

为什么一句话就能带来不同？因为紧张和兴奋，在身体里的感觉几乎一样，心跳都会加快。让自己平静下来很难，可是给同一种感觉换个名字，却很容易。

不过也要说清楚，紧张并没有消失，大家还是会焦虑。而且后来的研究，也不是每次都得出同样的结果，所以这不是什么魔法。

但是试一试又不花钱。按下录制键之前，先说一遍：我很兴奋。',
   '["https://doi.org/10.1037/a0035325"]'::jsonb, 75, 'short_talk',
   '{"en": "A short talk about a one-sentence trick for stage nerves. Tell the racing heart like you’ve been there, the study like a story, and say the last line as if you’re about to press record.", "ko": "무대 앞 긴장을 다루는 한 문장짜리 요령에 관한 짧은 강연이에요. 쿵쾅거리는 심장은 겪어 본 사람처럼, 실험은 이야기처럼 들려주고, 마지막 한마디는 지금 막 녹화 버튼을 누르려는 사람처럼 말해 보세요.", "ja": "本番前の緊張に効く、ひとことのコツについての短いトークです。ドキドキする心臓は自分の経験のように、実験は物語のように話し、最後のひとことは今まさに録画ボタンを押すつもりで言ってみましょう。", "de": "Ein kurzer Vortrag über einen Ein-Satz-Trick gegen Lampenfieber. Erzähl vom rasenden Herzen, als hättest du es selbst erlebt, von der Studie wie von einer Geschichte, und sag den letzten Satz, als würdest du gleich auf Aufnahme drücken.", "es": "Una charla breve sobre un truco de una sola frase contra los nervios de hablar en público. Cuenta lo del corazón acelerado como algo que has vivido, el estudio como una historia, y di la última frase como si fueras a pulsar el botón de grabar.", "fr": "Un court exposé sur une astuce d’une seule phrase contre le trac. Raconte le cœur qui s’emballe comme si tu l’avais vécu, l’étude comme une histoire, et dis la dernière phrase comme si tu allais appuyer sur « enregistrer ».", "zh-Hant": "一段短短的分享，講一句話就能對付上台緊張的小方法。心跳加速那段，說得像自己經歷過；實驗像講故事一樣講；最後一句，就像你正要按下錄影鍵。", "zh-Hans": "一段简短的分享，讲一句话就能对付上台紧张的小方法。心跳加速那段，说得像自己经历过；实验像讲故事一样讲；最后一句，就像你正要按下录制键。"}'::jsonb,
   null, 'female'),

  ('5beec000-0000-4000-8000-0000000b0010', 'zh', '女士们、先生们，欢迎登机', 'briefing',
   '女士们、先生们，晚上好！欢迎您乘坐纳瓦纳航空的航班，由北京前往伦敦。

现在，客舱门已经关闭。请您系好安全带，调直座椅靠背，收起小桌板。

请将手机等便携式电子设备调至飞行模式。笔记本电脑等较大的电子设备，起飞期间请放在头顶上方的行李架内，或前排座椅下方。

稍后，乘务员将为您介绍机上的安全设备。请您留意离您最近的紧急出口，它可能就在您的身后。

从北京到伦敦的飞行时间大约是十一个小时。起飞后不久，我们将为您提供晚餐和饮料。

本次航班全程禁烟，包括洗手间在内，客舱内任何地方都请不要吸烟。

我谨代表机长和全体机组人员，感谢您选择纳瓦纳航空。请您坐好，放松，祝您旅途愉快！',
   '[]'::jsonb, 60, 'in_flight',
   '{"en": "You’re the cabin crew, making the welcome announcement before take-off. Keep that calm, polished airline voice, warm but formal, with every instruction clear to the whole cabin.", "ko": "이륙 전 환영 방송을 하는 승무원이 되어 보세요. 차분하고 정돈된 항공사 말투로, 따뜻하지만 격식 있게, 꽉 찬 객실의 모든 손님이 알아듣도록 또렷하게 말해 보세요.", "ja": "離陸前のウェルカムアナウンスをする客室乗務員になってみましょう。落ち着いた、整った航空会社の話し方で、温かく、それでいて丁寧に。満席の機内の誰にでも伝わるように、はっきりと。", "de": "Du gehörst zur Crew und machst die Begrüßungsdurchsage vor dem Start. Ruhig und souverän im typischen Ton einer Airline, herzlich, aber förmlich, und jede Anweisung so klar, dass die ganze Kabine sie versteht.", "es": "Formas parte de la tripulación y das el anuncio de bienvenida antes del despegue. Mantén esa voz tranquila y cuidada de aerolínea, cálida pero formal, con cada indicación clara para toda la cabina.", "fr": "Tu fais partie de l’équipage et tu passes l’annonce de bienvenue avant le décollage. Garde cette voix calme et soignée des compagnies aériennes, chaleureuse mais formelle, avec chaque consigne claire pour toute la cabine.", "zh-Hant": "你是空服員，要在起飛前做歡迎廣播。用沉穩、端正的航空公司語氣，親切又正式，每一句提醒都要讓整個客艙聽得清清楚楚。", "zh-Hans": "你是乘务员，要在起飞前做欢迎广播。用沉稳、规范的航空公司语气，亲切又正式，每一句提醒都要让整个客舱听得清清楚楚。"}'::jsonb,
   null, 'female'),

  ('5beec000-0000-4000-8000-0000000b0020', 'zh', '一觉醒来，皮肤会发光', 'product',
   '各位观众朋友们，先看看我的脸。凑近一点看。没有滤镜，没有粉底，这就是我忙了一整天以后，最真实的皮肤。

两个星期前，我的皮肤还特别累。鼻子周围发干，脸颊粗粗的，一笑，眼角就是小细纹。是不是很熟悉？

这就是晨露晚霜。看我怎么用。洗完脸，取豌豆那么大一点，在指尖揉开，然后按压。别搓，是按。额头、脸颊、下巴，眼下也带一点。

感觉到有多轻薄了吗？淡淡的黄瓜香，一抹就像水一样化开。不粘枕头，脸也不油。

你睡着了，它还在工作。整夜锁住水分，第二天一早，皮肤又软又嫩又滑，上妆像丝绸一样服帖。说实话，有些早上我连妆都不化了。

今晚下单，大瓶装一瓶，再送旅行装一支，外加一支眼霜。买一送二！

你的皮肤每天都在为你辛苦，给它一个好好的夜晚吧。赶快拨打屏幕下方的电话订购！',
   '[]'::jsonb, 60, 'show_host',
   '{"en": "You’re a home-shopping host, live on air, selling one night cream. Look straight into the camera, show off your own skin with confidence, and talk as if the phones won’t stop ringing.", "ko": "생방송 홈쇼핑 쇼호스트가 되어 나이트 크림 하나를 파는 장면이에요. 카메라를 똑바로 보고, 내 피부를 보여주듯 자신 있게, 주문 전화가 쏟아지는 것처럼 말해 보세요.", "ja": "生放送のテレビ通販で、ナイトクリームをひとつ売り込む場面です。カメラをまっすぐ見て、自分の肌を見せるように自信を持って、注文の電話が鳴りやまない勢いで話してみましょう。", "de": "Du moderierst live im Teleshopping und verkaufst eine Nachtcreme. Schau direkt in die Kamera, zeig selbstbewusst deine eigene Haut und sprich, als würden die Telefone gar nicht mehr stillstehen.", "es": "Presentas un programa de teletienda en vivo y vendes una crema de noche. Mira directo a la cámara, presume de tu piel con seguridad y habla como si los teléfonos no pararan de sonar.", "fr": "Tu animes une émission de téléachat en direct et tu vends une crème de nuit. Regarde la caméra droit dans les yeux, montre ta peau avec assurance et parle comme si les téléphones n’arrêtaient pas de sonner.", "zh-Hant": "你是電視購物的直播主持人，要賣一款晚霜。直視鏡頭，自信地秀出自己的皮膚，講得像訂購電話響個不停一樣。", "zh-Hans": "你是电视购物的直播主持人，要卖一款晚霜。直视镜头，自信地展示自己的皮肤，讲得像订购电话响个不停一样。"}'::jsonb,
   null, 'female'),

  ('5beec000-0000-4000-8000-0000000b0024', 'zh', '这一刻，会被写进历史', 'person',
   '谢谢！谢谢大家！

说实话，我准备了一份稿子，可现在一个字都想不起来了。

我十九岁第一次进剧组，演一个连名字都没有的路人，只有一句台词：“小心，车来了。”那一句话，我对着镜子练了一百遍。所以今天，我想对所有正坐在电视机前，觉得自己太普通、太晚、不够好的人说：没有一句台词是白练的。

谢谢我们的导演。所有人都在犹豫的时候，是你说了一句：就是她了。谢谢剧组的每一位演员和工作人员，那个冬天，我们在零下二十度的雪地里，一起熬过了四十个夜晚。

这个奖，我要献给我的妈妈。她今年八十岁了，一辈子几乎没进过电影院，因为她总说票太贵。可是我演的每一部戏，她都在电视上看了不止一遍。妈，今天别心疼钱了，这个奖杯，我亲手给你带回家。

还有我的女儿，你今年七岁，要是现在还没睡，记住妈妈这句话：梦想不怕晚，就怕你不去试。

我是从我们那个小县城走出来、第一个站上这个舞台的女演员。今天站在这里，不只是为了我自己，也是为了每一个被人说过“你不行”的女孩。这一刻，会被写进历史。谢谢大家！',
   '[]'::jsonb, 90, 'acceptance',
   '{"en": "An original acceptance speech, written for nawana: you’re a fictional actress who has just won Best Actress, the first from her small hometown. Picture the trophy in your hand, laugh about the speech you forgot, put your heart into the words for your mom, and let the last line ring out.", "ko": "나와나가 새로 쓴 수상 소감이에요. 작은 고향에서 처음으로 여우주연상을 받은 가상의 배우가 되어 보세요. 트로피를 손에 든 것처럼, 잊어버린 원고 이야기는 웃으며, 엄마 이야기에는 진심을 담아, 마지막 한 줄은 크게 말해 보세요.", "ja": "nawanaのために書き下ろした受賞スピーチです。小さな故郷から初めて主演女優賞を受けた、架空の女優になってみましょう。トロフィーを手にしたつもりで、忘れた原稿の話は笑いながら、お母さんの話には心を込めて、最後の一言は力強く。", "de": "Eine eigens für nawana geschriebene Dankesrede: Du bist eine erfundene Schauspielerin, die gerade als Erste aus ihrer kleinen Heimatstadt den Preis als beste Hauptdarstellerin gewonnen hat. Stell dir die Trophäe in deiner Hand vor, lach über die vergessene Rede, leg dein Herz in die Worte an deine Mutter, und lass den letzten Satz richtig klingen.", "es": "Un discurso de agradecimiento original, escrito para nawana: eres una actriz ficticia que acaba de ganar el premio a mejor actriz, la primera de su pequeño pueblo. Imagina el trofeo en tu mano, ríete del discurso que se te olvidó, pon el corazón en las palabras para tu mamá y deja que la última frase resuene.", "fr": "Un discours de remerciement original, écrit pour nawana : tu es une actrice imaginaire qui vient de remporter le prix de la meilleure actrice, la première de sa petite ville natale. Imagine le trophée dans ta main, ris du discours que tu as oublié, mets tout ton cœur dans les mots pour ta mère, et laisse la dernière phrase résonner.", "zh-Hant": "這是 nawana 原創的得獎感言。你是一位虛構的女演員，剛拿下最佳女主角，也是從家鄉小縣城走出來的第一個。想像獎座就在手上：忘詞那段笑著說，講到媽媽時用心說，最後一句大聲說出來。", "zh-Hans": "这是 nawana 原创的获奖感言。你是一位虚构的女演员，刚拿下最佳女主角，也是从家乡小县城走出来的第一个。想象奖杯就在手上：忘词那段笑着说，讲到妈妈时用心说，最后一句大声说出来。"}'::jsonb,
   null, 'female'),

  ('5beec000-0000-4000-8000-0000000b0025', 'zh', '欢迎回到我们的节目', 'explainer',
   '嗨，大家好，欢迎回到《小小胜利》，一档专门聊那些悄悄改变生活的小事的节目。我是主播，很高兴你又来了。

泡杯咖啡，把脚翘起来，今天这期很值得听。我们来聊聊“五分钟法则”。是这样的：当你不想做一件事的时候，就跟自己说，我就做五分钟。就五分钟，做完就可以停。

好玩的是，你几乎从来不会停。因为最难的从来不是做，而是开始。

上个月，我拿跑步试了试。我讨厌跑步，真的。可是每天早上我都跟自己说，五分钟，就绕小区跑一圈。结果你猜怎么着？今天早上我跑了半个小时，自己都没发觉。

今天，我请来了一位嘉宾，她就是靠这个小办法，写完了一整本书。不过在那之前，先问你一个问题：有哪件事，你一直在往后拖？先记住它，因为这期节目听完，你就要开始做了。

我们开始吧。',
   '[]'::jsonb, 60, 'podcast',
   '{"en": "You’re opening a new episode of your own podcast. Talk to one listener with headphones on, not to a crowd: relaxed and warm, with a smile in your voice.", "ko": "내 팟캐스트의 새 에피소드를 여는 장면이에요. 많은 사람이 아니라 이어폰을 낀 한 사람에게 말하듯, 편하고 다정하게, 목소리에 미소를 담아 말해 보세요.", "ja": "自分のポッドキャストの新しいエピソードを始める場面です。大勢ではなく、イヤホンで聴いているひとりに話しかけるように、リラックスして温かく、声に笑顔をのせてみましょう。", "de": "Du eröffnest eine neue Folge deines eigenen Podcasts. Sprich nicht zu einem Publikum, sondern zu einer Person mit Kopfhörern: locker, herzlich und mit einem Lächeln in der Stimme.", "es": "Abres un nuevo episodio de tu propio pódcast. No le hables a una multitud, sino a una persona con los auriculares puestos: con calma, con calidez y con una sonrisa en la voz.", "fr": "Tu ouvres un nouvel épisode de ton propre podcast. Ne parle pas à une foule, mais à une seule personne qui t’écoute avec ses écouteurs : sur un ton détendu et chaleureux, avec le sourire dans la voix.", "zh-Hant": "你正在為自己的 Podcast 開場新的一集。不是對一大群人，而是對戴著耳機的那一個人說話：輕鬆、溫暖，讓聲音帶著笑意。", "zh-Hans": "你正在为自己的播客开场新的一集。不是对一大群人，而是对戴着耳机的那一个人说话：轻松、温暖，让声音带着笑意。"}'::jsonb,
   null, 'female'),

  ('5beec000-0000-4000-8000-0000000b002b', 'zh', '大家再往前站一点', 'explainer',
   '好了，各位，大家再往前站一点。别不好意思，前面还有地方。

很多人第一次看到她，都会吃一惊：原来这么小啊。可能也有人在想，为什么偏偏是这一幅？走廊那头明明有更大、更亮、更有戏剧性的画，为什么全世界的人都跑来看她？

告诉大家一个秘密。四百年来，她只在艺术圈里有名，出了这个圈子，几乎没人知道。直到一九一一年八月，一个安静的星期一早上，博物馆正好闭馆，一个曾经在这里干过活的男人，把她从墙上取下来，藏在工作服底下，就这么走了出去。

大家猜猜，过了多久才有人发现她不见了？整整一天。

就是从那时候起，一切都变了。世界各地的报纸把她的脸印在头版上，那些从来没进过博物馆的人，突然都知道她长什么样。警察甚至还找年轻的毕加索问过话。而在这座博物馆里，人们排着长队，就为了看一眼墙上空出来的那块地方。

两年多的时间里，全世界都在猜她去了哪儿。所以，当她终于在佛罗伦萨被找到，又被送回巴黎的时候，她已经不只是一幅画了。她成了地球上最有名的一张脸。

所以，请大家再看一眼那个微笑，然后告诉我：要是当年没人偷走她，你今天还会站在这里吗？',
   '["https://www.historyhit.com/culture/theft-mona-lisa/", "https://www.history.com/articles/the-heist-that-made-the-mona-lisa-famous"]'::jsonb, 90, 'docent',
   '{"en": "You’re a museum docent, and you’ve just gathered a group in front of the Mona Lisa. Tell it like a secret you can’t wait to share, talk to the faces in front of you, and ask the last question as if you really want an answer.", "ko": "미술관 도슨트가 되어 모나리자 앞에 관람객들을 모았어요. 눈앞의 사람들에게 말을 걸듯, 꼭 들려주고 싶던 비밀을 털어놓는 기분으로 읽어 보세요. 마지막 질문은 정말 대답을 기다리듯이요.", "ja": "美術館のドーセントになって、モナ・リザの前にお客さんを集めたところです。目の前の人たちに話しかけるように、とっておきの秘密を打ち明ける気分で読んでみましょう。最後の質問は、本当に答えを待っているつもりで。", "de": "Du führst durchs Museum und hast gerade eine Gruppe vor der Mona Lisa versammelt. Sprich die Leute direkt an, als würdest du ein Geheimnis verraten, und stell die letzte Frage so, als wolltest du wirklich eine Antwort.", "es": "Eres guía de museo y acabas de reunir a un grupo frente a la Mona Lisa. Háblales directamente, como quien cuenta un secreto que llevaba tiempo guardando, y haz la última pregunta como si de verdad esperaras una respuesta.", "fr": "Tu es guide de musée et tu viens de rassembler un groupe devant la Joconde. Parle aux gens en face de toi, comme si tu leur confiais un secret, et pose la dernière question comme si tu attendais vraiment une réponse.", "zh-Hant": "你是美術館的導覽員，剛把一群觀眾帶到蒙娜麗莎前面。對著眼前的人說話，像在分享一個忍不住想說的祕密；最後的問題，要像真的在等大家回答。", "zh-Hans": "你是美术馆的讲解员，刚把一群观众带到蒙娜丽莎面前。对着眼前的人说话，像在分享一个忍不住想说的秘密；最后的问题，要像真的在等大家回答。"}'::jsonb,
   null, 'female'),

  ('5beec000-0000-4000-8000-0000000b002c', 'zh', '雨伞先别急着收', 'explainer',
   '各位观众早上好，今天是星期五。我们来看看周末的天气。先透露一句，有好消息，不过得请大家先等一等。

先说不太好的部分。这条在我们头顶上待了一整个星期的雨带，还没有走。今天上午，北部地区和沿海一带有较强阵雨，到中午前后，阵风可达八级。开车上班的朋友，请多留出几分钟。还有，记得带那把大伞，别带那把好看的小伞。

今天下午，最高气温很难超过九度，夜间最低气温会降到两度左右。阳台上养了花草的朋友，记得搬进屋里。

好，接下来就是大家等着的部分了。明天上午晚些时候，随着高压从西边移过来，这条雨带会逐渐东移入海。到星期六下午，天空晴朗，风力不大，最高气温能回升到十五度。星期天的天气还会更好。

没错，连着阴了三个星期，太阳终于要回来了。

那么，我想问问大家：这是快一个月来的第一个晴朗周末，你打算怎么过？',
   '[]'::jsonb, 75, 'weather',
   '{"en": "You’re the morning weather presenter, telling everyone getting ready for work what the weekend holds. Keep it bright and clear, and save the good news for the end.", "ko": "아침 방송 기상캐스터가 되어 주말 날씨를 전해요. 출근 준비하는 사람들에게 말하듯 밝고 또렷하게, 좋은 소식은 아껴 뒀다가 마지막에 풀어 주세요.", "ja": "朝の番組のお天気キャスターになって、週末の天気を伝えます。出かける準備をしている人に話しかけるように、明るくはっきりと。いい知らせは最後までとっておいてください。", "de": "Du moderierst das Wetter im Frühstücksfernsehen und sagst allen, die sich gerade für die Arbeit fertig machen, wie das Wochenende wird. Hell und klar, und die gute Nachricht hebst du dir bis zum Schluss auf.", "es": "Eres quien presenta el tiempo en el programa de la mañana y cuentas qué trae el fin de semana a quienes se preparan para salir. Con energía y claridad, y guarda la buena noticia para el final.", "fr": "Tu présentes la météo du matin et tu annonces le week-end à ceux qui se préparent à partir travailler. Avec entrain et clarté, et garde la bonne nouvelle pour la fin.", "zh-Hant": "你是晨間新聞的氣象主播，要告訴正在準備出門的大家週末天氣如何。語氣明亮清楚，好消息留到最後再說。", "zh-Hans": "你是早间新闻的天气预报员，要告诉正准备出门的大家周末天气怎么样。语气明快清楚，好消息留到最后再说。"}'::jsonb,
   null, 'male'),

  ('5beec000-0000-4000-8000-0000000b002d', 'zh', '我又重看了一遍《星际穿越》', 'explainer',
   '嗨，大家好，欢迎回来。昨天晚上，我又重看了一遍《星际穿越》，差不多是第十遍了吧。我必须跟你们聊聊，因为这一次，它比以往任何一次都更打动我。放心，不剧透结局。

先简单交代一下背景。地球快不行了，到处都是沙尘暴，庄稼一片一片地死掉。一个叫库珀的前飞行员，留下自己的孩子，穿过虫洞，去给人类找一个新家。

那这部电影到底特别在哪儿？第一，科学是真的。克里斯托弗·诺兰请来了物理学家基普·索恩，银幕上那个黑洞，就是根据他的方程做出来的。做得太逼真了，后来还被写进了科学论文。

第二，是配乐。汉斯·季默用了一架巨大的教堂管风琴。对接那场戏，管风琴一响起来，我发誓，我连呼吸都忘了。

但每次都让我绷不住的，是这一场。他们降落在一颗星球上，在那里待一个小时，地球上就过去了七年。等库珀回到飞船，孩子们二十三年的留言都在等着他。他用几分钟看着孩子们长大，却一句话也回不了。

它完美吗？不完美。有些台词说得有点重，片长也差不多三个小时。可是我从来没看过哪部电影，能把物理拍得这么让人心疼。

所以，我想问问你们：如果能跨越时间给一个人发一条消息，你会发给谁？你会说什么？',
   '["https://doi.org/10.1088/0264-9381/32/6/065001", "https://en.wikipedia.org/wiki/Interstellar_(soundtrack)"]'::jsonb, 95, 'film_review',
   '{"en": "You’re a film reviewer, and you’ve just rewatched Interstellar. Talk the way you would to a friend you want to see it, mean it when you get to that scene, and ask the last question like you’re waiting for the comments.", "ko": "영화 전문 리뷰어가 되어 인터스텔라를 다시 보고 리뷰해요. 좋아하는 영화를 친구에게 권하듯 신나게, 그 장면에서는 진심을 담아서, 마지막 질문은 댓글을 기다리듯이요.", "ja": "映画レビュアーになって、インターステラーを見返したレビューをします。好きな映画を友だちにすすめるように楽しく、あのシーンでは気持ちを込めて。最後の質問は、コメントを待っているつもりで。", "de": "Du bist Filmkritikerin und hast gerade Interstellar noch einmal gesehen. Erzähl es wie einer Freundin, die den Film unbedingt sehen soll, sprich die eine Szene mit Gefühl, und stell die letzte Frage so, als würdest du auf die Kommentare warten.", "es": "Eres crítica de cine y acabas de volver a ver Interstellar. Cuéntalo como se lo contarías a una amiga a la que quieres convencer, pon el corazón en esa escena y haz la última pregunta como si esperaras los comentarios.", "fr": "Tu es critique de cinéma et tu viens de revoir Interstellar. Raconte-le comme à une amie que tu veux convaincre, mets-y du cœur sur cette scène, et pose la dernière question comme si tu attendais les commentaires.", "zh-Hant": "你是電影評論人，剛重看了《星際效應》。像跟朋友推薦愛看的電影一樣興奮地說，講到那一幕時要真心，最後的問題就像在等大家留言。", "zh-Hans": "你是影评人，刚重看了《星际穿越》。像跟朋友安利喜欢的电影一样兴奋地说，讲到那一幕时要真心，最后的问题就像在等大家留言。"}'::jsonb,
   null, 'female')
on conflict (id) do nothing;
