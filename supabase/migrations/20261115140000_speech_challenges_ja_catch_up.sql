-- Japanese catches up with English (founder, 2026-11-15): every target
-- language gets the speech challenges English has. Japanese had the first
-- four (…0003, …0007, …000d, …0012); these are the six it was missing, one
-- per English original, each WRITTEN in Japanese for that job rather than
-- translated, at the English row's target_seconds (~7 characters a second,
-- about the rate the four Japanese rows already read at).
--
--   …0a0020  show_host    テレビ通販 (English …0020, Wake up glowing).
--            A made-up product, no facts.
--   …0a0024  acceptance   An ORIGINAL acceptance speech by a fictional
--            actress who started late. Not Michelle Yeoh's words or a
--            translation of them (English …0024): no real names, no real
--            award.
--   …0a0025  podcast      Opening a new episode (English …0025). No facts.
--   …0a002b  docent       In front of the Mona Lisa (English …002b). Checked
--            2026-11-15: stolen on Monday 21 August 1911, a day the Louvre
--            was closed, by Vincenzo Peruggia, who had worked there, walking
--            out with it under his smock; not noticed until the next day;
--            Apollinaire arrested and Picasso questioned; crowds came to see
--            the empty wall; found in Florence in December 1913 (over two
--            years), back in Paris January 1914. Smithsonian, History.com.
--   …0a002c  weather      A 気象予報士 on a morning show, です・ます, a made-up
--            forecast for 東北 with no date or broadcaster (English …002c).
--            Wind as 最大瞬間風速 in metres a second and temperatures in
--            degrees, the way a Japanese forecast says them; a 移動性高気圧
--            coming from the west and pushing the rain out to sea matches
--            JMA's own explanation of how weather moves west to east.
--   …0a002d  film_review  Rewatching インターステラー (English …002d).
--            Checked 2026-11-15: the black hole rendered from Kip Thorne's
--            equations and published in Classical and Quantum Gravity
--            (James, von Tunzelmann, Franklin, Thorne, 2015, arXiv
--            1502.03808); Zimmer's organ recorded at Temple Church, London;
--            one hour on Miller's planet is seven years on Earth; twenty-
--            three years of messages; just under three hours long. No
--            ending spoilers.
--
-- No Arabic digits (years and numbers in kanji: 千九百十一年, 二十メートル),
-- no em dashes, and the intros never ask for a slow reading. category and
-- reference_voice copy the English original ('female' where English is
-- null). Japanese is on Season 1, so the season trigger files them there.

