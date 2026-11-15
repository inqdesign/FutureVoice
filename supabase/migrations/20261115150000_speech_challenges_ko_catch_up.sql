-- Korean catches up with English's speech challenges (2026-11-15).
--
-- English has ten live challenges; Korean had the first four. These are the
-- other six, one per English original, each WRITTEN in Korean for the same
-- role and shape (same category, target_seconds, genre and reference_voice),
-- never translated. Numbers are written as words, no digits, no em dashes,
-- and no intro asks for a slow reading. Korean is still on Season 1, so the
-- insert trigger files them there and they are live at once.
--
-- ids: 5beec000-0000-4000-8000-0000000c00NN, NN = the English original's
-- running number (20, 24, 25, 2b, 2c, 2d).

-- Home-shopping host (en 'Wake up glowing', ...0020). A made-up product (Morning Dew, as the English); no claims to check beyond what the English makes. Written in live home-shopping talk: 고객님, 오늘 방송에서만, 지금 바로 전화 주세요.
insert into public.speech_challenges (id, language, title, genre, body, sources, target_seconds, category, intro, link, reference_voice)
values
  ('5beec000-0000-4000-8000-0000000c0020', 'ko', '자고 일어나면 달라져요', 'product',
   '고객님, 말씀 드리기 전에 제 얼굴부터 봐 주세요. 카메라 더 가까이요. 필터도, 파운데이션도 없어요. 하루 종일 일하고 난 제 맨 피부예요.

솔직히 보름 전만 해도 제 피부, 많이 지쳐 있었거든요. 코 옆은 건조하고, 볼은 까칠하고, 웃을 때마다 눈가에 잔주름이 자글자글했어요. 고객님도 그러시죠?

이게 바로 모닝듀 나이트 크림이에요. 바르는 법 보여 드릴게요. 세안하고, 콩알만큼 덜어서, 손끝으로 데운 다음, 꾹꾹 눌러 주세요. 문지르지 마시고요, 누르세요. 이마, 양 볼, 턱, 그리고 눈 밑에 아주 조금.

정말 가볍죠? 오이 향이 산뜻하게 나고, 물처럼 쏙 스며들어요. 베개에 묻어나지도 않고, 번들거리지도 않아요.

진짜 일은 주무시는 동안 해요. 밤새 수분을 꽉 잡아 줘서, 아침에 일어나면 피부가 촉촉하고 탱탱하고 매끈해요. 화장도 실크처럼 착 붙고요. 어떤 날은 저, 그냥 맨얼굴로 나가요.

오늘 방송에서만, 대용량 본품에, 여행용 하나, 아이크림까지 드려요. 하나 가격에 세 개예요.

우리 피부, 매일 정말 고생하잖아요. 오늘 밤만큼은 제대로 쉬게 해 주세요. 지금 바로 전화 주세요!',
   '[]'::jsonb, 60, 'show_host',
   '{"ko": "생방송 홈쇼핑 쇼호스트가 되어 나이트 크림 하나를 파는 장면이에요. 카메라를 똑바로 보고, 내 피부를 보여 주듯 자신 있게, 주문 전화가 쏟아지는 것처럼 말해 보세요.", "en": "You’re a home-shopping host on live TV, selling one night cream to Korean viewers. Look straight into the camera, show off your own skin with confidence, and talk as if the phones won’t stop ringing.", "ja": "韓国の生放送テレビ通販で、ナイトクリームをひとつ売り込む場面です。カメラをまっすぐ見て、自分の肌を見せるように自信を持って、注文の電話が鳴りやまない勢いで話してみましょう。", "de": "Du moderierst live im koreanischen Teleshopping und verkaufst eine Nachtcreme. Schau direkt in die Kamera, zeig selbstbewusst deine eigene Haut und sprich, als würden die Telefone gar nicht mehr stillstehen.", "es": "Presentas un programa de teletienda en vivo en Corea y vendes una crema de noche. Mira directo a la cámara, presume de tu piel con seguridad y habla como si los teléfonos no pararan de sonar.", "fr": "Tu animes une émission de téléachat en direct à la télé coréenne et tu vends une crème de nuit. Regarde la caméra droit dans les yeux, montre ta peau avec assurance et parle comme si les téléphones n’arrêtaient pas de sonner.", "zh-Hant": "你是韓國電視購物的直播主持人，要賣一款晚霜。直視鏡頭，自信地秀出自己的皮膚，講得像訂購電話響個不停一樣。", "zh-Hans": "你是韩国电视购物的直播主持人，要卖一款晚霜。直视镜头，自信地展示自己的皮肤，讲得像订购电话响个不停一样。"}'::jsonb,
   null, 'female')
