-- German catches up with English (founder, 2026-11-15: every target language
-- gets the speech challenges English has). English has ten live challenges,
-- German had the first four. These are the six it was missing, one per English
-- original, each WRITTEN in German for the same role rather than translated:
--
--   ...0d0020  show_host     Teleshopping, a night cream     (en ...000020)
--   ...0d0024  acceptance    an acceptance speech            (en ...000024)
--   ...0d0025  podcast       opening an episode              (en ...000025)
--   ...0d002b  docent        the Mona Lisa                   (en ...00002b)
--   ...0d002c  weather       a grey week, a sunny weekend    (en ...00002c)
--   ...0d002d  film_review   Interstellar on a rewatch       (en ...00002d)
--
-- Same category key, genre, reference_voice and about the same length as
-- each English row (null there is set to 'female' here). The intros are the
-- English rows' intros in every app language, except the acceptance speech,
-- whose own is new.
--
-- The acceptance speech is ORIGINAL: a fictional actress after twenty-three
-- years of small parts. It neither copies nor translates any real speech and
-- names no real person.
--
-- Facts checked 2026-11-15:
--   * Mona Lisa: stolen on Monday 21 August 1911 while the Louvre was closed,
--     by Vincenzo Peruggia, who had worked there, carried out under his work
--     smock; noticed missing the next day (22 August); crowds came to look at
--     the empty wall; Picasso and Apollinaire were questioned by the police;
--     found in Florence in December 1913 and back in Paris in January 1914
--     ("mehr als zwei Jahre"). The English row says "a full day" before it
--     was noticed; this one says "erst am nächsten Tag", which every source
--     agrees with.
--   * Interstellar: Kip Thorne's equations behind the black hole and the 2015
--     Classical and Quantum Gravity paper (James, von Tunzelmann, Franklin,
--     Thorne); the organ is the Temple Church organ in London, played by
--     Roger Sayer; one hour on the planet is seven years on Earth; twenty-
--     three years of messages; 169 minutes ("fast drei Stunden"). No ending
--     spoilers.
--   * The weather forecast is made up: no real place, date or broadcaster,
--     km/h and Grad as a German forecast says them.
--
-- No digits, no em dashes, „…“ quotes. The intros never ask for a slow
-- reading. German has one season, so the insert trigger files these there.
-- Ids far from the other languages' running numbers (…0d00NN mirrors the
-- English last digits).

