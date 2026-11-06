-- Speech challenge, ja (2026-11-06): written for that language's board,
-- not translated from another. Japanese board: the friend's speech at a wedding (友人代表スピーチ), in its set
-- order and without 忌み言葉 (別れる・切れる・重ね重ね…). Original script.
insert into public.speech_challenges (id, language, title, genre, body, sources, target_seconds, category, intro, link)
values
  ('5beec000-0000-4000-8000-000000000028', 'ja', 'ご結婚おめでとうございます', 'person',
   '健太さん、美咲さん、ご結婚おめでとうございます。ご両家の皆さまにも、心よりお祝い申し上げます。

ただいまご紹介にあずかりました、新婦の大学時代の友人、山下と申します。僭越ではございますが、ひと言ご挨拶させていただきます。

美咲さんとは、入学式の日に隣の席になったのが始まりでした。緊張していた私に、そのペン、かわいいねと声をかけてくれたのを、今でもよく覚えています。美咲さんは、そうやって誰にでも自然に優しくできる人です。

先日、健太さんの話を聞いたとき、美咲さんはずっと笑っていました。こんなに楽しそうな顔を見たのは初めてで、ああ、この人なら大丈夫だと思いました。

お二人とも、これからは楽しいことも大変なことも一緒に乗り越えて、笑顔のあふれる家庭を築いてください。

簡単ではございますが、お祝いの言葉とさせていただきます。本日は本当におめでとうございます。',
   '[]'::jsonb, 60, 'short_talk',
   '{"en": "You’re giving the friend’s speech at a Japanese wedding. It has a set order: congratulations, who you are, one short story about the bride, your wishes, a polite close. Speak calmly and warmly, in polite Japanese.", "ko": "일본 결혼식에서 신부 친구 대표로 축사를 하는 장면이에요. 축하 인사, 자기소개, 신부와의 짧은 이야기, 앞으로의 덕담, 정중한 마무리라는 정해진 순서가 있어요. 차분하고 따뜻하게 말해 보세요.", "ja": "結婚式で、新婦の友人代表としてスピーチをする場面です。お祝い、自己紹介、新婦とのエピソード、これからへの言葉、結びという流れがあります。落ち着いて、温かく、丁寧に話しましょう。", "de": "Du hältst auf einer japanischen Hochzeit die Rede als Freundin oder Freund der Braut. Sie folgt einer festen Reihenfolge: Glückwunsch, wer du bist, eine kurze Geschichte über die Braut, gute Wünsche und ein höflicher Schluss. Sprich ruhig, herzlich und höflich.", "es": "Das el discurso en nombre de los amigos de la novia en una boda japonesa. Tiene un orden fijo: felicitar, presentarte, contar una anécdota breve de la novia, desearles lo mejor y cerrar con cortesía. Habla con calma, con calidez y de forma educada.", "fr": "Tu prononces le discours au nom des amis de la mariée, à un mariage japonais. Il suit un ordre précis : félicitations, présentation, une courte anecdote sur la mariée, des vœux, puis une conclusion polie. Parle calmement, avec chaleur et politesse.", "zh-Hant": "你在日本婚禮上代表新娘的朋友致詞。致詞有固定的順序：道賀、自我介紹、一段和新娘的小故事、祝福，再禮貌地收尾。說得沉穩、溫暖又有禮貌。", "zh-Hans": "你在日本婚礼上代表新娘的朋友致辞。致辞有固定的顺序：道贺、自我介绍、一段和新娘的小故事、祝福，再礼貌地收尾。说得沉稳、温暖又有礼貌。"}'::jsonb,
   null)
on conflict (id) do nothing;