on conflict (id) do nothing;

-- Acceptance (en 'This is history in the making', ...0024, Michelle Yeoh). NOT her speech and not a translation: an original speech by a fictional actress who got her first lead at forty-six, with the same beats (the kids watching, never too late, the crew, the mom watching at home, where the career began). No real person, film, award or ceremony is named. Avoids lines from well-known Korean acceptance speeches.
insert into public.speech_challenges (id, language, title, genre, body, sources, target_seconds, category, intro, link, reference_voice)
values
  ('5beec000-0000-4000-8000-0000000c0024', 'ko', '오늘, 새로운 역사를 썼습니다', 'person',
   '감사합니다. 정말, 감사합니다.

지금 텔레비전 앞에서 이 장면을 보고 있을, 저처럼 작은 바닷가 마을에서 큰 꿈을 꾸는 아이들에게 먼저 말하고 싶어요. 이 상은 여러분 거예요. 꿈은 크게 꾸세요. 꿈은, 정말로 이루어져요.

그리고 이제 너무 늦었다고 생각하시는 분들. 누가 뭐라고 해도, 절대 포기하지 마세요. 저는 마흔여섯 살에 처음으로 주인공을 맡았습니다.

끝까지 저를 믿어 주신 감독님, 제작사 식구들, 그리고 그 추운 겨울 내내 현장을 지켜 준 우리 배우들과 스태프 여러분. 여러분이 없었으면 저는 오늘 이 자리에 서 있지 못했을 거예요.

그래도 이 상은 꼭 우리 엄마한테 바치고 싶어요. 그리고 세상의 모든 엄마들께요. 엄마들이야말로 진짜 영웅이니까요. 엄마들이 없었으면, 오늘 여기 있는 우리 중 누구도 없었을 거예요.

우리 엄마, 올해 여든셋이세요. 지금 목포 집에서 동생들이랑 텔레비전 앞에 앉아 계실 거예요. 엄마, 보고 있지? 이거 들고 바로 내려갈게. 사랑해.

그리고 스무 살의 저를 처음 무대에 세워 주신 대학로 소극장 선배님들. 선배님들이 어깨를 내어 주셔서, 제가 여기까지 올라올 수 있었습니다. 고맙습니다.

이 상을 주신 모든 분들께 감사드립니다. 오늘 우리가, 새로운 역사를 썼습니다. 감사합니다.',
   '[]'::jsonb, 90, 'acceptance',
   '{"ko": "마흔여섯에 처음 주인공을 맡은 배우가 여우주연상을 받는 장면이에요. 트로피를 손에 든 순간처럼, 첫 문장은 지켜보는 아이들에게, 엄마 이야기는 천천히, 마지막 한 줄은 크게 말해 보세요.", "en": "You’ve just won Best Actress, after getting your first lead role at forty-six. Picture the trophy in your hand: say the first lines to every kid watching, slow down when you get to your mom, and let the last line ring out.", "ja": "四十六歳で初めて主役をつかんだ俳優が、主演女優賞を受け取る場面です。トロフィーを手にしたつもりで、最初の言葉は見ている子どもたちに、お母さんの話はゆっくり、最後の一言は力強く話してみましょう。", "de": "Du hast gerade den Preis als beste Hauptdarstellerin gewonnen, nachdem du mit sechsundvierzig deine erste Hauptrolle bekommen hast. Stell dir die Trophäe in deiner Hand vor: Sag die ersten Sätze zu allen Kindern, die zuschauen, sprich langsamer, wenn es um deine Mutter geht, und lass den letzten Satz richtig klingen.", "es": "Acabas de ganar el premio a mejor actriz, después de conseguir tu primer papel protagonista a los cuarenta y seis. Imagina el trofeo en tu mano: dile las primeras frases a cada niño que te está viendo, habla más despacio cuando llegues a tu mamá y deja que la última frase resuene.", "fr": "Tu viens de recevoir le prix de la meilleure actrice, toi qui as eu ton premier grand rôle à quarante-six ans. Imagine le trophée dans ta main : adresse les premières phrases à tous les enfants qui regardent, ralentis quand tu parles de ta mère, et laisse la dernière phrase résonner.", "zh-Hant": "你是四十六歲才第一次當上主角的演員，剛拿下最佳女主角。想像獎座就在你手上：開頭說給正在看的孩子們聽，講到媽媽時放慢，最後一句大聲說出來。", "zh-Hans": "你是四十六岁才第一次当上主角的演员，刚拿下最佳女主角。想象奖杯就在你手上：开头说给正在看的孩子们听，讲到妈妈时放慢，最后一句大声说出来。"}'::jsonb,
   null, 'female')