insert into public.speech_challenges (id, language, title, genre, body, sources, target_seconds, category, intro, link, reference_voice)
values
  ('5beec000-0000-4000-8000-0000000d0020', 'de', 'Strahlend aufwachen', 'product',
   'Meine Damen und Herren, bevor ich irgendetwas sage, schauen Sie mir ins Gesicht. Ganz nah. Kein Filter, kein Make-up, gar nichts. Nur meine echte Haut, am Ende eines sehr langen Tages.

Vor zwei Wochen war meine Haut noch müde. Trocken um die Nase, rau an den Wangen, und diese kleinen Fältchen an den Augen, jedes Mal, wenn ich gelacht habe. Kommt Ihnen das bekannt vor?

Das ist die Nachtcreme Morgentau. Schauen Sie genau hin, wie ich sie benutze. Auf die saubere Haut, nur ein kleines bisschen, so groß wie eine Erbse. Zwischen den Fingern anwärmen und sanft eindrücken. Nicht reiben. Drücken. Stirn, Wangen, Kinn und ein winziges bisschen unter die Augen.

Spüren Sie, wie leicht das ist? Sie duftet nach frischer Gurke und zieht ein wie Wasser. Kein klebriges Kopfkissen, kein glänzendes Gesicht.

Und während Sie schlafen, arbeitet sie für Sie. Sie hält die Feuchtigkeit die ganze Nacht in der Haut. Am Morgen ist Ihre Haut weich, prall und glatt, und das Make-up gleitet darüber wie Seide. An manchen Morgen lasse ich es ehrlich gesagt einfach weg.

Nur heute Abend bekommen Sie den großen Tiegel, eine Reisegröße für die Handtasche und eine Augencreme gratis dazu. Drei zum Preis von einem.

Ihre Haut arbeitet jeden Tag hart für Sie. Gönnen Sie ihr eine gute Nacht. Rufen Sie jetzt an!',
   '[]'::jsonb, 60, 'show_host',
   '{"en": "You’re a home-shopping host, live on air, selling one night cream. Look straight into the camera, show off your own skin with confidence, and talk as if the phones won’t stop ringing.", "ko": "생방송 홈쇼핑 쇼호스트가 되어 나이트 크림 하나를 파는 장면이에요. 카메라를 똑바로 보고, 내 피부를 보여주듯 자신 있게, 주문 전화가 쏟아지는 것처럼 말해 보세요.", "ja": "生放送のテレビ通販で、ナイトクリームをひとつ売り込む場面です。カメラをまっすぐ見て、自分の肌を見せるように自信を持って、注文の電話が鳴りやまない勢いで話してみましょう。", "de": "Du moderierst live im Teleshopping und verkaufst eine Nachtcreme. Schau direkt in die Kamera, zeig selbstbewusst deine eigene Haut und sprich, als würden die Telefone gar nicht mehr stillstehen.", "es": "Presentas un programa de teletienda en vivo y vendes una crema de noche. Mira directo a la cámara, presume de tu piel con seguridad y habla como si los teléfonos no pararan de sonar.", "fr": "Tu animes une émission de téléachat en direct et tu vends une crème de nuit. Regarde la caméra droit dans les yeux, montre ta peau avec assurance et parle comme si les téléphones n’arrêtaient pas de sonner.", "zh-Hant": "你是電視購物的直播主持人，要賣一款晚霜。直視鏡頭，自信地秀出自己的皮膚，講得像訂購電話響個不停一樣。", "zh-Hans": "你是电视购物的直播主持人，要卖一款晚霜。直视镜头，自信地展示自己的皮肤，讲得像订购电话响个不停一样。"}'::jsonb,
   null, 'female'),

  ('5beec000-0000-4000-8000-0000000d0024', 'de', 'Heute Abend wird Geschichte geschrieben', 'person',
   'Danke. Vielen, vielen Dank.

Ich habe mir diesen Moment so oft vorgestellt. Im Bus, beim Abwaschen, vor dem Spiegel mit einer Haarbürste in der Hand. Und jetzt stehe ich hier, und mir fällt kein einziger Satz mehr ein, den ich geübt habe.

Als ich angefangen habe, hat man mir gesagt, ich sei zu alt, zu leise, und mein Akzent sei zu stark. Dreiundzwanzig Jahre lang habe ich kleine Rollen gespielt. Die Kellnerin. Die Nachbarin. Die Frau, die im Hintergrund den Bus verpasst. Und ich habe jede einzelne davon geliebt.

An alle, die heute Abend zuschauen und denken, für mich ist es zu spät: Das stimmt nicht. Es ist nie zu spät. Gebt niemals auf.

Ich danke unserer Regisseurin, die an mich geglaubt hat, als ich es selbst nicht konnte. Ich danke dem ganzen Team, das bei Regen und Schnee mit mir gefroren hat. Und ich danke meinem Vater. Er ist einundachtzig, er sitzt gerade zu Hause vor dem Fernseher und weint wahrscheinlich mehr als ich. Papa, den hier bringe ich dir nach Hause.

Heute Abend wird hier Geschichte geschrieben, und zwar nicht nur meine. Also sagt mir: Wovon träumt ihr, seit ihr klein wart?',
   '[]'::jsonb, 90, 'acceptance',
   '{"en": "After twenty-three years of small parts, you’ve just won Best Actress. Thank everyone who got you here, let your voice catch when you get to your dad, and ask the last question to every single person watching.", "ko": "이십 년 넘게 단역만 하다가 드디어 여우주연상을 받은 배우가 되어 보세요. 여기까지 오게 해 준 사람들에게 고마움을 전하고, 아빠 이야기에서는 목이 메듯이, 마지막 질문은 지켜보는 모든 사람에게 던져 보세요.", "ja": "長年脇役を続けてきて、ついに主演女優賞を受け取った俳優になってみましょう。ここまで支えてくれた人たちにお礼を伝え、お父さんの話では胸がいっぱいになるように。最後の質問は、見ているすべての人に投げかけてください。", "de": "Du hast nach über zwanzig Jahren in kleinen Rollen gerade den Preis als beste Hauptdarstellerin gewonnen. Bedank dich bei allen, die dich bis hierher getragen haben, lass bei deinem Vater ruhig die Stimme wackeln und stell die letzte Frage an alle, die zuschauen.", "es": "Después de más de veinte años en papeles pequeños, acabas de ganar el premio a mejor actriz. Dales las gracias a todos los que te trajeron hasta aquí, deja que se te quiebre un poco la voz al hablar de tu papá y haz la última pregunta a todos los que te están viendo.", "fr": "Après plus de vingt ans de petits rôles, tu viens de remporter le prix de la meilleure actrice. Remercie tous ceux qui t’ont aidée à arriver jusqu’ici, laisse ta voix trembler un peu quand tu parles de ton père, et pose la dernière question à tous ceux qui te regardent.", "zh-Hant": "演了二十多年的小角色，你終於拿下最佳女主角獎。向一路支持你的人道謝，講到爸爸時讓聲音微微哽咽，最後的問題要問每一位正在看的人。", "zh-Hans": "演了二十多年的小角色，你终于拿下最佳女主角奖。向一路支持你的人道谢，讲到爸爸时让声音微微哽咽，最后的问题要问每一位正在看的人。"}'::jsonb,
   null, 'female'),

  ('5beec000-0000-4000-8000-0000000d0025', 'de', 'Willkommen zurück im Podcast', 'explainer',
   'Hey, hallo und herzlich willkommen zurück bei Kleine Siege, dem Podcast über die winzigen Dinge, die ganz leise dein Leben verändern. Schön, dass du wieder dabei bist.

Hol dir einen Kaffee und mach es dir gemütlich, denn die heutige Folge ist richtig gut. Es geht um die Fünf-Minuten-Regel. Die Idee ist ganz einfach. Wenn du auf etwas überhaupt keine Lust hast, sagst du dir: Ich mache das jetzt nur fünf Minuten. Mehr nicht. Fünf Minuten, und dann darf ich aufhören.

Und jetzt kommt das Lustige daran. Du hörst fast nie auf. Denn das Schwierigste war nie die Arbeit selbst. Es war das Anfangen.

Ich habe das letzten Monat beim Joggen ausprobiert. Ich hasse Joggen. Wirklich. Aber jeden Morgen habe ich mir gesagt: fünf Minuten, nur einmal um den Block. Und weißt du was? Heute Morgen bin ich eine halbe Stunde gelaufen und habe es nicht einmal gemerkt.

Heute habe ich einen Gast, der mit diesem kleinen Trick ein ganzes Buch geschrieben hat. Aber vorher noch eine kurze Frage an dich. Was ist die eine Sache, die du schon ewig vor dir herschiebst? Merk sie dir, denn am Ende dieser Folge fängst du damit an.

Dann legen wir mal los.',
   '[]'::jsonb, 60, 'podcast',
   '{"en": "You’re opening a new episode of your own podcast. Talk to one listener with headphones on, not to a crowd: relaxed and warm, with a smile in your voice.", "ko": "내 팟캐스트의 새 에피소드를 여는 장면이에요. 많은 사람이 아니라 이어폰을 낀 한 사람에게 말하듯, 편하고 다정하게, 목소리에 미소를 담아 말해 보세요.", "ja": "自分のポッドキャストの新しいエピソードを始める場面です。大勢ではなく、イヤホンで聴いているひとりに話しかけるように、リラックスして温かく、声に笑顔をのせてみましょう。", "de": "Du eröffnest eine neue Folge deines eigenen Podcasts. Sprich nicht zu einem Publikum, sondern zu einer Person mit Kopfhörern: locker, herzlich und mit einem Lächeln in der Stimme.", "es": "Abres un nuevo episodio de tu propio pódcast. No le hables a una multitud, sino a una persona con los auriculares puestos: con calma, con calidez y con una sonrisa en la voz.", "fr": "Tu ouvres un nouvel épisode de ton propre podcast. Ne parle pas à une foule, mais à une seule personne qui t’écoute avec ses écouteurs : sur un ton détendu et chaleureux, avec le sourire dans la voix.", "zh-Hant": "你正在為自己的 Podcast 開場新的一集。不是對一大群人，而是對戴著耳機的那一個人說話：輕鬆、溫暖，讓聲音帶著笑意。", "zh-Hans": "你正在为自己的播客开场新的一集。不是对一大群人，而是对戴着耳机的那一个人说话：轻松、温暖，让声音带着笑意。"}'::jsonb,
   null, 'female'),

  ('5beec000-0000-4000-8000-0000000d002b', 'de', 'Kommen Sie ruhig etwas näher', 'explainer',
   'So, meine Damen und Herren, kommen Sie ruhig etwas näher. Keine Scheu, vorne ist noch Platz.

Die meisten sind überrascht, wie klein sie ist. Und einige von Ihnen fragen sich bestimmt: Warum gerade dieses Bild? Warum kommt die ganze Welt hierher, wenn es nur ein paar Säle weiter größere, buntere und viel dramatischere Gemälde gibt?

Hier ist das Geheimnis. Vierhundert Jahre lang war sie in der Kunstwelt berühmt, und sonst kaum irgendwo. Dann, an einem ruhigen Montagmorgen im August neunzehnhundertelf, als das Museum geschlossen war, nahm ein Mann, der hier früher gearbeitet hatte, sie einfach von der Wand. Er versteckte das Bild unter seinem Arbeitskittel und spazierte hinaus.

Was glauben Sie, wann hat jemand gemerkt, dass sie fehlt? Erst am nächsten Tag.

Und genau da hat sich alles verändert. Zeitungen auf der ganzen Welt druckten ihr Gesicht auf die Titelseite. Menschen, die noch nie ein Museum betreten hatten, wussten plötzlich genau, wie sie aussieht. Die Polizei hat sogar den jungen Pablo Picasso befragt. Und hier, in diesem Museum, standen die Leute Schlange, nur um auf die leere Stelle an der Wand zu starren.

Mehr als zwei Jahre lang rätselte die ganze Welt, wo sie geblieben war. Als man sie schließlich in Florenz fand und nach Paris zurückbrachte, war sie kein gewöhnliches Gemälde mehr. Sie war das berühmteste Gesicht der Welt.

Also, schauen Sie sich dieses Lächeln noch ein letztes Mal an, und sagen Sie mir: Wenn sie nie gestohlen worden wäre, würden Sie dann heute hier stehen?',
   '["https://www.history.com/this-day-in-history/august-22/theft-of-mona-lisa-is-discovered", "https://www.history.com/news/the-heist-that-made-the-mona-lisa-famous", "https://www.history.com/this-day-in-history/december-12/mona-lisa-recovered-in-florence", "https://www.mentalfloss.com/art/pablo-picasso-was-suspected-of-stealing-the-mona-lisa"]'::jsonb,
   90, 'docent',
   '{"en": "You’re a museum docent, and you’ve just gathered a group in front of the Mona Lisa. Tell it like a secret you can’t wait to share, talk to the faces in front of you, and ask the last question as if you really want an answer.", "ko": "미술관 도슨트가 되어 모나리자 앞에 관람객들을 모았어요. 눈앞의 사람들에게 말을 걸듯, 꼭 들려주고 싶던 비밀을 털어놓는 기분으로 읽어 보세요. 마지막 질문은 정말 대답을 기다리듯이요.", "ja": "美術館のドーセントになって、モナ・リザの前にお客さんを集めたところです。目の前の人たちに話しかけるように、とっておきの秘密を打ち明ける気分で読んでみましょう。最後の質問は、本当に答えを待っているつもりで。", "de": "Du führst durchs Museum und hast gerade eine Gruppe vor der Mona Lisa versammelt. Sprich die Leute direkt an, als würdest du ein Geheimnis verraten, und stell die letzte Frage so, als wolltest du wirklich eine Antwort.", "es": "Eres guía de museo y acabas de reunir a un grupo frente a la Mona Lisa. Háblales directamente, como quien cuenta un secreto que llevaba tiempo guardando, y haz la última pregunta como si de verdad esperaras una respuesta.", "fr": "Tu es guide de musée et tu viens de rassembler un groupe devant la Joconde. Parle aux gens en face de toi, comme si tu leur confiais un secret, et pose la dernière question comme si tu attendais vraiment une réponse.", "zh-Hant": "你是美術館的導覽員，剛把一群觀眾帶到蒙娜麗莎前面。對著眼前的人說話，像在分享一個忍不住想說的祕密；最後的問題，要像真的在等大家回答。", "zh-Hans": "你是美术馆的讲解员，刚把一群观众带到蒙娜丽莎面前。对着眼前的人说话，像在分享一个忍不住想说的秘密；最后的问题，要像真的在等大家回答。"}'::jsonb,
   null, 'female'),

  ('5beec000-0000-4000-8000-0000000d002c', 'de', 'Packen Sie den Schirm noch nicht weg', 'explainer',
   'Guten Morgen und einen schönen Freitag! Werfen wir einen Blick aufs Wochenende, denn ich habe gute Nachrichten. Aber die verrate ich Ihnen erst am Schluss.

Zuerst das weniger Schöne. Das Regenband, das seit Tagen über uns liegt, ist noch nicht fertig mit uns. Heute Vormittag gibt es im Norden und an der Küste kräftige Schauer, und gegen Mittag kommen Böen bis sechzig Kilometer pro Stunde dazu. Wenn Sie mit dem Auto zur Arbeit fahren, planen Sie ein paar Minuten mehr ein. Und bitte: Nehmen Sie den großen Schirm mit, nicht den hübschen.

Am Nachmittag kommen die Temperaturen kaum über neun Grad hinaus, und in der Nacht kühlt es auf etwa zwei Grad ab. Wer Pflanzen auf dem Balkon hat, holt sie heute Abend besser rein.

Und jetzt kommt der Teil, auf den Sie gewartet haben. Morgen im Laufe des Vormittags setzt sich von Westen ein Hoch durch, und der Regen zieht nach Osten ab. Am Samstagnachmittag erwarten wir einen strahlend blauen Himmel, nur schwachen Wind und Höchstwerte um fünfzehn Grad. Und der Sonntag wird sogar noch schöner.

Sie haben richtig gehört. Nach drei grauen Wochen kommt endlich die Sonne zurück.

Deshalb meine Frage an Sie: Was machen Sie mit dem ersten sonnigen Wochenende seit fast einem Monat?',
   '[]'::jsonb, 75, 'weather',
   '{"en": "You’re the morning weather presenter, telling everyone getting ready for work what the weekend holds. Keep it bright and clear, and save the good news for the end.", "ko": "아침 방송 기상캐스터가 되어 주말 날씨를 전해요. 출근 준비하는 사람들에게 말하듯 밝고 또렷하게, 좋은 소식은 아껴 뒀다가 마지막에 풀어 주세요.", "ja": "朝の番組のお天気キャスターになって、週末の天気を伝えます。出かける準備をしている人に話しかけるように、明るくはっきりと。いい知らせは最後までとっておいてください。", "de": "Du moderierst das Wetter im Frühstücksfernsehen und sagst allen, die sich gerade für die Arbeit fertig machen, wie das Wochenende wird. Hell und klar, und die gute Nachricht hebst du dir bis zum Schluss auf.", "es": "Eres quien presenta el tiempo en el programa de la mañana y cuentas qué trae el fin de semana a quienes se preparan para salir. Con energía y claridad, y guarda la buena noticia para el final.", "fr": "Tu présentes la météo du matin et tu annonces le week-end à ceux qui se préparent à partir travailler. Avec entrain et clarté, et garde la bonne nouvelle pour la fin.", "zh-Hant": "你是晨間新聞的氣象主播，要告訴正在準備出門的大家週末天氣如何。語氣明亮清楚，好消息留到最後再說。", "zh-Hans": "你是早间新闻的天气预报员，要告诉正准备出门的大家周末天气怎么样。语气明快清楚，好消息留到最后再说。"}'::jsonb,
   null, 'male'),

  ('5beec000-0000-4000-8000-0000000d002d', 'de', 'Ich habe Interstellar noch mal gesehen', 'explainer',
   'Hallo zusammen und willkommen zurück! Ich habe mir gestern Abend Interstellar noch einmal angeschaut, ungefähr zum zehnten Mal, und ich muss einfach darüber reden, weil er mich diesmal härter getroffen hat als je zuvor. Keine Spoiler zum Ende, versprochen.

Kurz zur Handlung. Die Erde stirbt. Überall Staubstürme, die Ernten fallen aus, und ein ehemaliger Pilot namens Cooper lässt seine Kinder zurück. Er fliegt durch ein Wurmloch, um für die Menschheit ein neues Zuhause zu finden.

Was macht diesen Film so besonders? Erstens: Die Wissenschaft stimmt. Christopher Nolan hat mit dem Physiker Kip Thorne zusammengearbeitet, und das Schwarze Loch, das ihr auf der Leinwand seht, wurde aus seinen Gleichungen berechnet. Es sah so echt aus, dass es später sogar in einer Fachzeitschrift für Physik gelandet ist.

Zweitens: die Musik. Hans Zimmer hat eine riesige Kirchenorgel verwendet, und wenn sie in der Andockszene loslegt, ich schwöre, da habe ich vergessen zu atmen.

Aber es gibt eine Szene, die mich jedes einzelne Mal erwischt. Die Crew landet auf einem Planeten, auf dem eine Stunde sieben Jahren auf der Erde entspricht. Als Cooper zurück aufs Schiff kommt, warten dort dreiundzwanzig Jahre Nachrichten von seinen Kindern auf ihn. Er sieht sie in ein paar Minuten erwachsen werden und kann ihnen kein einziges Wort antworten.

Ist der Film perfekt? Nein. Manche Dialoge sind ein bisschen dick aufgetragen, und er dauert fast drei Stunden. Aber ich habe noch nie einen Film gesehen, der Physik so persönlich wirken lässt.

Deshalb meine Frage an euch: Wenn ihr jemandem eine Nachricht durch die Zeit schicken könntet, wem würdet ihr schreiben, und was würdet ihr sagen?',
   '["https://doi.org/10.1088/0264-9381/32/6/065001", "https://www.sciencedaily.com/releases/2015/02/150213081615.htm", "https://www.thediapason.com/content/interstellar-10-comes-united-states"]'::jsonb,
   95, 'film_review',
   '{"en": "You’re a film reviewer, and you’ve just rewatched Interstellar. Talk the way you would to a friend you want to see it, mean it when you get to that scene, and ask the last question like you’re waiting for the comments.", "ko": "영화 전문 리뷰어가 되어 인터스텔라를 다시 보고 리뷰해요. 좋아하는 영화를 친구에게 권하듯 신나게, 그 장면에서는 진심을 담아서, 마지막 질문은 댓글을 기다리듯이요.", "ja": "映画レビュアーになって、インターステラーを見返したレビューをします。好きな映画を友だちにすすめるように楽しく、あのシーンでは気持ちを込めて。最後の質問は、コメントを待っているつもりで。", "de": "Du bist Filmkritikerin und hast gerade Interstellar noch einmal gesehen. Erzähl es wie einer Freundin, die den Film unbedingt sehen soll, sprich die eine Szene mit Gefühl, und stell die letzte Frage so, als würdest du auf die Kommentare warten.", "es": "Eres crítica de cine y acabas de volver a ver Interstellar. Cuéntalo como se lo contarías a una amiga a la que quieres convencer, pon el corazón en esa escena y haz la última pregunta como si esperaras los comentarios.", "fr": "Tu es critique de cinéma et tu viens de revoir Interstellar. Raconte-le comme à une amie que tu veux convaincre, mets-y du cœur sur cette scène, et pose la dernière question comme si tu attendais les commentaires.", "zh-Hant": "你是電影評論人，剛重看了《星際效應》。像跟朋友推薦愛看的電影一樣興奮地說，講到那一幕時要真心，最後的問題就像在等大家留言。", "zh-Hans": "你是影评人，刚重看了《星际穿越》。像跟朋友安利喜欢的电影一样兴奋地说，讲到那一幕时要真心，最后的问题就像在等大家留言。"}'::jsonb,
   null, 'female')
on conflict (id) do nothing;
