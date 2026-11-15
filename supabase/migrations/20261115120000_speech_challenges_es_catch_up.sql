-- Spanish catches up with English's speech challenges (founder, 2026-11-15:
-- every target language gets the challenges English has). English has ten
-- live, Spanish had the first four; these are the other six, one per English
-- original, each WRITTEN in Spanish for the same role and shape, never
-- translated. Same category key, genre and target length as the English row;
-- ids mirror the English last digits (…0020 → …0e0020).
--
-- Neutral Spanish for Latin America and Spain: tú to the learner, ustedes to
-- a group or an audience (never vosotros), never the verb coger, and where a
-- word had to be chosen, the Latin American one (the app's Spanish voices
-- are Mexican): cuadra, manejar, celular, bolsa; a pea-sized dab is "del tamaño de una perla", since chícharo and guisante each read as one region.
-- Numbers as words, no digits; no em dashes; the intros never ask for a slow
-- reading. Spanish has only Season 1, so the season trigger puts all six
-- there, live.
--
--   * …0e0020 show host, night cream (EN …0020). A made-up product.
--   * …0e0024 acceptance (EN …0024). NOT Michelle Yeoh's words and not a
--     translation of them: an original speech by a fictional winner, no real
--     names, no film title. Nothing in it is a fact to check.
--   * …0e0025 podcast host, the five-minute rule (EN …0025). A made-up show.
--   * …0e002b docent, the Mona Lisa (EN …002b). Checked 2026-11-15 against
--     History.com, Sortir à Paris and the sources in `sources`: stolen on
--     Monday 21 August 1911 while the Louvre was closed, by Vincenzo
--     Peruggia, a former Louvre worker, under his white work smock; missed
--     only the next morning (Louis Béroud, Tuesday 22 August), so the script
--     says "hasta el día siguiente", not "un día entero"; Picasso questioned
--     and cleared; when the Louvre reopened crowds came to stare at the empty
--     wall (Kafka and Max Brod among them); recovered in Florence in December
--     1913 (more than two years), back in the Louvre on 4 January 1914.
--   * …0e002c weather presenter (EN …002c). A made-up forecast, no real
--     place, date or broadcaster, like the English one; wind in km/h
--     (sixty-five, about the English forty mph) and Celsius.
--   * …0e002d film critic, Interstellar (EN …002d, category `film_review` as
--     set by 20261115100000). Checked 2026-11-15: Kip Thorne and the 2015
--     Classical and Quantum Gravity paper (James, von Tunzelmann, Franklin,
--     Thorne) on the film's black hole; the organ is Temple Church's,
--     London, played by Roger Sayer; one hour on Miller's planet is seven
--     years on Earth and twenty-three years of messages wait for Cooper
--     (the English row's checks, kept); 169 minutes. No ending spoilers. The
--     film is released as "Interstellar" in Spain and Latin America alike.
--
-- reference_voice as the English row: female everywhere English is female or
-- null, male for the weather presenter.

insert into public.speech_challenges (id, language, title, genre, body, sources, target_seconds, category, intro, link, reference_voice)
values
  ('5beec000-0000-4000-8000-0000000e0020', 'es', 'Despierta radiante', 'product',
   'Amigas, amigos, antes de decir cualquier cosa, mírenme la cara. De cerca. Sin filtro, sin base, sin nada. Esta es mi piel de verdad, al final de un día larguísimo.

Hace dos semanas, mi piel estaba cansada. Reseca alrededor de la nariz, áspera en las mejillas, y con estas rayitas junto a los ojos cada vez que sonreía. ¿Les suena?

Esta es la crema de noche Rocío Matinal. Miren cómo la uso. Con la piel limpia, tomo poquito, del tamaño de una perla. La caliento entre los dedos y la aplico presionando. No froten. Presionen. Frente, mejillas, barbilla, y un toquecito debajo de los ojos.

¿Ven qué ligera es? Huele a pepino fresco y se absorbe como agua. Nada de almohada pegajosa, nada de cara brillosa.

Y mientras duermes, ella trabaja. Retiene la hidratación toda la noche, y en la mañana tu piel amanece suave, firme y lisa, y el maquillaje se desliza como seda. Hay mañanas en que, de verdad, ni me maquillo.

Solo esta noche te llevas el frasco grande, uno de viaje para tu bolsa y, de regalo, un contorno de ojos. Tres por el precio de uno.

Tu piel trabaja por ti todos los días. Regálale una buena noche. ¿Qué esperas? ¡Llama ya!',
   '[]'::jsonb, 60, 'show_host',
   '{"en": "You’re a home-shopping host, live on air, selling one night cream in Spanish. Look straight into the camera, show off your own skin with confidence, and talk as if the phones won’t stop ringing.", "ko": "스페인어 생방송 홈쇼핑 쇼호스트가 되어 나이트 크림 하나를 파는 장면이에요. 카메라를 똑바로 보고, 내 피부를 보여주듯 자신 있게, 주문 전화가 쏟아지는 것처럼 말해 보세요.", "ja": "スペイン語のテレビ通販の生放送で、ナイトクリームをひとつ売り込む場面です。カメラをまっすぐ見て、自分の肌を見せるように自信を持って、注文の電話が鳴りやまない勢いで話してみましょう。", "de": "Du moderierst live im spanischen Teleshopping und verkaufst eine Nachtcreme. Schau direkt in die Kamera, zeig selbstbewusst deine eigene Haut und sprich, als würden die Telefone gar nicht mehr stillstehen.", "es": "Presentas un programa de teletienda en vivo y vendes una crema de noche. Mira directo a la cámara, presume tu piel con seguridad y habla como si los teléfonos no pararan de sonar.", "fr": "Tu animes une émission de téléachat en direct, en espagnol, et tu vends une crème de nuit. Regarde la caméra droit dans les yeux, montre ta peau avec assurance et parle comme si les téléphones n’arrêtaient pas de sonner.", "zh-Hant": "你是西語電視購物的直播主持人，要賣一款晚霜。直視鏡頭，自信地秀出自己的皮膚，講得像訂購電話響個不停一樣。", "zh-Hans": "你是西语电视购物的直播主持人，要卖一款晚霜。直视镜头，自信地展示自己的皮肤，讲得像订购电话响个不停一样。"}'::jsonb,
   null, 'female'),

  ('5beec000-0000-4000-8000-0000000e0024', 'es', 'Hoy estamos haciendo historia', 'person',
   'Gracias. Muchísimas gracias.

Ay, no sé ni por dónde empezar. Hace veinte años yo era la muchacha del fondo, la que pasaba detrás de la protagonista con una bandeja en la mano. Sin texto, sin nombre en los créditos. Y hoy estoy aquí, con esto en las manos.

A todas las niñas y los niños que me están viendo desde un pueblo pequeño, desde una cocina, desde un celular prestado: sí se puede. Que nadie les diga que su acento, su cara o su apellido no caben en una pantalla. Caben. Aquí están.

Gracias a la Academia. Gracias a mi directora, que me eligió cuando nadie más quería arriesgarse conmigo. Gracias a todo el equipo, a cada persona que cargó cables a las cinco de la mañana para que esta película existiera.

Y este premio es para mi mamá. Ella trabajó de noche durante treinta años para que yo pudiera estudiar de día. Mamá, ya sé que estás llorando en la sala con toda la familia. Yo también. Esto es tuyo. Te lo llevo a casa.

Hoy no gana solo una actriz. Hoy gana toda la gente que pasó años en el fondo esperando su turno.

Así que dime, tú que me estás escuchando: ¿cuál es ese sueño que todavía guardas en silencio? Sácalo. Porque hoy estamos haciendo historia. Gracias.',
   '[]'::jsonb, 90, 'acceptance',
   '{"en": "You’ve just won the big award, and this is your acceptance speech, in Spanish. Picture the statue in your hand: say the first lines to every kid watching, slow down when you get to your mom, and let the last line ring out.", "ko": "큰 상을 받고 스페인어로 수상 소감을 말하는 장면이에요. 트로피를 손에 든 순간처럼, 앞부분은 지켜보는 아이들에게, 엄마 이야기는 천천히, 마지막 한 줄은 크게 말해 보세요.", "ja": "大きな賞を受け取り、スペイン語で受賞スピーチをする場面です。トロフィーを手にしたつもりで、前半は見ている子どもたちに語りかけ、お母さんの話はゆっくり、最後の一言は力強く話してみましょう。", "de": "Du hast gerade den großen Preis gewonnen und hältst deine Dankesrede auf Spanisch. Stell dir die Statue in deiner Hand vor: Sprich die ersten Sätze zu allen Kindern, die zuschauen, werde langsamer, wenn es um deine Mutter geht, und lass den letzten Satz richtig klingen.", "es": "Acabas de ganar el gran premio y este es tu discurso de agradecimiento. Imagina la estatuilla en tu mano: dile las primeras frases a cada niño que te está viendo, baja el ritmo cuando llegues a tu mamá y deja que la última frase resuene.", "fr": "Tu viens de remporter le grand prix, et voici ton discours de remerciement, en espagnol. Imagine la statuette dans ta main : adresse les premières phrases à tous les enfants qui regardent, ralentis quand tu parles de ta mère, et laisse la dernière phrase résonner.", "zh-Hant": "你剛拿下大獎，要用西班牙語發表得獎感言。想像獎座就在你手上：前面的話說給正在看的孩子們聽，講到媽媽時放慢，最後一句大聲說出來。", "zh-Hans": "你刚拿下大奖，要用西班牙语发表获奖感言。想象奖杯就在你手上：前面的话说给正在看的孩子们听，讲到妈妈时放慢，最后一句大声说出来。"}'::jsonb,
   null, 'female'),

  ('5beec000-0000-4000-8000-0000000e0025', 'es', 'Bienvenidos de nuevo al programa', 'explainer',
   'Hola, hola, ¿qué tal? Bienvenidos de nuevo a Pequeñas Victorias, el pódcast de las cosas chiquitas que, sin hacer ruido, te cambian la vida. Yo soy tu anfitriona y me da muchísimo gusto que estés aquí.

Prepárate un cafecito y ponte cómoda, ponte cómodo, porque el episodio de hoy está buenísimo. Vamos a hablar de la regla de los cinco minutos. La idea es esta. Cuando no tienes ganas de hacer algo, te dices: solo cinco minutos. Nada más. Cinco minutos, y si quiero, lo dejo.

Y aquí viene lo curioso. Casi nunca lo dejas. Porque lo difícil nunca fue el trabajo. Lo difícil era empezar.

Yo lo probé el mes pasado con correr. Odio correr. De verdad, lo odio. Pero cada mañana me decía: cinco minutos, solo una vuelta a la cuadra. ¿Y saben qué? Hoy en la mañana corrí media hora y ni me di cuenta.

Hoy tengo una invitada que usó este truquito para escribir un libro entero. Pero antes, una pregunta rápida para ti. ¿Qué es eso que llevas semanas posponiendo? Guárdalo en la mente, porque al final de este episodio lo vas a empezar.

¡Vamos allá!',
   '[]'::jsonb, 60, 'podcast',
   '{"en": "You’re opening a new episode of your own Spanish podcast. Talk to one listener with headphones on, not to a crowd: relaxed and warm, with a smile in your voice.", "ko": "내 스페인어 팟캐스트의 새 에피소드를 여는 장면이에요. 많은 사람이 아니라 이어폰을 낀 한 사람에게 말하듯, 편하고 다정하게, 목소리에 미소를 담아 말해 보세요.", "ja": "自分のスペイン語ポッドキャストの新しいエピソードを始める場面です。大勢ではなく、イヤホンで聴いているひとりに話しかけるように、リラックスして温かく、声に笑顔をのせてみましょう。", "de": "Du eröffnest eine neue Folge deines eigenen spanischen Podcasts. Sprich nicht zu einem Publikum, sondern zu einer Person mit Kopfhörern: locker, herzlich und mit einem Lächeln in der Stimme.", "es": "Abres un nuevo episodio de tu propio pódcast. No le hables a una multitud, sino a una persona con los audífonos puestos: relajada, cálida y con una sonrisa en la voz.", "fr": "Tu ouvres un nouvel épisode de ton propre podcast en espagnol. Ne parle pas à une foule, mais à une seule personne qui t’écoute avec ses écouteurs : sur un ton détendu et chaleureux, avec le sourire dans la voix.", "zh-Hant": "你正在為自己的西語 Podcast 開場新的一集。不是對一大群人，而是對戴著耳機的那一個人說話：輕鬆、溫暖，讓聲音帶著笑意。", "zh-Hans": "你正在为自己的西语播客开场新的一集。不是对一大群人，而是对戴着耳机的那一个人说话：轻松、温暖，让声音带着笑意。"}'::jsonb,
   null, 'female'),

  ('5beec000-0000-4000-8000-0000000e002b', 'es', 'Acérquense un poquito más', 'explainer',
   'Muy bien, acérquense un poquito más. No sean tímidos, que adelante hay lugar.

A casi todo el mundo le sorprende lo pequeña que es. Y seguro que más de uno se está preguntando: ¿por qué esta? ¿Por qué viene el mundo entero a ver este cuadro, si en la sala de al lado hay pinturas más grandes, más brillantes y mucho más dramáticas?

Les cuento el secreto. Durante cuatrocientos años, ella fue famosa en el mundo del arte y en casi ningún otro lugar. Hasta que un lunes tranquilo de agosto de mil novecientos once, con el museo cerrado, un hombre que había trabajado aquí la descolgó de la pared y salió por la puerta con el cuadro escondido debajo de su bata de trabajo.

¿Cuánto creen que tardaron en darse cuenta de que no estaba? Hasta el día siguiente.

Y ahí cambió todo. Los periódicos de todo el mundo pusieron su cara en primera plana, y gente que jamás había pisado un museo de repente sabía exactamente cómo era. La policía hasta interrogó a un joven Pablo Picasso. Y aquí, en este mismo museo, la gente hacía fila solo para mirar el hueco vacío en la pared.

Durante más de dos años, el mundo entero se preguntó dónde estaba. Así que, cuando por fin la encontraron en Florencia y la trajeron de vuelta a París, ya no era solo un cuadro. Era la cara más famosa del planeta.

Así que miren una vez más esa sonrisa y díganme: si nadie la hubiera robado, ¿estarían ustedes aquí hoy?',
   '["https://www.history.com/this-day-in-history/august-22/theft-of-mona-lisa-is-discovered", "https://www.sortiraparis.com/en/what-to-visit-in-paris/history-heritage/articles/257946-louvre-museum-mona-lisa-theft-1911-august-22-paris", "https://www.npr.org/2011/07/30/138800110/the-theft-that-made-the-mona-lisa-a-masterpiece", "https://www.mentalfloss.com/art/pablo-picasso-was-suspected-of-stealing-the-mona-lisa"]'::jsonb,
   90, 'docent',
   '{"en": "You’re a museum docent, and you’ve just gathered a Spanish-speaking group in front of the Mona Lisa. Tell it like a secret you can’t wait to share, talk to the faces in front of you, and ask the last question as if you really want an answer.", "ko": "미술관 도슨트가 되어 모나리자 앞에 스페인어권 관람객들을 모았어요. 눈앞의 사람들에게 말을 걸듯, 꼭 들려주고 싶던 비밀을 털어놓는 기분으로 읽어 보세요. 마지막 질문은 정말 대답을 기다리듯이요.", "ja": "美術館のドーセントになって、モナ・リザの前にスペイン語圏のお客さんを集めたところです。目の前の人たちに話しかけるように、とっておきの秘密を打ち明ける気分で読んでみましょう。最後の質問は、本当に答えを待っているつもりで。", "de": "Du führst durchs Museum und hast gerade eine spanischsprachige Gruppe vor der Mona Lisa versammelt. Sprich die Leute direkt an, als würdest du ein Geheimnis verraten, und stell die letzte Frage so, als wolltest du wirklich eine Antwort.", "es": "Eres guía de museo y acabas de reunir a un grupo frente a la Mona Lisa. Háblales directamente, como quien cuenta un secreto que se moría por compartir, y haz la última pregunta como si de verdad esperaras una respuesta.", "fr": "Tu es guide de musée et tu viens de rassembler un groupe hispanophone devant la Joconde. Parle aux gens en face de toi, comme si tu leur confiais un secret, et pose la dernière question comme si tu attendais vraiment une réponse.", "zh-Hant": "你是美術館的導覽員，剛把一群說西班牙語的觀眾帶到蒙娜麗莎前面。對著眼前的人說話，像在分享一個忍不住想說的祕密；最後的問題，要像真的在等大家回答。", "zh-Hans": "你是美术馆的讲解员，刚把一群说西班牙语的观众带到蒙娜丽莎面前。对着眼前的人说话，像在分享一个忍不住想说的秘密；最后的问题，要像真的在等大家回答。"}'::jsonb,
   null, 'female'),

  ('5beec000-0000-4000-8000-0000000e002c', 'es', 'No guardes el paraguas todavía', 'explainer',
   'Buenos días a todos y feliz viernes. Vamos a ver cómo viene el fin de semana, porque tengo una buena noticia, y los voy a hacer esperar un poquito.

Primero, lo no tan bueno. Esa franja de lluvias que tenemos encima desde el lunes todavía no se va. Esta mañana esperamos aguaceros fuertes en el norte y en la costa, con rachas de viento de hasta sesenta y cinco kilómetros por hora a la hora de la comida. Si vas a manejar al trabajo, sal unos minutos antes, y por favor, llévate el paraguas grande, no el bonito.

Por la tarde, a la temperatura le va a costar pasar de los nueve grados, y en la noche va a bajar a unos dos. Así que si tienes plantas en el balcón, mételas a la casa.

Y ahora sí, lo que estaban esperando. Mañana, a media mañana, entra un sistema de alta presión desde el oeste y se lleva todo esto mar adentro. Para el sábado en la tarde esperamos cielos despejados, viento ligero y máximas de quince grados. Y el domingo pinta todavía mejor.

Así es. Después de tres semanas grises, por fin vuelve el sol.

Así que aquí va mi pregunta para ti. ¿Qué vas a hacer con el primer fin de semana soleado en casi un mes?',
   '[]'::jsonb, 75, 'weather',
   '{"en": "You’re the morning weather presenter on Spanish-language TV, telling everyone getting ready for work what the weekend holds. Keep it bright and clear, and save the good news for the end.", "ko": "스페인어 아침 방송 기상캐스터가 되어 주말 날씨를 전해요. 출근 준비하는 사람들에게 말하듯 밝고 또렷하게, 좋은 소식은 아껴 뒀다가 마지막에 풀어 주세요.", "ja": "スペイン語の朝の番組のお天気キャスターになって、週末の天気を伝えます。出かける準備をしている人に話しかけるように、明るくはっきりと。いい知らせは最後までとっておいてください。", "de": "Du moderierst das Wetter im spanischsprachigen Frühstücksfernsehen und sagst allen, die sich gerade für die Arbeit fertig machen, wie das Wochenende wird. Hell und klar, und die gute Nachricht hebst du dir bis zum Schluss auf.", "es": "Presentas el pronóstico del tiempo en el noticiero de la mañana y les cuentas qué trae el fin de semana a quienes se preparan para salir. Con energía y claridad, y guarda la buena noticia para el final.", "fr": "Tu présentes la météo du matin sur une chaîne hispanophone et tu annonces le week-end à ceux qui se préparent à partir travailler. Avec entrain et clarté, et garde la bonne nouvelle pour la fin.", "zh-Hant": "你是西語晨間新聞的氣象主播，要告訴正在準備出門的大家週末天氣如何。語氣明亮清楚，好消息留到最後再說。", "zh-Hans": "你是西语早间新闻的天气预报员，要告诉正准备出门的大家周末天气怎么样。语气明快清楚，好消息留到最后再说。"}'::jsonb,
   null, 'male'),

  ('5beec000-0000-4000-8000-0000000e002d', 'es', 'Volví a ver Interstellar', 'explainer',
   'Hola a todos, bienvenidos de nuevo. Anoche volví a ver Interstellar, creo que por décima vez, y necesito hablar de ella, porque me pegó más fuerte que nunca. Nada de spoilers del final, lo prometo.

Rapidito, de qué va. La Tierra se está muriendo. Tormentas de polvo por todas partes, cosechas que se pierden, y un expiloto llamado Cooper deja a sus hijos para atravesar un agujero de gusano y buscarle a la humanidad un nuevo hogar.

Ahora, ¿qué la hace tan especial? Primero, la ciencia es de verdad. Christopher Nolan trabajó con el físico Kip Thorne, y el agujero negro que ves en pantalla se construyó a partir de sus ecuaciones. Quedó tan real que terminó en artículos científicos.

Segundo, la música. Hans Zimmer usó un órgano de iglesia enorme, y cuando entra en la escena del acoplamiento, te lo juro, se me olvidó respirar.

Pero hay una escena que me destroza cada vez. Llegan a un planeta donde una hora equivale a siete años en la Tierra. Cuando Cooper vuelve a la nave, lo esperan veintitrés años de mensajes de sus hijos. Los ve crecer en unos minutos, y no puede contestarles ni una palabra.

¿Es perfecta? No. Algunos diálogos son un poco pesados, y dura casi tres horas. Pero nunca había visto una película que hiciera sentir la física tan personal.

Así que te pregunto. Si pudieras mandarle un mensaje a alguien a través del tiempo, ¿a quién sería, y qué le dirías?',
   '["https://arxiv.org/abs/1502.03808", "https://en.wikipedia.org/wiki/Interstellar_(soundtrack)", "https://gramophone.co.uk/choir-and-organ/news/article/interstellar-at-10"]'::jsonb,
   95, 'film_review',
   '{"en": "You’re a film critic with a Spanish-language channel, and you’ve just rewatched Interstellar. Talk the way you would to a friend you want to see it, mean it when you get to that scene, and ask the last question like you’re waiting for the comments.", "ko": "스페인어로 영화를 리뷰하는 평론가가 되어 인터스텔라를 다시 보고 리뷰해요. 좋아하는 영화를 친구에게 권하듯 신나게, 그 장면에서는 진심을 담아서, 마지막 질문은 댓글을 기다리듯이요.", "ja": "スペイン語で映画を語るレビュアーになって、インターステラーを見返したレビューをします。好きな映画を友だちにすすめるように楽しく、あのシーンでは気持ちを込めて。最後の質問は、コメントを待っているつもりで。", "de": "Du bist Filmkritikerin mit einem spanischsprachigen Kanal und hast gerade Interstellar noch einmal gesehen. Erzähl es wie einer Freundin, die den Film unbedingt sehen soll, sprich die eine Szene mit Gefühl, und stell die letzte Frage so, als würdest du auf die Kommentare warten.", "es": "Eres crítica de cine y acabas de volver a ver Interstellar. Cuéntalo como se lo contarías a una amiga a la que quieres convencer, ponle el corazón a esa escena y haz la última pregunta como si esperaras los comentarios.", "fr": "Tu es critique de cinéma sur une chaîne en espagnol et tu viens de revoir Interstellar. Raconte-le comme à une amie que tu veux convaincre, mets-y du cœur sur cette scène, et pose la dernière question comme si tu attendais les commentaires.", "zh-Hant": "你是用西班牙語評電影的影評人，剛重看了《星際效應》。像跟朋友推薦愛看的電影一樣興奮地說，講到那一幕時要真心，最後的問題就像在等大家留言。", "zh-Hans": "你是用西班牙语评电影的影评人，刚重看了《星际穿越》。像跟朋友安利喜欢的电影一样兴奋地说，讲到那一幕时要真心，最后的问题就像在等大家留言。"}'::jsonb,
   null, 'female')
on conflict (id) do nothing;
