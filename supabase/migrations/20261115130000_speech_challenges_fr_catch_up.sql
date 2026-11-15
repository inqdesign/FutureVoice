-- French catches up with English's speech challenges (founder, 2026-11-15:
-- every target language gets the challenges English has). French had only
-- the two it started with (…0f0001, …0f0002); these are the eight English
-- challenges it was missing, one row each, WRITTEN in French for the same
-- role, not translated: the same story shape and payoff, the same closing
-- question to the listener, about the same length, the same category key and
-- the same reading voice as the English original (null there reads female,
-- so female here, set explicitly; the weather presenter is male). The French
-- scripts address their audience with vous, as …0f0001 does; the intros
-- speak to the learner with tu, as every French intro does. Numbers are
-- words, no digits, no em dashes, and no intro asks for a slow reading.
-- Typographic ’ and a no-break space before ? ! : ; and inside « ».
--
--   …0f000b  short_talk  (English …000b, Brooks). Checked: Brooks, Journal
--            of Experimental Psychology: General, 2014, doi:10.1037/a0035325
--            (participants said "I am excited" or "I am calm" aloud before a
--            short filmed persuasive speech; raters judged the excited group
--            more confident and persuasive; anxiety stayed). A twenty-twenty-
--            five direct replication found no observable gain in the speeches,
--            which is the script's "not always the same effect". French says
--            « J’ai hâte ! », because « je suis excité » means something else.
--   …0f0010  in_flight   nawana Air (never a real carrier), Paris to Montréal,
--            no flight number. Checked: a direct Paris CDG to Montréal YUL
--            flight is about seven and a half hours (Air France route pages,
--            flight-report.com averages ~7 h 40). Air France's own phrasing.
--   …0f0020  show_host   a made-up cream (« Rosée de Nuit »), no claims beyond
--            the English row's.
--   …0f0024  acceptance  NOT Michelle Yeoh's speech and not any real one: an
--            original winner (sixty-two, first leading role, a mother of
--            eighty-seven), no real names, no real award named. The spirit of
--            the English row (hope to the girls watching, never too late, the
--            mother) without its words.
--   …0f0025  podcast     original, no facts (« Petites Victoires »).
--   …0f002b  docent      at the Louvre, her own museum. Checked (History Hit,
--            NPR 2011): taken Monday 21 August 1911 while the Louvre was
--            closed, by Vincenzo Peruggia, a handyman who had worked there,
--            under his smock; noticed about twenty-six hours later; Picasso
--            questioned (and Apollinaire held); crowds came to see the empty
--            spot; found in Florence in December 1913, back at the Louvre on
--            4 January 1914. The Grande Galerie is next to the Salle des États.
--   …0f002c  weather     a made-up forecast, no real place, date or channel;
--            wind in kilometres an hour, as a French forecast says it.
--   …0f002d  film_review Checked: the black hole paper (James, von
--            Tunzelmann, Franklin, Thorne, Classical and Quantum Gravity 32,
--            2015, arXiv:1502.03808); the organ was Temple Church's in London;
--            one hour on Miller's planet is seven years on Earth; twenty-three
--            years of messages; about two hours forty-nine minutes. No ending
--            spoilers. « Interstellar » is the French release title too.
--
-- Same ids pattern as the French Season 1 rows (…0f00NN, NN = the English
-- row's own number). French has no Season 2 yet, so these land in Season 1.

insert into public.speech_challenges (id, language, title, genre, body, sources, target_seconds, category, intro, link, reference_voice)
values
  ('5beec000-0000-4000-8000-0000000f000b', 'fr', 'Le trac ? Dites-vous que vous avez hâte', 'explainer',
   'Votre cœur bat à toute vitesse, vos mains sont glacées, et dans une minute, vous allez parler devant tout le monde. La plupart d’entre nous se disent la même chose : du calme. Et si c’était justement le mauvais conseil ?

En deux mille quatorze, Alison Wood Brooks, chercheuse à la Harvard Business School, a voulu en avoir le cœur net. Elle a demandé à des volontaires de faire un court discours devant une caméra. Juste avant de commencer, certains ont dit à voix haute : « Je suis calme. » D’autres ont dit : « J’ai hâte ! »

Ensuite, d’autres personnes ont regardé les vidéos et les ont notées. Ceux qui avaient dit « J’ai hâte » paraissaient plus sûrs d’eux et plus convaincants.

Pourquoi une seule phrase changerait-elle quelque chose ? Le trac et l’impatience se ressemblent beaucoup dans le corps. Dans les deux cas, le cœur s’accélère. Se calmer, c’est difficile. Donner un autre nom à la même sensation, c’est facile.

Attention, il y a un bémol. Le trac n’avait pas disparu. Les gens se sentaient toujours anxieux. Et les études suivantes n’ont pas toujours retrouvé le même effet. Ce n’est donc pas un tour de magie.

Mais essayer ne coûte rien. Avant d’appuyer sur le bouton d’enregistrement, dites-le une fois : j’ai hâte !',
   '["https://doi.org/10.1037/a0035325"]'::jsonb, 75, 'short_talk',
   '{"en": "A short talk about stage fright and the one sentence that might help. Tell it like someone who has just read the study, and say the last line as if you’re about to walk on stage.", "ko": "무대 공포증과, 도움이 될지도 모르는 한 문장에 관한 짧은 이야기예요. 방금 연구를 읽고 온 사람처럼 들려주고, 마지막 한 줄은 곧 무대에 오를 사람처럼 말해 보세요.", "ja": "あがり症と、それを助けてくれるかもしれないひとことについての短い話です。研究を読んだばかりの人のように話して、最後の一言は、これから舞台に出るつもりで言ってみましょう。", "de": "Ein kurzer Vortrag über Lampenfieber und den einen Satz, der helfen könnte. Erzähl es wie jemand, der gerade die Studie gelesen hat, und sag den letzten Satz so, als würdest du gleich auf die Bühne gehen.", "es": "Una charla corta sobre los nervios antes de hablar y la frase que quizá ayude. Cuéntalo como alguien que acaba de leer el estudio, y di la última frase como si estuvieras a punto de salir al escenario.", "fr": "Une courte intervention sur le trac et la petite phrase qui pourrait aider. Raconte-le comme quelqu’un qui vient de lire l’étude, et dis la dernière phrase comme si tu allais monter sur scène.", "zh-Hant": "一段關於上台緊張、以及一句可能有幫助的話的短講。像剛讀完這項研究的人一樣分享，最後一句就像你馬上要上台那樣說出來。", "zh-Hans": "一段关于上台紧张、以及一句可能有帮助的话的短讲。像刚读完这项研究的人一样分享，最后一句就像你马上要上台那样说出来。"}'::jsonb,
   null, 'female'),

  ('5beec000-0000-4000-8000-0000000f0010', 'fr', 'Mesdames et messieurs, bienvenue à bord', 'briefing',
   'Mesdames et messieurs, bonsoir et bienvenue à bord de ce vol nawana Air à destination de Montréal.

L’embarquement est terminé et les portes de l’avion sont fermées. Nous vous prions d’attacher votre ceinture, de redresser le dossier de votre siège et de relever votre tablette.

Veuillez mettre vos téléphones portables et tous vos appareils électroniques en mode avion. Les appareils plus volumineux, comme les ordinateurs portables, doivent être rangés pendant le décollage dans les coffres à bagages ou sous le siège devant vous.

Dans quelques instants, notre équipage va vous présenter les consignes de sécurité de cet appareil. Prenez le temps de repérer la sortie la plus proche de vous. Elle peut se trouver derrière vous.

La durée de notre vol jusqu’à Montréal sera aujourd’hui d’environ sept heures trente. Peu après le décollage, nous aurons le plaisir de vous servir le dîner et des boissons.

Nous vous rappelons que ce vol est entièrement non-fumeur. Il est interdit de fumer à bord, y compris dans les toilettes.

Le commandant de bord et l’ensemble de l’équipage vous remercient d’avoir choisi nawana Air et vous souhaitent un agréable vol.',
   '[]'::jsonb, 60, 'in_flight',
   '{"en": "You’re the cabin crew, making the announcement before take-off. Calm, polite and clear, like someone who has said it a thousand times and still means every word.", "ko": "이륙 전 기내 방송을 하는 승무원이 되어 보세요. 이 방송을 수없이 해 본 사람처럼 차분하고 정중하고 또렷하게, 그래도 한마디 한마디 진심을 담아서요.", "ja": "離陸前の機内アナウンスをする客室乗務員になりましょう。何度もこのアナウンスをしてきた人のように、落ち着いて、丁寧に、はっきりと。それでも一言ずつ心を込めて。", "de": "Du gehörst zur Kabinencrew und machst die Durchsage vor dem Start. Ruhig, höflich und klar, wie jemand, der diese Ansage schon tausendmal gemacht hat und trotzdem jedes Wort meint.", "es": "Formas parte de la tripulación de cabina y das el aviso antes del despegue. Con calma, cortesía y claridad, como alguien que lo ha dicho mil veces y aun así lo dice en serio.", "fr": "Tu fais partie de l’équipage et tu fais l’annonce avant le décollage. Avec calme, politesse et clarté, comme quelqu’un qui l’a faite mille fois et qui pense encore chaque mot.", "zh-Hant": "你是起飛前做機上廣播的空服員。像已經廣播過無數次的人一樣，沉穩、有禮、清楚，但每一句都說得真心。", "zh-Hans": "你是起飞前做机上广播的乘务员。像已经广播过无数次的人一样，沉稳、有礼、清楚，但每一句都说得真心。"}'::jsonb,
   null, 'female'),

  ('5beec000-0000-4000-8000-0000000f0020', 'fr', 'Réveillez-vous avec une peau éclatante', 'product',
   'Mesdames et messieurs, avant que je dise quoi que ce soit, regardez mon visage. De tout près. Pas de filtre, pas de fond de teint, rien. Juste ma vraie peau, à la fin d’une très longue journée.

Il y a deux semaines, ma peau était fatiguée. Sèche autour du nez, rêche sur les joues, et ces petites ridules au coin des yeux dès que je souriais. Ça vous dit quelque chose ?

Voici la crème de nuit Rosée de Nuit. Regardez comment je l’utilise. Sur une peau bien propre, une toute petite noisette. Je la réchauffe entre mes doigts, et je la presse sur la peau. On ne frotte pas. On presse. Le front, les joues, le menton, et une pointe sous les yeux.

Regardez comme c’est léger. Elle sent le concombre frais, et elle disparaît comme de l’eau. Pas d’oreiller qui colle, pas de visage qui brille.

Et pendant que vous dormez, elle travaille pour vous. Elle garde l’hydratation toute la nuit, alors au réveil, votre peau est douce, repulpée et lisse, et votre maquillage glisse comme de la soie. Certains matins, franchement, je ne me maquille même pas.

Ce soir, vous recevez le grand pot, un format voyage pour votre sac et une crème contour des yeux offerte. Trois produits pour le prix d’un.

Votre peau travaille dur pour vous tous les jours. Offrez-lui une vraie bonne nuit. Appelez vite !',
   '[]'::jsonb, 60, 'show_host',
   '{"en": "You’re a home-shopping host, live on air, selling one night cream. Look straight into the camera, show off your own skin with confidence, and talk as if the phones won’t stop ringing.", "ko": "생방송 홈쇼핑 쇼호스트가 되어 나이트 크림 하나를 파는 장면이에요. 카메라를 똑바로 보고, 내 피부를 보여주듯 자신 있게, 주문 전화가 쏟아지는 것처럼 말해 보세요.", "ja": "生放送のテレビ通販で、ナイトクリームをひとつ売り込む場面です。カメラをまっすぐ見て、自分の肌を見せるように自信を持って、注文の電話が鳴りやまない勢いで話してみましょう。", "de": "Du moderierst live im Teleshopping und verkaufst eine Nachtcreme. Schau direkt in die Kamera, zeig selbstbewusst deine eigene Haut und sprich, als würden die Telefone gar nicht mehr stillstehen.", "es": "Presentas un programa de teletienda en vivo y vendes una crema de noche. Mira directo a la cámara, presume de tu piel con seguridad y habla como si los teléfonos no pararan de sonar.", "fr": "Tu animes une émission de téléachat en direct et tu vends une crème de nuit. Regarde la caméra droit dans les yeux, montre ta peau avec assurance et parle comme si les téléphones n’arrêtaient pas de sonner.", "zh-Hant": "你是電視購物的直播主持人，要賣一款晚霜。直視鏡頭，自信地秀出自己的皮膚，講得像訂購電話響個不停一樣。", "zh-Hans": "你是电视购物的直播主持人，要卖一款晚霜。直视镜头，自信地展示自己的皮肤，讲得像订购电话响个不停一样。"}'::jsonb,
   null, 'female'),

  ('5beec000-0000-4000-8000-0000000f0024', 'fr', 'Il n’est jamais trop tard', 'person',
   'Merci. Merci beaucoup. Pardon, laissez-moi une seconde. Je n’avais rien préparé, parce que je n’y croyais pas.

J’ai soixante-deux ans, et c’est mon premier grand rôle. Pendant trente ans, on m’a dit que j’étais trop ceci, pas assez cela. Trop petite, trop discrète, et puis un jour, trop vieille. Alors, à toutes les femmes qui m’entendent ce soir et qui pensent que leur tour est passé : ce n’est pas vrai. Il n’est jamais trop tard.

Et aux petites filles qui regardent depuis leur canapé, en pyjama, alors qu’elles devraient déjà dormir : rêvez grand. Rêvez très grand. Les rêves, ça se réalise. Je suis là pour vous le prouver.

Je ne serais pas sur cette scène sans notre réalisatrice, qui a cru en moi quand plus personne n’y croyait. Sans mes partenaires, sans toute l’équipe, des techniciens aux maquilleuses, qui ont tenu bon pendant tout ce tournage sous la pluie. Ce prix, il est à vous aussi.

Mais ce soir, je le dédie à ma mère. Elle a quatre-vingt-sept ans, elle est devant sa télévision, et je suis sûre qu’elle pleure déjà. Maman, c’est toi qui m’as appris à ne jamais baisser les bras. Je te le ramène à la maison.

Merci à l’Académie. Merci à vous tous. Et surtout, n’abandonnez jamais.',
   '[]'::jsonb, 90, 'acceptance',
   '{"en": "You’ve just won the top acting prize for your very first leading role, at sixty-two. Catch your breath at the start, talk straight to the women and girls watching, let your voice soften for your mother, and say the last line loud and clear.", "ko": "예순둘에 첫 주연으로 연기상을 받은 순간이에요. 처음엔 숨을 고르고, 지켜보는 여성들과 여자아이들에게 똑바로 말을 건네고, 엄마 이야기에서는 목소리를 부드럽게, 마지막 한 줄은 크고 또렷하게 말해 보세요.", "ja": "六十二歳、初めての主演で演技賞を受けた瞬間です。最初は息を整えて、見ている女性たちや女の子たちにまっすぐ語りかけ、お母さんの話では声をやわらかく、最後の一言は大きくはっきりと言ってみましょう。", "de": "Du hast gerade mit zweiundsechzig für deine allererste Hauptrolle den großen Darstellerpreis gewonnen. Hol am Anfang kurz Luft, sprich die Frauen und Mädchen vor den Bildschirmen direkt an, lass deine Stimme bei deiner Mutter weich werden und sag den letzten Satz laut und klar.", "es": "Acabas de ganar el gran premio de interpretación por tu primer papel protagonista, a los sesenta y dos años. Toma aire al principio, háblales directamente a las mujeres y a las niñas que te ven, deja que la voz se ablande al hablar de tu madre y di la última frase alto y claro.", "fr": "Tu viens de remporter le grand prix d’interprétation pour ton tout premier grand rôle, à soixante-deux ans. Reprends ton souffle au début, parle droit aux femmes et aux petites filles qui regardent, laisse ta voix s’adoucir pour ta mère, et lance la dernière phrase haut et fort.", "zh-Hant": "六十二歲的你，憑第一個主角拿下了表演大獎。開頭先喘口氣，直接對正在看的女性和小女孩們說話，講到媽媽時聲音放柔，最後一句要大聲、清楚。", "zh-Hans": "六十二岁的你，凭第一个主角拿下了表演大奖。开头先喘口气，直接对正在看的女性和小女孩们说话，讲到妈妈时声音放柔，最后一句要大声、清楚。"}'::jsonb,
   null, 'female'),

  ('5beec000-0000-4000-8000-0000000f0025', 'fr', 'Ravie de vous retrouver', 'explainer',
   'Salut tout le monde, et bienvenue dans un nouvel épisode de Petites Victoires, le podcast sur ces toutes petites choses qui changent la vie sans faire de bruit. Je suis votre animatrice, et je suis tellement contente que vous soyez là.

Prenez un café, installez-vous bien, parce que l’épisode d’aujourd’hui vaut le détour. On parle de la règle des cinq minutes. Le principe est simple. Quand vous n’avez pas envie de faire quelque chose, vous vous dites : je le fais juste cinq minutes. C’est tout. Cinq minutes, et après, j’ai le droit d’arrêter.

Et le plus drôle, c’est qu’on n’arrête presque jamais. Parce que le plus dur, ce n’était pas le travail. C’était de commencer.

Je l’ai testé le mois dernier avec la course à pied. Je déteste courir. Vraiment. Mais chaque matin, je me disais : cinq minutes, juste le tour du pâté de maisons. Et vous savez quoi ? Ce matin, j’ai couru une demi-heure, et je n’ai même pas vu le temps passer.

Aujourd’hui, j’ai une invitée qui a utilisé cette petite astuce pour écrire un livre entier. Mais d’abord, une petite question pour vous. Quelle est la chose que vous repoussez sans arrêt ? Gardez-la en tête, parce qu’à la fin de cet épisode, vous allez vous y mettre.

C’est parti !',
   '[]'::jsonb, 60, 'podcast',
   '{"en": "You’re opening a new episode of your own podcast. Talk to one listener with headphones on, not to a crowd: relaxed and warm, with a smile in your voice.", "ko": "내 팟캐스트의 새 에피소드를 여는 장면이에요. 많은 사람이 아니라 이어폰을 낀 한 사람에게 말하듯, 편하고 다정하게, 목소리에 미소를 담아 말해 보세요.", "ja": "自分のポッドキャストの新しいエピソードを始める場面です。大勢ではなく、イヤホンで聴いているひとりに話しかけるように、リラックスして温かく、声に笑顔をのせてみましょう。", "de": "Du eröffnest eine neue Folge deines eigenen Podcasts. Sprich nicht zu einem Publikum, sondern zu einer Person mit Kopfhörern: locker, herzlich und mit einem Lächeln in der Stimme.", "es": "Abres un nuevo episodio de tu propio pódcast. No le hables a una multitud, sino a una persona con los auriculares puestos: con calma, con calidez y con una sonrisa en la voz.", "fr": "Tu ouvres un nouvel épisode de ton propre podcast. Ne parle pas à une foule, mais à une seule personne qui t’écoute avec ses écouteurs : sur un ton détendu et chaleureux, avec le sourire dans la voix.", "zh-Hant": "你正在為自己的 Podcast 開場新的一集。不是對一大群人，而是對戴著耳機的那一個人說話：輕鬆、溫暖，讓聲音帶著笑意。", "zh-Hans": "你正在为自己的播客开场新的一集。不是对一大群人，而是对戴着耳机的那一个人说话：轻松、温暖，让声音带着笑意。"}'::jsonb,
   null, 'female'),

  ('5beec000-0000-4000-8000-0000000f002b', 'fr', 'Approchez-vous un peu', 'explainer',
   'Bon, tout le monde, approchez-vous un peu. N’ayez pas peur, il reste de la place devant.

La plupart des gens sont surpris de voir à quel point elle est petite. Et certains d’entre vous se demandent sûrement : pourquoi elle ? Pourquoi le monde entier vient-il voir ce tableau, alors qu’il y en a de plus grands, de plus colorés, de plus spectaculaires juste à côté, dans la Grande Galerie ?

Voici le secret. Pendant quatre cents ans, la Joconde était célèbre dans le monde de l’art, et presque nulle part ailleurs. Et puis, un lundi matin bien tranquille, en août mille neuf cent onze, alors que le Louvre était fermé, un homme qui avait travaillé ici l’a décrochée du mur et est reparti avec le tableau caché sous sa blouse.

À votre avis, combien de temps a-t-il fallu pour que quelqu’un remarque qu’elle avait disparu ? Une journée entière.

Et c’est là que tout a changé. Les journaux du monde entier ont mis son visage à la une, si bien que des gens qui n’avaient jamais mis les pieds dans un musée savaient soudain exactement à quoi elle ressemblait. La police a même interrogé un jeune peintre qui s’appelait Pablo Picasso. Et ici, dans ce musée, la foule faisait la queue rien que pour regarder l’espace vide sur le mur.

Pendant plus de deux ans, le monde entier s’est demandé où elle était. Alors, quand on l’a enfin retrouvée à Florence et qu’elle est revenue à Paris, ce n’était plus seulement un tableau. C’était le visage le plus célèbre de la planète.

Alors regardez encore une fois ce sourire, et dites-moi : si personne ne l’avait jamais volée, est-ce que vous seriez là aujourd’hui ?',
   '["https://www.historyhit.com/culture/theft-mona-lisa/", "https://www.npr.org/2011/07/30/138800110/the-theft-that-made-the-mona-lisa-a-masterpiece"]'::jsonb, 90, 'docent',
   '{"en": "You’re a museum docent, and you’ve just gathered a group in front of the Mona Lisa. Tell it like a secret you can’t wait to share, talk to the faces in front of you, and ask the last question as if you really want an answer.", "ko": "미술관 도슨트가 되어 모나리자 앞에 관람객들을 모았어요. 눈앞의 사람들에게 말을 걸듯, 꼭 들려주고 싶던 비밀을 털어놓는 기분으로 읽어 보세요. 마지막 질문은 정말 대답을 기다리듯이요.", "ja": "美術館のドーセントになって、モナ・リザの前にお客さんを集めたところです。目の前の人たちに話しかけるように、とっておきの秘密を打ち明ける気分で読んでみましょう。最後の質問は、本当に答えを待っているつもりで。", "de": "Du führst durchs Museum und hast gerade eine Gruppe vor der Mona Lisa versammelt. Sprich die Leute direkt an, als würdest du ein Geheimnis verraten, und stell die letzte Frage so, als wolltest du wirklich eine Antwort.", "es": "Eres guía de museo y acabas de reunir a un grupo frente a la Mona Lisa. Háblales directamente, como quien cuenta un secreto que llevaba tiempo guardando, y haz la última pregunta como si de verdad esperaras una respuesta.", "fr": "Tu es guide de musée et tu viens de rassembler un groupe devant la Joconde. Parle aux gens en face de toi, comme si tu leur confiais un secret, et pose la dernière question comme si tu attendais vraiment une réponse.", "zh-Hant": "你是美術館的導覽員，剛把一群觀眾帶到蒙娜麗莎前面。對著眼前的人說話，像在分享一個忍不住想說的祕密；最後的問題，要像真的在等大家回答。", "zh-Hans": "你是美术馆的讲解员，刚把一群观众带到蒙娜丽莎面前。对着眼前的人说话，像在分享一个忍不住想说的秘密；最后的问题，要像真的在等大家回答。"}'::jsonb,
   null, 'female'),

  ('5beec000-0000-4000-8000-0000000f002c', 'fr', 'Ne rangez pas tout de suite votre parapluie', 'explainer',
   'Bonjour à tous, et bon vendredi. On regarde tout de suite le week-end, parce que j’ai une bonne nouvelle, et je vais vous faire un peu attendre.

D’abord, le moins bon. Cette bande de pluie qui stationne au-dessus de nous depuis le début de la semaine n’en a pas encore fini. Ce matin, de fortes averses sont attendues dans le nord et le long des côtes, avec des rafales jusqu’à soixante-dix kilomètres-heure en fin de matinée. Si vous prenez la voiture pour aller travailler, partez quelques minutes plus tôt. Et s’il vous plaît, prenez le grand parapluie, pas celui qui est juste joli.

Cet après-midi, le thermomètre aura du mal à dépasser les neuf degrés, et cette nuit, il descendra autour de deux degrés. Si vous avez des plantes sur le balcon, rentrez-les.

Et maintenant, le moment que vous attendiez. Demain, en fin de matinée, un anticyclone arrive par l’ouest et repousse toute cette perturbation vers la mer. Samedi après-midi, on attend un grand ciel bleu, un vent faible et jusqu’à quinze degrés. Et dimanche s’annonce encore plus beau.

Eh oui. Après trois semaines de grisaille, le soleil fait enfin son retour.

Alors, ma question pour vous : qu’est-ce que vous allez faire de votre premier week-end ensoleillé depuis presque un mois ?',
   '[]'::jsonb, 75, 'weather',
   '{"en": "You’re the morning weather presenter, telling everyone getting ready for work what the weekend holds. Keep it bright and clear, and save the good news for the end.", "ko": "아침 방송 기상캐스터가 되어 주말 날씨를 전해요. 출근 준비하는 사람들에게 말하듯 밝고 또렷하게, 좋은 소식은 아껴 뒀다가 마지막에 풀어 주세요.", "ja": "朝の番組のお天気キャスターになって、週末の天気を伝えます。出かける準備をしている人に話しかけるように、明るくはっきりと。いい知らせは最後までとっておいてください。", "de": "Du moderierst das Wetter im Frühstücksfernsehen und sagst allen, die sich gerade für die Arbeit fertig machen, wie das Wochenende wird. Hell und klar, und die gute Nachricht hebst du dir bis zum Schluss auf.", "es": "Eres quien presenta el tiempo en el programa de la mañana y cuentas qué trae el fin de semana a quienes se preparan para salir. Con energía y claridad, y guarda la buena noticia para el final.", "fr": "Tu présentes la météo du matin et tu annonces le week-end à ceux qui se préparent à partir travailler. Avec entrain et clarté, et garde la bonne nouvelle pour la fin.", "zh-Hant": "你是晨間新聞的氣象主播，要告訴正在準備出門的大家週末天氣如何。語氣明亮清楚，好消息留到最後再說。", "zh-Hans": "你是早间新闻的天气预报员，要告诉正准备出门的大家周末天气怎么样。语气明快清楚，好消息留到最后再说。"}'::jsonb,
   null, 'male'),

  ('5beec000-0000-4000-8000-0000000f002d', 'fr', 'J’ai revu Interstellar', 'explainer',
   'Salut tout le monde, et bon retour sur la chaîne. Alors, hier soir, j’ai revu Interstellar, pour la dixième fois peut-être, et il faut absolument que je vous en parle, parce que ça m’a frappée plus fort que jamais. Pas de spoiler sur la fin, promis.

Le pitch, en deux mots. La Terre se meurt. Des tempêtes de poussière partout, des récoltes perdues, et un ancien pilote, Cooper, laisse ses enfants derrière lui pour traverser un trou de ver et trouver une nouvelle maison pour l’humanité.

Alors, qu’est-ce qui rend ce film si spécial ? D’abord, la science est vraie. Christopher Nolan a travaillé avec le physicien Kip Thorne, et le trou noir que vous voyez à l’écran a été construit à partir de ses équations. Il était si réaliste qu’il s’est retrouvé dans des articles scientifiques.

Ensuite, la musique. Hans Zimmer a utilisé un immense orgue d’église, et quand il démarre pendant la scène de l’arrimage, je vous jure, j’ai oublié de respirer.

Mais voilà la scène qui me bouleverse à chaque fois. Ils se posent sur une planète où une heure vaut sept ans sur Terre. Quand Cooper remonte à bord, vingt-trois ans de messages de ses enfants l’attendent. Il les regarde grandir en quelques minutes, et il ne peut pas leur répondre un seul mot.

Est-ce qu’il est parfait ? Non. Certains dialogues sont un peu lourds, et il dure presque trois heures. Mais je n’ai jamais vu un film rendre la physique aussi personnelle.

Alors, ma question pour vous. Si vous pouviez envoyer un message à quelqu’un à travers le temps, ce serait à qui, et qu’est-ce que vous lui diriez ?',
   '["https://arxiv.org/abs/1502.03808"]'::jsonb, 95, 'film_review',
   '{"en": "You’re a film reviewer, and you’ve just rewatched Interstellar. Talk the way you would to a friend you want to see it, mean it when you get to that scene, and ask the last question like you’re waiting for the comments.", "ko": "영화 전문 리뷰어가 되어 인터스텔라를 다시 보고 리뷰해요. 좋아하는 영화를 친구에게 권하듯 신나게, 그 장면에서는 진심을 담아서, 마지막 질문은 댓글을 기다리듯이요.", "ja": "映画レビュアーになって、インターステラーを見返したレビューをします。好きな映画を友だちにすすめるように楽しく、あのシーンでは気持ちを込めて。最後の質問は、コメントを待っているつもりで。", "de": "Du bist Filmkritikerin und hast gerade Interstellar noch einmal gesehen. Erzähl es wie einer Freundin, die den Film unbedingt sehen soll, sprich die eine Szene mit Gefühl, und stell die letzte Frage so, als würdest du auf die Kommentare warten.", "es": "Eres crítica de cine y acabas de volver a ver Interstellar. Cuéntalo como se lo contarías a una amiga a la que quieres convencer, pon el corazón en esa escena y haz la última pregunta como si esperaras los comentarios.", "fr": "Tu es critique de cinéma et tu viens de revoir Interstellar. Raconte-le comme à une amie que tu veux convaincre, mets-y du cœur sur cette scène, et pose la dernière question comme si tu attendais les commentaires.", "zh-Hant": "你是電影評論人，剛重看了《星際效應》。像跟朋友推薦愛看的電影一樣興奮地說，講到那一幕時要真心，最後的問題就像在等大家留言。", "zh-Hans": "你是影评人，刚重看了《星际穿越》。像跟朋友安利喜欢的电影一样兴奋地说，讲到那一幕时要真心，最后的问题就像在等大家留言。"}'::jsonb,
   null, 'female')
on conflict (id) do nothing;