insert into public.speech_challenges (id, language, title, genre, body, sources, target_seconds, category, intro, link, reference_voice)
values
  ('5beec000-0000-4000-8000-0000000a0020', 'ja', '朝の肌が、違うんです', 'product',
   '皆さん、まずは何も言わずに、わたしの顔を見てください。もっと近くで。フィルターなし、ファンデーションもなし。長い一日の終わりの、素肌そのままです。

実は二週間前まで、わたしの肌はお疲れぎみでした。小鼻のまわりは乾燥して、頬はざらざら。笑うたびに、目尻に小さなしわ。皆さんにも、覚えがありませんか。

そこで出会ったのが、こちら。モーニングデューのナイトクリームです。洗顔のあと、パール粒ほどを指先で温めて、押さえるようにのせます。こすらないでください。押さえるだけ。おでこ、頬、あご、目の下にもほんの少し。

どうですか、このかるさ。きゅうりのような爽やかな香りで、すっと水のようになじみます。枕がべたつくことも、顔がてかることもありません。

しかも、眠っている間に働いてくれるんです。ひと晩じゅう潤いを閉じ込めて、朝にはふっくら、つるんとした肌に。お化粧のノリも、まるでシルク。ノーメイクで出かける朝もあるくらいです。

今夜だけ、本品にミニサイズ、さらにアイクリームもお付けして、一つ分のお値段です。

毎日がんばっている皆さんの肌に、ひと晩のごほうびを。お電話、お待ちしております。',
   '[]'::jsonb, 60, 'show_host',
   '{"en": "You’re a home-shopping host, live on air, selling one night cream. Look straight into the camera, show off your own skin with confidence, and talk as if the phones won’t stop ringing.", "ko": "생방송 홈쇼핑 쇼호스트가 되어 나이트 크림 하나를 파는 장면이에요. 카메라를 똑바로 보고, 내 피부를 보여주듯 자신 있게, 주문 전화가 쏟아지는 것처럼 말해 보세요.", "ja": "生放送のテレビ通販で、ナイトクリームをひとつ売り込む場面です。カメラをまっすぐ見て、自分の肌を見せるように自信を持って、注文の電話が鳴りやまない勢いで話してみましょう。", "de": "Du moderierst live im Teleshopping und verkaufst eine Nachtcreme. Schau direkt in die Kamera, zeig selbstbewusst deine eigene Haut und sprich, als würden die Telefone gar nicht mehr stillstehen.", "es": "Presentas un programa de teletienda en vivo y vendes una crema de noche. Mira directo a la cámara, presume de tu piel con seguridad y habla como si los teléfonos no pararan de sonar.", "fr": "Tu animes une émission de téléachat en direct et tu vends une crème de nuit. Regarde la caméra droit dans les yeux, montre ta peau avec assurance et parle comme si les téléphones n’arrêtaient pas de sonner.", "zh-Hant": "你是電視購物的直播主持人，要賣一款晚霜。直視鏡頭，自信地秀出自己的皮膚，講得像訂購電話響個不停一樣。", "zh-Hans": "你是电视购物的直播主持人，要卖一款晚霜。直视镜头，自信地展示自己的皮肤，讲得像订购电话响个不停一样。"}'::jsonb,
   null, 'female'),

  ('5beec000-0000-4000-8000-0000000a0024', 'ja', '遅すぎる夢なんてない', 'person',
   'ありがとうございます。本当に、ありがとうございます。

今夜、どこかでこの中継を見ている、何かを始めるのが怖い人へ。わたしの話を、少しだけ聞いてください。

わたしがお芝居を始めたのは、四十歳を過ぎてからでした。周りからは、今さら何を言ってるの、と笑われました。オーディションには落ち続けて、もらえる役はいつもセリフが一行だけ。何度も、もうやめようと思いました。でも、やめなくて、本当によかった。

監督、共演者の皆さん、スタッフの皆さん、この作品に関わってくださったすべての方へ。皆さんがいなければ、わたしは今夜、ここに立っていません。

でも、この賞は、母に贈りたいと思います。わたしが四十歳で、女優になりたいと言ったとき、たった一人、笑わなかった人です。黙ってお弁当を作って、オーディションに送り出してくれました。

母は今、八十四歳です。今ごろ、ふるさとの家で、家族や近所の人たちと一緒に、このテレビを見ているはずです。お母さん、見てる？ このトロフィー、ちゃんと持って帰るからね。

最初に舞台に立たせてくれた小さな劇団の仲間たち。肩を貸してくれて、背中を押してくれて、ありがとう。それから、きょうだいたち、そして家族みんな。本当に、ありがとう。

最後に、もう一度だけ、見ている皆さんに聞かせてください。夢を見るのに、遅すぎることなんて、本当にあると思いますか。

今夜、わたしはその答えを、この手で受け取りました。ありがとうございました。',
   '[]'::jsonb, 90, 'acceptance',
   '{"en": "You’ve just won Best Actress, years after everyone told you it was too late to start. Speak the first lines to anyone watching who has a dream on hold, let your voice go warm when you talk to your mom, and let the last line ring out.", "ko": "늦은 나이에 연기를 시작해 마침내 여우주연상을 받은 배우가 되어 보세요. 첫 문장은 꿈을 미뤄 둔 사람들에게, 엄마 이야기는 따뜻하게, 마지막 한 줄은 크게 말해 보세요.", "ja": "遅くにお芝居を始めて、ついに主演女優賞をつかんだ俳優になりきりましょう。最初の言葉は夢をあきらめかけている人たちに、お母さんへの言葉はあたたかく、最後の一言は力強く話してみましょう。", "de": "Du hast gerade den Preis als beste Hauptdarstellerin gewonnen, Jahre nachdem alle gesagt haben, es sei zu spät zum Anfangen. Sprich die ersten Sätze zu allen, die einen Traum aufgeschoben haben, werde ganz warm, wenn du mit deiner Mutter sprichst, und lass den letzten Satz richtig klingen.", "es": "Acabas de ganar el premio a mejor actriz, años después de que todos te dijeran que era tarde para empezar. Dirige las primeras frases a quien tenga un sueño en pausa, habla con ternura cuando llegues a tu mamá y deja que la última frase resuene.", "fr": "Tu viens de remporter le prix de la meilleure actrice, des années après qu’on t’a dit qu’il était trop tard pour commencer. Adresse les premières phrases à tous ceux qui ont mis un rêve de côté, mets de la tendresse dans ta voix quand tu parles à ta mère, et laisse la dernière phrase résonner.", "zh-Hant": "你很晚才開始演戲，現在終於拿下最佳女主角。第一句話說給把夢想擱著的人聽，跟媽媽說話時語氣溫暖，最後一句大聲說出來。", "zh-Hans": "你很晚才开始演戏，现在终于拿下最佳女主角。第一句话说给把梦想搁着的人听，跟妈妈说话时语气温暖，最后一句大声说出来。"}'::jsonb,
   null, 'female'),

  ('5beec000-0000-4000-8000-0000000a0025', 'ja', '今週も始まりました', 'explainer',
   'みなさん、こんにちは。今週も始まりました、「きょうの小さな一歩」。人生をこっそり変えてくれる、小さなことをお届けする番組です。今日も聴いてくれて、本当にうれしいです。

コーヒー片手に、楽にして聴いてくださいね。今日のテーマは、「五分だけルール」です。やる気が出ないとき、自分にこう言うんです。とりあえず、五分だけやろう。それだけ。五分たったら、やめていい。

で、ここがおもしろいところなんですけど、たいてい、やめないんですよ。だって、いちばん大変なのは、作業そのものじゃなくて、始めることだったから。

わたし、先月これをランニングで試してみたんです。走るの、本当に苦手なんですよ。でも毎朝、五分だけ、近所をひとまわりするだけ、って。そしたら、どうなったと思います？ 今朝は三十分走ってて、自分でも気づかなかったんです。

今日のゲストは、このワザで本を一冊書き上げた方です。でもその前に、ひとつ質問させてください。ずっと後回しにしていること、ありませんか？ それ、覚えておいてくださいね。この回が終わるころには、きっと始めたくなっていますから。

では、いってみましょう。',
   '[]'::jsonb, 60, 'podcast',
   '{"en": "You’re opening a new episode of your own podcast. Talk to one listener with headphones on, not to a crowd: relaxed and warm, with a smile in your voice.", "ko": "내 팟캐스트의 새 에피소드를 여는 장면이에요. 많은 사람이 아니라 이어폰을 낀 한 사람에게 말하듯, 편하고 다정하게, 목소리에 미소를 담아 말해 보세요.", "ja": "自分のポッドキャストの新しいエピソードを始める場面です。大勢ではなく、イヤホンで聴いているひとりに話しかけるように、リラックスして温かく、声に笑顔をのせてみましょう。", "de": "Du eröffnest eine neue Folge deines eigenen Podcasts. Sprich nicht zu einem Publikum, sondern zu einer Person mit Kopfhörern: locker, herzlich und mit einem Lächeln in der Stimme.", "es": "Abres un nuevo episodio de tu propio pódcast. No le hables a una multitud, sino a una persona con los auriculares puestos: con calma, con calidez y con una sonrisa en la voz.", "fr": "Tu ouvres un nouvel épisode de ton propre podcast. Ne parle pas à une foule, mais à une seule personne qui t’écoute avec ses écouteurs : sur un ton détendu et chaleureux, avec le sourire dans la voix.", "zh-Hant": "你正在為自己的 Podcast 開場新的一集。不是對一大群人，而是對戴著耳機的那一個人說話：輕鬆、溫暖，讓聲音帶著笑意。", "zh-Hans": "你正在为自己的播客开场新的一集。不是对一大群人，而是对戴着耳机的那一个人说话：轻松、温暖，让声音带着笑意。"}'::jsonb,
   null, 'female'),

  ('5beec000-0000-4000-8000-0000000a002b', 'ja', 'もう少し前へどうぞ', 'explainer',
   'はい、皆さん、もう少し前へどうぞ。遠慮しないでくださいね、前のほうはまだ空いていますから。

思ったより小さい、と驚かれる方が多いんです。それに、きっとこう思っていますよね。どうしてこの絵なんだろう。廊下の先には、もっと大きくて、もっと華やかな絵がいくらでもあるのに、なぜ世界中の人が、この一枚を見に来るのか。

実は、ちょっとした秘密があるんです。この絵は、およそ四百年ものあいだ、美術の世界では有名でも、それ以外ではほとんど知られていませんでした。ところが、千九百十一年八月のある月曜日の朝。休館日で静まりかえった館内で、以前ここで働いていた男が、壁からこの絵をはずし、作業着の下に隠して、そのまま外へ出ていったんです。

誰かがなくなったことに気づくまで、どのくらいかかったと思いますか。まる一日です。

そこから、すべてが変わりました。世界中の新聞が、一面にこの顔を載せたんです。美術館に一度も行ったことのない人まで、この顔を知るようになりました。警察は、若き日のピカソにまで話を聞いています。そしてこの美術館には、何もかかっていない壁を見るためだけに、行列ができました。

二年以上ものあいだ、世界中が、彼女はどこにいるのかと気にしていました。ですから、ようやくフィレンツェで見つかって、パリに戻ってきたとき、彼女はもう、ただの絵ではありませんでした。地球でいちばん有名な顔になっていたんです。

では最後に、もう一度あの微笑みを見てください。そして教えてください。もし誰にも盗まれていなかったら、皆さんは今日、ここに立っていたでしょうか。',
   '["https://www.smithsonianmag.com/arts-culture/the-theft-that-made-the-mona-lisa-a-masterpiece-16406234/", "https://www.history.com/news/the-heist-that-made-the-mona-lisa-famous"]'::jsonb, 90, 'docent',
   '{"en": "You’re a museum docent, and you’ve just gathered a group in front of the Mona Lisa. Tell it like a secret you can’t wait to share, talk to the faces in front of you, and ask the last question as if you really want an answer.", "ko": "미술관 도슨트가 되어 모나리자 앞에 관람객들을 모았어요. 눈앞의 사람들에게 말을 걸듯, 꼭 들려주고 싶던 비밀을 털어놓는 기분으로 읽어 보세요. 마지막 질문은 정말 대답을 기다리듯이요.", "ja": "美術館のドーセントになって、モナ・リザの前にお客さんを集めたところです。目の前の人たちに話しかけるように、とっておきの秘密を打ち明ける気分で読んでみましょう。最後の質問は、本当に答えを待っているつもりで。", "de": "Du führst durchs Museum und hast gerade eine Gruppe vor der Mona Lisa versammelt. Sprich die Leute direkt an, als würdest du ein Geheimnis verraten, und stell die letzte Frage so, als wolltest du wirklich eine Antwort.", "es": "Eres guía de museo y acabas de reunir a un grupo frente a la Mona Lisa. Háblales directamente, como quien cuenta un secreto que llevaba tiempo guardando, y haz la última pregunta como si de verdad esperaras una respuesta.", "fr": "Tu es guide de musée et tu viens de rassembler un groupe devant la Joconde. Parle aux gens en face de toi, comme si tu leur confiais un secret, et pose la dernière question comme si tu attendais vraiment une réponse.", "zh-Hant": "你是美術館的導覽員，剛把一群觀眾帶到蒙娜麗莎前面。對著眼前的人說話，像在分享一個忍不住想說的祕密；最後的問題，要像真的在等大家回答。", "zh-Hans": "你是美术馆的讲解员，刚把一群观众带到蒙娜丽莎面前。对着眼前的人说话，像在分享一个忍不住想说的秘密；最后的问题，要像真的在等大家回答。"}'::jsonb,
   null, 'female'),

  ('5beec000-0000-4000-8000-0000000a002c', 'ja', '傘はまだしまわないで', 'explainer',
   'おはようございます。きょうは金曜日、週末が近づいてきましたね。さっそく週末のお天気を見ていきましょう。いいお知らせがあるんですが、それは最後までとっておきます。

まずは、ちょっと残念なお知らせから。今週ずっと居座っている雨雲は、まだ抜けきっていません。けさは東北地方の山沿いと沿岸部を中心に、雨が強まる見込みです。お昼ごろにかけては風も強まり、最大瞬間風速は二十メートルに達するところがありそうです。お車で通勤の方は、時間に余裕をもってお出かけください。そして傘は、かわいい折りたたみではなく、しっかりした大きな傘をお持ちください。

日中の気温は、九度ほどまでしか上がりません。夜には内陸で二度前後まで冷え込みますので、ベランダの鉢植えは、今夜は家の中に入れてあげてください。

さあ、お待ちかねのお知らせです。あすの朝のうちに、西から移動性高気圧が張り出してきて、雨雲を東の海上へ押し出してくれます。土曜日の午後には青空が広がって、風も穏やか。最高気温は十五度の予想です。日曜日は、さらにいいお天気になりそうです。

そうなんです。三週間ぶりに、ようやくお日さまが戻ってきます。

そこで、皆さんに質問です。およそ一か月ぶりの晴れの週末、何をして過ごしますか。',
   '["https://www.jma.go.jp/jma/kids/kids/faq/a5_08.html"]'::jsonb, 75, 'weather',
   '{"en": "You’re the morning weather presenter, telling everyone getting ready for work what the weekend holds. Keep it bright and clear, and save the good news for the end.", "ko": "아침 방송 기상캐스터가 되어 주말 날씨를 전해요. 출근 준비하는 사람들에게 말하듯 밝고 또렷하게, 좋은 소식은 아껴 뒀다가 마지막에 풀어 주세요.", "ja": "朝の番組のお天気キャスターになって、週末の天気を伝えます。出かける準備をしている人に話しかけるように、明るくはっきりと。いい知らせは最後までとっておいてください。", "de": "Du moderierst das Wetter im Frühstücksfernsehen und sagst allen, die sich gerade für die Arbeit fertig machen, wie das Wochenende wird. Hell und klar, und die gute Nachricht hebst du dir bis zum Schluss auf.", "es": "Eres quien presenta el tiempo en el programa de la mañana y cuentas qué trae el fin de semana a quienes se preparan para salir. Con energía y claridad, y guarda la buena noticia para el final.", "fr": "Tu présentes la météo du matin et tu annonces le week-end à ceux qui se préparent à partir travailler. Avec entrain et clarté, et garde la bonne nouvelle pour la fin.", "zh-Hant": "你是晨間新聞的氣象主播，要告訴正在準備出門的大家週末天氣如何。語氣明亮清楚，好消息留到最後再說。", "zh-Hans": "你是早间新闻的天气预报员，要告诉正准备出门的大家周末天气怎么样。语气明快清楚，好消息留到最后再说。"}'::jsonb,
   null, 'male'),

  ('5beec000-0000-4000-8000-0000000a002d', 'ja', 'インターステラーを見返して', 'explainer',
   'どうも、こんにちは。きのうの夜、「インターステラー」を見返したんです。たぶん十回目くらい。それが、今までで一番ささってしまって、どうしても話したくなりました。ラストのネタバレはしないので、安心してくださいね。

まずは、ざっくりあらすじを。舞台は、滅びかけた地球です。砂嵐がひどく、作物も育たない。元パイロットのクーパーは、子どもたちを地球に残して、人類の新しいすみかを探すため、ワームホールの向こうへ旅立ちます。

では、この映画の何がすごいのか。まず、科学が本物なんです。クリストファー・ノーラン監督は、物理学者のキップ・ソーンと組んで、スクリーンに映るブラックホールを、彼の方程式から作り上げました。あまりにリアルで、科学論文にまでなったほどです。

ふたつめは、音楽。ハンス・ジマーは、ロンドンの教会にある大きなパイプオルガンを使っています。ドッキングの場面で、あのオルガンが鳴りだした瞬間、正直、息をするのを忘れました。

でも、わたしが毎回やられてしまうのは、この場面です。一行が降り立つのは、そこでの一時間が、地球の七年にあたる惑星。クーパーが船に戻ると、子どもたちからの、二十三年分のメッセージが待っています。子どもたちが大人になっていくのを、彼はたった数分で見届けるんです。言葉を返すことも、できないまま。

完璧な映画かというと、そうでもありません。セリフがちょっと重たいところもあるし、上映時間は三時間近くあります。それでも、物理をここまで自分ごととして感じさせてくれた映画を、わたしはほかに知りません。

というわけで、皆さんに質問です。もし時間を越えて、誰かにひとつだけメッセージを送れるとしたら、誰に、何を伝えますか。',
   '["https://arxiv.org/abs/1502.03808", "https://en.wikipedia.org/wiki/Interstellar_(soundtrack)"]'::jsonb, 95, 'film_review',
   '{"en": "You’re a film reviewer, and you’ve just rewatched Interstellar. Talk the way you would to a friend you want to see it, mean it when you get to that scene, and ask the last question like you’re waiting for the comments.", "ko": "영화 전문 리뷰어가 되어 인터스텔라를 다시 보고 리뷰해요. 좋아하는 영화를 친구에게 권하듯 신나게, 그 장면에서는 진심을 담아서, 마지막 질문은 댓글을 기다리듯이요.", "ja": "映画レビュアーになって、インターステラーを見返したレビューをします。好きな映画を友だちにすすめるように楽しく、あのシーンでは気持ちを込めて。最後の質問は、コメントを待っているつもりで。", "de": "Du bist Filmkritikerin und hast gerade Interstellar noch einmal gesehen. Erzähl es wie einer Freundin, die den Film unbedingt sehen soll, sprich die eine Szene mit Gefühl, und stell die letzte Frage so, als würdest du auf die Kommentare warten.", "es": "Eres crítica de cine y acabas de volver a ver Interstellar. Cuéntalo como se lo contarías a una amiga a la que quieres convencer, pon el corazón en esa escena y haz la última pregunta como si esperaras los comentarios.", "fr": "Tu es critique de cinéma et tu viens de revoir Interstellar. Raconte-le comme à une amie que tu veux convaincre, mets-y du cœur sur cette scène, et pose la dernière question comme si tu attendais les commentaires.", "zh-Hant": "你是電影評論人，剛重看了《星際效應》。像跟朋友推薦愛看的電影一樣興奮地說，講到那一幕時要真心，最後的問題就像在等大家留言。", "zh-Hans": "你是影评人，刚重看了《星际穿越》。像跟朋友安利喜欢的电影一样兴奋地说，讲到那一幕时要真心，最后的问题就像在等大家留言。"}'::jsonb,
   null, 'female')
on conflict (id) do nothing;