on conflict (id) do nothing;

-- Podcast host (en 'Welcome back to the show', ...0025). The show is the English one's, 작은 승리. No factual claims.
insert into public.speech_challenges (id, language, title, genre, body, sources, target_seconds, category, intro, link, reference_voice)
values
  ('5beec000-0000-4000-8000-0000000c0025', 'ko', '작은 승리, 다시 돌아왔습니다', 'explainer',
   '안녕하세요, 여러분. 작은 습관이 인생을 조용히 바꾸는 이야기, 작은 승리입니다. 오늘도 와 주셔서 정말 반가워요.

커피 한 잔 들고 편하게 앉으세요. 오늘 이야기 진짜 좋거든요. 오늘의 주제는 오 분의 법칙이에요. 방법은 간단해요. 뭔가 하기 싫을 때, 나한테 이렇게 말하는 거예요. 딱 오 분만 하자. 그게 다예요. 오 분 하고, 그래도 싫으면 그만둬도 돼요.

그런데 재밌는 게요, 거의 안 그만둬요. 제일 어려운 건 일 자체가 아니라, 시작하는 거였거든요.

저도 지난달에 달리기로 해 봤어요. 저 달리기 진짜 싫어해요. 진짜로요. 그런데 매일 아침, 딱 오 분만, 동네 한 바퀴만, 이러면서 나갔어요. 어떻게 됐는지 아세요? 오늘 아침에는 삼십 분을 뛰었는데, 그런 줄도 몰랐어요.

오늘은 이 작은 방법으로 책 한 권을 다 쓴 분을 게스트로 모셨어요. 그 전에, 하나만 물어볼게요. 계속 미루고 있는 일, 뭐가 있으세요? 그 생각 잠깐 붙잡고 계세요. 이 에피소드 끝날 때쯤엔, 그 일 시작하고 계실 거예요.

그럼, 시작해 볼까요?',
   '[]'::jsonb, 60, 'podcast',
   '{"ko": "내 팟캐스트의 새 에피소드를 여는 장면이에요. 많은 사람이 아니라 이어폰을 낀 한 사람에게 말하듯, 편하고 다정하게, 목소리에 미소를 담아 말해 보세요.", "en": "You’re opening a new episode of your own Korean podcast. Talk to one listener with headphones on, not to a crowd: relaxed and warm, with a smile in your voice.", "ja": "自分の韓国語ポッドキャストの新しいエピソードを始める場面です。大勢ではなく、イヤホンで聴いているひとりに話しかけるように、リラックスして温かく、声に笑顔をのせてみましょう。", "de": "Du eröffnest eine neue Folge deines eigenen koreanischen Podcasts. Sprich nicht zu einem Publikum, sondern zu einer Person mit Kopfhörern: locker, herzlich und mit einem Lächeln in der Stimme.", "es": "Abres un nuevo episodio de tu propio pódcast en coreano. No le hables a una multitud, sino a una persona con los auriculares puestos: con calma, con calidez y con una sonrisa en la voz.", "fr": "Tu ouvres un nouvel épisode de ton propre podcast en coréen. Ne parle pas à une foule, mais à une seule personne qui t’écoute avec ses écouteurs : sur un ton détendu et chaleureux, avec le sourire dans la voix.", "zh-Hant": "你正在為自己的韓語 Podcast 開場新的一集。不是對一大群人，而是對戴著耳機的那一個人說話：輕鬆、溫暖，讓聲音帶著笑意。", "zh-Hans": "你正在为自己的韩语播客开场新的一集。不是对一大群人，而是对戴着耳机的那一个人说话：轻松、温暖，让声音带着笑意。"}'::jsonb,
   null, 'female')
