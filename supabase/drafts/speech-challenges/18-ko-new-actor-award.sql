-- Speech challenge, ko (2026-11-06): written for that language's board,
-- not translated from another. Korean board: a Best New Actor acceptance speech at a film awards, in the
-- shape Korean ones take (director, crew, seniors, family, then a promise).
-- Original script, no real names.
insert into public.speech_challenges (id, language, title, genre, body, sources, target_seconds, category, intro, link)
values
  ('5beec000-0000-4000-8000-000000000027', 'ko', '정말 받을 줄 몰랐어요', 'person',
   '어… 정말 받을 줄 몰랐어요. 무대에 올라오는데 다리가 너무 떨려서, 넘어질까 봐 걱정했어요.

먼저 부족한 저를 믿고 이 역할을 맡겨 주신 감독님, 정말 감사합니다. 첫 촬영 날 대사를 다 잊어버렸을 때, 괜찮다고, 천천히 하자고 해 주셨던 그 한마디 덕분에 여기까지 왔습니다.

추운 겨울 새벽마다 같이 고생해 주신 스태프 여러분, 그리고 늘 먼저 손 내밀어 주신 선배님들께도 감사드립니다.

사실 저는 오디션에서 정말 많이 떨어졌어요. 그만둘까 고민한 날도 많았고요. 그때마다 넌 잘될 거라고 말해 준 우리 엄마, 아빠. 저 오늘 상 받았어요. 사랑합니다.

이 상은 잘했다고 주시는 상이 아니라, 앞으로 더 잘하라고 주시는 상이라고 생각하겠습니다. 부끄럽지 않은 배우가 되겠습니다. 감사합니다!',
   '[]'::jsonb, 60, 'acceptance',
   '{"en": "You’ve just won Best New Actor at a film awards, and you never saw it coming. A Korean acceptance speech thanks people in turn: the director, the crew, the seniors, then family. A little emotion in your voice is fine; say the promise at the end clearly.", "ko": "영화제에서 신인상을 받은 순간이에요. 전혀 예상하지 못했어요. 감독님, 스태프, 선배님, 가족에게 차례로 고마움을 전하고, 살짝 울컥해도 괜찮아요. 마지막 다짐만은 또박또박 말해 보세요.", "ja": "映画祭で新人賞を受け取った瞬間です。まさか自分が、という気持ちで。監督、スタッフ、先輩、家族へと順番に感謝を伝えるのが韓国の受賞スピーチの形です。少し声が震えてもかまいません。最後の決意は、はっきりと。", "de": "Du hast gerade einen Nachwuchspreis bei einem Filmfestival gewonnen und überhaupt nicht damit gerechnet. In Korea dankt man der Reihe nach: der Regie, dem Team, den älteren Kollegen und dann der Familie. Ein bisschen Rührung in der Stimme ist erlaubt, das Versprechen am Ende sagst du klar.", "es": "Acabas de ganar el premio a la mejor revelación en un festival de cine y no te lo esperabas. En Corea se agradece por orden: al director, al equipo, a los compañeros con más trayectoria y a la familia. Está bien que se te quiebre un poco la voz; la promesa del final, dila con claridad.", "fr": "Tu viens de recevoir le prix de la révélation dans un festival de cinéma, et tu ne t’y attendais pas du tout. En Corée, on remercie dans l’ordre : le réalisateur, l’équipe, les aînés, puis la famille. Un peu d’émotion dans la voix, c’est permis ; la promesse de la fin, dis-la clairement.", "zh-Hant": "你剛在影展上拿下新人獎，完全沒想到會是自己。韓國的得獎感言會依序道謝：導演、工作人員、前輩，最後是家人。聲音有點哽咽也沒關係，最後的承諾要說得清清楚楚。", "zh-Hans": "你刚在电影节上拿下新人奖，完全没想到会是自己。韩国的获奖感言会依次道谢：导演、工作人员、前辈，最后是家人。声音有点哽咽也没关系，最后的承诺要说得清清楚楚。"}'::jsonb,
   null)
on conflict (id) do nothing;
