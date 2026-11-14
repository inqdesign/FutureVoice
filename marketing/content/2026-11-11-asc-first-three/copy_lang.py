# Store screenshot headlines, written in each language (not translated from the Korean).
# Each headline is (black line, grey line). s02sub / s03sub are the one-line explanations.
NB = " "
SCR = "/private/tmp/claude-502/-Users-eunggyuelee-FutureVoice/28555fe9-7198-4899-99bf-1aa90e91e314/scratchpad/asc"

# The language row on the opener: the learner picks ONE.
LANGS_ROW = [("English ✓", True), ("日本語", False), ("Español", False),
             ("Deutsch", False), ("Français", False), ("中文", False)]

COPY = {
    "ko": dict(
        hand=f"{SCR}/dev/hand_1320.png",
        s01=("유창해진 미래의 나와", "통화해요"),
        s02=("원어민 흉내 말고", "유창한 나를 따라 해요"), s02sub="내 목소리 그대로, 유창해진 내가 말해요.",
        s03=("시험도 면접도", "튜터가 챙겨요"), s03sub="날짜에 맞춰 오늘 할 일을 골라 줘요.",
        s04=("매일 새 원고로", "소리 내어 연습해요"),
        s05=("틀린 문법은", "통화 중에 잡아줘요"),
        s06=("말이 막히면", "답할 문장이 떠요"),
        s07=("입에 붙을 때까지", "따라 말해요"),
        s08=("어떤 상황이든", "직접 만들어 연습해요"),
        s09=("통화 한 번이", "복습 교재 한 권"),
        s10=("내가 정한 루틴대로", "매일 이어가요"),
    ),
    "en": dict(
        hand=f"{SCR}/dev/hand_en_1320.png",
        s01=("Call the fluent", "future you"),
        s02=("Don't copy natives.", "Copy the fluent you."), s02sub="Your own voice, already fluent.",
        s03=("Exams, interviews:", "your tutor's on it."), s03sub="It picks today's practice by the date.",
        s04=("A new script every day,", "read out loud."),
        s05=("Grammar slips,", "caught mid-call."),
        s06=("Stuck for words?", "Your answer appears."),
        s07=("Shadow every line", "until it sticks."),
        s08=("Any situation,", "built by you."),
        s09=("One call,", "one review book."),
        s10=("Your own routine,", "every day."),
    ),
    "ja": dict(
        s01=("ペラペラになった未来の自分と", "電話で話そう"),
        s02=("ネイティブのまねより", "流暢な自分をまねしよう"), s02sub="自分の声のまま、流暢になった自分が話します。",
        s03=("試験も面接も", "チューターにおまかせ"), s03sub="日付に合わせて、今日やることを選んでくれます。",
        s04=("毎日あたらしい原稿を", "声に出して練習"),
        s05=("文法のミスは", "通話中にその場で直る"),
        s06=("言葉につまったら", "答える一文が出てくる"),
        s07=("口になじむまで", "シャドーイング"),
        s08=("どんな場面も", "自分でつくって練習"),
        s09=("一回の通話が", "一冊の復習ノートに"),
        s10=("自分で決めたルーティンで", "毎日つづける"),
    ),
    "zh-Hans": dict(
        s01=("和说得流利的", "未来的自己通话"),
        s02=("别模仿母语者", "模仿流利的自己"), s02sub="还是你的声音，只是说得更流利。",
        s03=("考试、面试", "导师帮你安排"), s03sub="按日期挑好今天要练的内容。",
        s04=("每天一篇新稿子", "大声读出来"),
        s05=("语法错误", "通话中当场纠正"),
        s06=("卡壳的时候", "回答的句子就在眼前"),
        s07=("一句句跟读", "直到脱口而出"),
        s08=("任何场景", "自己设定来练"),
        s09=("一次通话", "就是一本复习书"),
        s10=("按自己的节奏", "每天坚持"),
    ),
    "zh-Hant": dict(
        s01=("和說得流利的", "未來的自己通話"),
        s02=("別模仿母語人士", "模仿流利的自己"), s02sub="還是你的聲音，只是說得更流利。",
        s03=("考試、面試", "家教幫你安排"), s03sub="依照日期挑好今天要練的內容。",
        s04=("每天一篇新講稿", "大聲唸出來"),
        s05=("文法錯誤", "通話中當場糾正"),
        s06=("卡住的時候", "回答的句子就在眼前"),
        s07=("一句句跟讀", "直到脫口而出"),
        s08=("任何情境", "自己設定來練"),
        s09=("一通電話", "就是一本複習書"),
        s10=("照自己的節奏", "每天持續"),
    ),
    "es": dict(
        s01=("Habla con tu yo", "del futuro, ya fluido"),
        s02=("No imites a nativos.", "Imita a tu yo fluido."), s02sub="Tu propia voz, hablando con fluidez.",
        s03=("Exámenes, entrevistas:", "tu tutor se encarga."), s03sub="Elige qué practicar hoy según la fecha.",
        s04=("Un guion nuevo cada día,", "en voz alta."),
        s05=("Errores de gramática,", "corregidos en la llamada."),
        s06=("¿Te quedas en blanco?", "Ahí tienes tu respuesta."),
        s07=("Repite cada frase", "hasta que salga sola."),
        s08=("Cualquier situación,", "creada por ti."),
        s09=("Una llamada,", "un cuaderno de repaso."),
        s10=("Tu propia rutina,", "cada día."),
    ),
    "fr": dict(
        s01=("Appelle ton futur toi,", "déjà fluide"),
        s02=("N’imite pas les natifs.", "Imite ton toi fluide."), s02sub="Ta propre voix, qui parle couramment.",
        s03=(f"Examens, entretiens{NB}:", "ton tuteur s’en charge."), s03sub="Il choisit quoi travailler aujourd’hui selon la date.",
        s04=("Un nouveau texte par jour,", "à voix haute."),
        s05=("Tes fautes de grammaire,", "corrigées en plein appel."),
        s06=(f"Tu bloques{NB}?", "Ta réponse s’affiche."),
        s07=("Répète chaque phrase", "jusqu’à ce qu’elle sorte seule."),
        s08=("N’importe quelle situation,", "créée par toi."),
        s09=("Un appel,", "un carnet de révision."),
        s10=("Ta routine à toi,", "chaque jour."),
    ),
    "de": dict(
        s01=("Ruf dein fließendes", "Zukunfts-Ich an"),
        s02=("Ahm nicht Muttersprachler nach,", "sondern dein fließendes Ich."), s02sub="Deine eigene Stimme, nur fließend.",
        s03=("Prüfung, Bewerbungsgespräch:", "dein Tutor plant mit."), s03sub="Er wählt nach dem Datum, was heute dran ist.",
        s04=("Jeden Tag ein neuer Text,", "laut gelesen."),
        s05=("Grammatikfehler,", "mitten im Gespräch korrigiert."),
        s06=("Fehlen dir die Worte?", "Deine Antwort steht schon da."),
        s07=("Sprich jeden Satz nach,", "bis er sitzt."),
        s08=("Jede Situation,", "von dir gebaut."),
        s09=("Ein Anruf,", "ein Lernheft."),
        s10=("Deine eigene Routine,", "jeden Tag."),
    ),
}
MEET = {
    "ko": (("유창해진 나를", "만나요"), [('쉐도잉', '내 목소리라<br>그대로 따라 해요'), ('교정', '틀린 말은<br>바로 고쳐 줘요'), ('안정감', '상대가 나라서<br>창피하지 않아요'), ('목표', '되고 싶은 내가<br>눈앞에 있어요')]),
    "en": (("Meet the fluent", "you"), [('Shadowing', "It's your voice,<br>so just copy it"), ('Correction', 'Slips get fixed<br>right away'), ('Comfort', "It's you, so<br>nothing to fear"), ('Goal', 'Who you want to be,<br>right there')]),
    "ja": (("流暢になった自分に", "会おう"), [('シャドーイング', '自分の声だから<br>そのまままねできる'), ('添削', 'まちがいは<br>その場で直る'), ('安心', '相手は自分だから<br>恥ずかしくない'), ('目標', 'なりたい自分が<br>目の前にいる')]),
    "zh-Hans": (("和流利的自己", "见面"), [('跟读', '是你的声音<br>直接跟着说'), ('纠错', '说错了<br>马上帮你改'), ('安心', '对面是自己<br>不用难为情'), ('目标', '想成为的自己<br>就在眼前')]),
    "zh-Hant": (("和流利的自己", "見面"), [('跟讀', '是你的聲音<br>直接跟著說'), ('糾錯', '說錯了<br>馬上幫你改'), ('安心', '對面是自己<br>不用不好意思'), ('目標', '想成為的自己<br>就在眼前')]),
    "es": (("Conoce a tu yo", "fluido"), [('Repetir', 'Es tu voz:<br>solo imítala'), ('Corrección', 'Tus errores,<br>corregidos al momento'), ('Confianza', 'Eres tú:<br>sin vergüenza'), ('Meta', 'Quien quieres ser,<br>frente a ti')]),
    "fr": (("Rencontre ton moi", "fluide"), [('Répéter', 'C’est ta voix :<br>imite-la'), ('Correction', 'Tes fautes,<br>corrigées aussitôt'), ('Confiance', 'C’est toi :<br>aucune gêne'), ('Objectif', 'Qui tu veux être,<br>juste là')]),
    "de": (("Triff dein", "fließendes Ich"), [('Nachsprechen', 'Deine Stimme:<br>einfach nachsprechen'), ('Korrektur', 'Fehler werden<br>sofort korrigiert'), ('Sicherheit', 'Du bist es selbst:<br>nichts ist peinlich'), ('Ziel', 'Wer du sein willst,<br>direkt vor dir')]),
}

# Play's folder names for the same languages.
COPY["zh-CN"] = COPY["zh-Hans"]
COPY["zh-TW"] = COPY["zh-Hant"]
MEET["zh-CN"] = MEET["zh-Hans"]
MEET["zh-TW"] = MEET["zh-Hant"]