on conflict (id) do nothing;

-- Docent at the Mona Lisa (en 'Come a little closer', ...002b). Checked 2026-11-15 (History.com, History Hit, Wikipedia): stolen Monday 21 August 1911 while the Louvre was closed, by Vincenzo Peruggia, who had worked there as a glazier, the panel hidden under his work smock; missed only the next day (Louis Béroud, Tuesday 22 August); Picasso questioned; crowds came to see the empty wall; found in Florence in December 1913 (more than two years), back in the Louvre January 1914. The painting is 77 x 53 cm ("생각보다 작아서").
insert into public.speech_challenges (id, language, title, genre, body, sources, target_seconds, category, intro, link, reference_voice)
values
  ('5beec000-0000-4000-8000-0000000c002b', 'ko', '조금만 더 가까이 오세요', 'explainer',
   '자, 여러분, 조금만 더 가까이 오세요. 앞쪽에 자리 있어요, 쑥스러워하지 마시고요.

실제로 보면 생각보다 작아서 다들 놀라세요. 그리고 아마 이런 생각도 드실 거예요. 왜 하필 이 그림일까? 바로 옆 전시실에 더 크고, 더 화려하고, 더 극적인 그림들이 있는데, 왜 전 세계 사람들이 이 그림 하나를 보러 올까?

비밀을 하나 알려 드릴게요. 이 그림은 사백 년 동안 미술계에서만 유명했어요. 미술관 밖에서는 아는 사람이 별로 없었죠. 그러다 천구백십일 년 팔월, 미술관이 문을 닫는 조용한 월요일 아침이었어요. 예전에 이곳에서 일했던 한 남자가 이 그림을 벽에서 떼어 내서, 작업복 속에 숨기고 그냥 걸어 나갔어요.

그림이 없어진 걸 누가 알아차리기까지 얼마나 걸렸을까요? 꼬박 하루가 걸렸어요.

그리고 바로 그때부터 모든 게 달라졌어요. 전 세계 신문이 첫 면에 이 얼굴을 실었고, 미술관에 한 번도 와 본 적 없는 사람들까지 이 얼굴을 알게 됐죠. 경찰은 젊은 파블로 피카소까지 불러서 조사했어요. 그리고 여기, 바로 이 미술관에는 그림이 걸려 있던 빈 벽을 보려고 사람들이 줄을 섰답니다.

이 년 넘게 전 세계가 이 그림의 행방을 궁금해했어요. 그러다 마침내 피렌체에서 발견되어 파리로 돌아왔을 때, 이 그림은 더 이상 그냥 그림이 아니었어요. 지구에서 가장 유명한 얼굴이 되어 있었죠.

자, 이 미소를 한 번만 더 보시고 말씀해 주세요. 만약 아무도 이 그림을 훔쳐 가지 않았다면, 여러분은 오늘 여기 서 계셨을까요?',
   '["https://www.history.com/articles/the-heist-that-made-the-mona-lisa-famous", "https://www.historyhit.com/theft-mona-lisa/", "https://en.wikipedia.org/wiki/Vincenzo_Peruggia"]'::jsonb, 90, 'docent',
   '{"ko": "미술관 도슨트가 되어 모나리자 앞에 관람객들을 모았어요. 눈앞의 사람들에게 말을 걸듯, 꼭 들려주고 싶던 비밀을 털어놓는 기분으로 읽어 보세요. 마지막 질문은 정말 대답을 기다리듯이요.", "en": "You’re a museum docent, and you’ve just gathered a Korean tour group in front of the Mona Lisa. Tell it like a secret you can’t wait to share, talk to the faces in front of you, and ask the last question as if you really want an answer.", "ja": "美術館のドーセントになって、モナ・リザの前に韓国からのお客さんを集めたところです。目の前の人たちに話しかけるように、とっておきの秘密を打ち明ける気分で読んでみましょう。最後の質問は、本当に答えを待っているつもりで。", "de": "Du führst durchs Museum und hast gerade eine koreanische Gruppe vor der Mona Lisa versammelt. Sprich die Leute direkt an, als würdest du ein Geheimnis verraten, und stell die letzte Frage so, als wolltest du wirklich eine Antwort.", "es": "Eres guía de museo y acabas de reunir a un grupo coreano frente a la Mona Lisa. Háblales directamente, como quien cuenta un secreto que llevaba tiempo guardando, y haz la última pregunta como si de verdad esperaras una respuesta.", "fr": "Tu es guide de musée et tu viens de rassembler un groupe coréen devant la Joconde. Parle aux gens en face de toi, comme si tu leur confiais un secret, et pose la dernière question comme si tu attendais vraiment une réponse.", "zh-Hant": "你是美術館的導覽員，剛把一群韓國觀眾帶到蒙娜麗莎前面。對著眼前的人說話，像在分享一個忍不住想說的祕密；最後的問題，要像真的在等大家回答。", "zh-Hans": "你是美术馆的讲解员，刚把一群韩国观众带到蒙娜丽莎面前。对着眼前的人说话，像在分享一个忍不住想说的秘密；最后的问题，要像真的在等大家回答。"}'::jsonb,
   null, 'female')
on conflict (id) do nothing;

-- Morning weather (en 'Don''t put that umbrella away yet', ...002c). A made-up forecast in a Korean presenter's register (합니다 for the forecast, 해요 for the asides), with Korean regions (중부지방, 서해안, 서울) and units: wind as 순간풍속 초속 N 미터, the way KMA and Korean forecasts give it (checked against KMA's forecast guide; fifteen m/s is strong wind, under the 20 m/s 강풍주의보 gust line, so no warning is implied). Weather moves west to east over Korea, so the high comes from the west and pushes the rain to the East Sea.
insert into public.speech_challenges (id, language, title, genre, body, sources, target_seconds, category, intro, link, reference_voice)
values
  ('5beec000-0000-4000-8000-0000000c002c', 'ko', '아직 우산 넣지 마세요', 'explainer',
   '안녕하십니까, 기다리던 금요일 아침입니다. 오늘은 주말 날씨부터 짚어 보겠는데요, 좋은 소식이 하나 있습니다. 그런데 그건, 조금 이따가 말씀드릴게요.

먼저 아쉬운 소식부터 전해 드리겠습니다. 이번 주 내내 머물던 비구름이 아직 물러나지 않았습니다. 오전까지 중부지방과 서해안을 중심으로 강한 소나기가 쏟아지겠고, 점심 무렵에는 순간풍속 초속 십오 미터 안팎의 강한 바람도 불겠습니다. 차 가지고 출근하시는 분들은 평소보다 조금 일찍 나서시고요, 우산은 예쁜 거 말고, 꼭 큰 걸로 챙기세요.

오늘 낮 기온은 서울이 구 도에 머물겠고, 밤사이에는 이 도 안팎까지 뚝 떨어지겠습니다. 베란다에 화분 두신 분들은, 오늘 밤엔 안으로 들여놓으세요.

자, 이제 기다리시던 소식입니다. 내일 늦은 오전부터 서쪽에서 고기압이 다가오면서, 이 비구름을 동쪽 바다로 밀어내겠습니다. 토요일 오후에는 하늘이 파랗게 개겠고, 바람도 잦아들면서 낮 기온은 십오 도까지 오르겠습니다. 일요일은 더 좋겠습니다.

네, 맞습니다. 삼 주 동안 이어진 흐린 날씨 끝에, 드디어 해가 돌아옵니다.

그럼 하나 여쭤볼게요. 거의 한 달 만에 찾아온 맑은 주말, 여러분은 뭐 하실 건가요?',
   '["https://www.weather.go.kr/w/forecast/guide/standard.do"]'::jsonb, 75, 'weather',
   '{"ko": "아침 방송 기상캐스터가 되어 주말 날씨를 전해요. 출근 준비하는 사람들에게 말하듯 밝고 또렷하게, 좋은 소식은 아껴 뒀다가 마지막에 풀어 주세요.", "en": "You’re the weather presenter on a Korean morning show, telling everyone getting ready for work what the weekend holds. Keep it bright and clear, and save the good news for the end.", "ja": "韓国の朝の番組のお天気キャスターになって、週末の天気を伝えます。出かける準備をしている人に話しかけるように、明るくはっきりと。いい知らせは最後までとっておいてください。", "de": "Du moderierst das Wetter im koreanischen Frühstücksfernsehen und sagst allen, die sich gerade für die Arbeit fertig machen, wie das Wochenende wird. Hell und klar, und die gute Nachricht hebst du dir bis zum Schluss auf.", "es": "Eres quien presenta el tiempo en un programa matutino de Corea y cuentas qué trae el fin de semana a quienes se preparan para salir. Con energía y claridad, y guarda la buena noticia para el final.", "fr": "Tu présentes la météo d’une matinale coréenne et tu annonces le week-end à ceux qui se préparent à partir travailler. Avec entrain et clarté, et garde la bonne nouvelle pour la fin.", "zh-Hant": "你是韓國晨間節目的氣象主播，要告訴正在準備出門的大家週末天氣如何。語氣明亮清楚，好消息留到最後再說。", "zh-Hans": "你是韩国早间节目的天气预报员，要告诉正准备出门的大家周末天气怎么样。语气明快清楚，好消息留到最后再说。"}'::jsonb,
   null, 'male')
on conflict (id) do nothing;

-- Film reviewer on Interstellar (en 'I rewatched Interstellar', ...002d, category film_review per 20261115100000). Checked 2026-11-15: Kip Thorne's equations behind the black hole and the 2015 Classical and Quantum Gravity paper (James, von Tunzelmann, Franklin, Thorne); the organ is Temple Church, London (Roger Sayer); one hour on Miller's planet is seven years on Earth; twenty-three years of messages; 169 minutes ("거의 세 시간"); over ten million admissions in Korea (10,000,046 on 25 Dec 2014, KOBIS via TenAsia; about 10.38M with re-releases). No ending spoilers.
insert into public.speech_challenges (id, language, title, genre, body, sources, target_seconds, category, intro, link, reference_voice)
values
  ('5beec000-0000-4000-8000-0000000c002d', 'ko', '인터스텔라를 다시 봤어요', 'explainer',
   '여러분 안녕하세요, 다시 오셨네요. 저 어젯밤에 인터스텔라를 또 봤어요. 한 열 번째쯤 되는 것 같은데, 이번에 유독 세게 와서 이야기를 안 할 수가 없어요. 결말 스포는 없어요, 약속할게요.

줄거리부터 짧게 갈게요. 지구가 죽어 가고 있어요. 어딜 가나 모래 폭풍이고, 농작물은 말라 가요. 그래서 전직 조종사 쿠퍼가 아이들을 두고, 웜홀을 지나 인류가 살 새 터전을 찾으러 떠나요.

자, 이 영화가 왜 특별하냐. 첫째, 과학이 진짜예요. 크리스토퍼 놀란 감독이 물리학자 킵 손이랑 같이 작업했는데, 화면에 나오는 블랙홀이 이분 방정식으로 만든 거예요. 얼마나 진짜 같았으면, 과학 논문에까지 실렸어요.

둘째, 음악이요. 한스 짐머가 런던의 오래된 교회에 있는 커다란 파이프 오르간으로 녹음했는데요, 도킹 장면에서 그 오르간이 터지는 순간, 저 진짜 숨 쉬는 걸 잊었어요.

그런데 저를 매번 무너뜨리는 장면은 따로 있어요. 한 시간이 지구의 칠 년인 행성에 내리거든요. 쿠퍼가 우주선으로 돌아오니까, 아이들이 보낸 이십삼 년 치 영상 메시지가 기다리고 있어요. 몇 분 만에 아이들이 자라는 걸 지켜보는데, 한마디도 대답을 못 해요.

완벽하냐고요? 아니요. 대사가 좀 무거운 데도 있고, 거의 세 시간짜리예요. 그래도 물리학을 이렇게 내 이야기처럼 느끼게 해 준 영화는 처음이었어요. 우리나라에서 천만 명 넘게 본 데는 다 이유가 있더라고요.

그럼 여러분한테 물어볼게요. 시간을 건너서 딱 한 사람한테 메시지를 보낼 수 있다면, 누구한테, 뭐라고 하실 거예요?',
   '["https://doi.org/10.1088/0264-9381/32/6/065001", "https://en.wikipedia.org/wiki/Interstellar_(soundtrack)", "https://www.tenasia.co.kr/article/2014122698804"]'::jsonb, 95, 'film_review',
   '{"ko": "영화 리뷰어가 되어 인터스텔라를 다시 보고 리뷰해요. 좋아하는 영화를 친구에게 권하듯 신나게, 그 장면에서는 진심을 담아서, 마지막 질문은 댓글을 기다리듯이요.", "en": "You’re a film reviewer, and you’ve just rewatched Interstellar, one of the most loved films in Korea. Talk the way you would to a friend you want to see it, mean it when you get to that scene, and ask the last question like you’re waiting for the comments.", "ja": "映画レビュアーになって、韓国でも大人気のインターステラーを見返したレビューをします。好きな映画を友だちにすすめるように楽しく、あのシーンでは気持ちを込めて。最後の質問は、コメントを待っているつもりで。", "de": "Du bist Filmkritikerin und hast gerade Interstellar noch einmal gesehen, einen der beliebtesten Filme in Korea. Erzähl es wie einer Freundin, die den Film unbedingt sehen soll, sprich die eine Szene mit Gefühl, und stell die letzte Frage so, als würdest du auf die Kommentare warten.", "es": "Eres crítica de cine y acabas de volver a ver Interstellar, una de las películas más queridas en Corea. Cuéntalo como se lo contarías a una amiga a la que quieres convencer, pon el corazón en esa escena y haz la última pregunta como si esperaras los comentarios.", "fr": "Tu es critique de cinéma et tu viens de revoir Interstellar, l’un des films les plus aimés en Corée. Raconte-le comme à une amie que tu veux convaincre, mets-y du cœur sur cette scène, et pose la dernière question comme si tu attendais les commentaires.", "zh-Hant": "你是電影評論人，剛重看了在韓國超受歡迎的《星際效應》。像跟朋友推薦愛看的電影一樣興奮地說，講到那一幕時要真心，最後的問題就像在等大家留言。", "zh-Hans": "你是影评人，刚重看了在韩国超受欢迎的《星际穿越》。像跟朋友安利喜欢的电影一样兴奋地说，讲到那一幕时要真心，最后的问题就像在等大家留言。"}'::jsonb,
   null, 'female')
on conflict (id) do nothing;
