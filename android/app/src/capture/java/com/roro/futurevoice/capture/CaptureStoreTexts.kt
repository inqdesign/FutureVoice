package com.roro.futurevoice.capture

/**
 * The app-language half of the staged screens the store screenshots are
 * taken from (`call-seed-fix`, `call-seed-coach`, `shadow-store`,
 * `store-tutor`) — iOS `CaptureCallSeed`, line for line. The practiced lines
 * are English; what explains them follows the app language, so each
 * language's screenshot reads like that learner's own screen.
 */
object CaptureStoreTexts {
    class Texts(
        val lesson: String,
        val goals: List<String>,
        val reason: String,
        val why: String,
        val coachMeaning: String,
        val shadowPronunciation: String,
        val shadowPacing: String,
        val shadowFix: String,
        /** The two goals on the tutor's first line: an exam, an interview. */
        val examTitle: String,
        val interviewTitle: String,
    )

    /**
     * The sample talk book's coaching (`talkdetail-store`): the scorecard's
     * top line and five axis notes, then the two correction reasons. Coaching
     * is in the app language; the sample seed writes it in English.
     */
    class Book(val top: String, val vocabulary: String, val grammar: String, val expressiveness: String,
               val fluency: String, val pronunciation: String, val pastTense: String, val articlePlural: String)

    fun book(language: String): Book = when {
        language.startsWith("ko") -> Book(
            "자신 있고 자연스러운 대화예요. 관사만 조금 다듬어요.",
            "구체적이고 정확한 단어를 골라 썼어요.", "관사와 시제 실수가 조금 있어요.",
            "점점 더 자연스럽고 관용적인 표현이 늘고 있어요.", "속도가 고르고 긴 멈춤이 줄었어요.",
            "또렷하고 연결이 매끄러워요.", "과거 시제", "관사 + 복수형")
        language.startsWith("ja") -> Book(
            "自信のある自然な会話です。冠詞だけ少し整えましょう。",
            "具体的で的確な単語を選べています。", "冠詞と時制のミスが少しあります。",
            "自然でこなれた言い回しが増えています。", "ペースが安定し、長い間が減りました。",
            "はっきりしていて、音のつながりもきれいです。", "過去形", "冠詞 + 複数形")
        language == "zh-Hans" -> Book(
            "说得自信又自然，冠词再注意一下就好。",
            "选词具体又准确。", "冠词和时态还有几处小错。",
            "表达越来越自然地道。", "语速平稳，长停顿变少了。",
            "发音清楚，连读顺畅。", "过去时", "冠词 + 复数")
        language.startsWith("zh") -> Book(
            "說得有自信又自然，冠詞再注意一下就好。",
            "選字具體又準確。", "冠詞和時態還有幾處小錯。",
            "表達越來越自然道地。", "語速平穩，長停頓變少了。",
            "發音清楚，連音順暢。", "過去式", "冠詞 + 複數")
        language.startsWith("es") -> Book(
            "Hablas con seguridad y naturalidad. Solo pule algunos artículos.",
            "Elegiste palabras precisas y concretas.", "Quedan algunos fallos de artículos y tiempos.",
            "Cada vez suenas más natural e idiomático.", "Ritmo estable, menos pausas largas.",
            "Clara, y enlazas bien las palabras.", "pasado", "artículo + plural")
        language.startsWith("fr") -> Book(
            "Tu parles avec aisance et naturel. Il reste quelques articles à soigner.",
            "Tu as choisi des mots précis et concrets.", "Quelques fautes d’articles et de temps à corriger.",
            "Tes tournures sont de plus en plus naturelles.", "Rythme régulier, moins de longues pauses.",
            "Clair, avec de belles liaisons.", "passé", "article + pluriel")
        else -> Book(
            "Confident, natural talk — tighten a few articles.",
            "Reached for precise, specific words.", "A few article and tense slips to tidy.",
            "Getting more natural and idiomatic.", "Steady pace, fewer long pauses.",
            "Clear, with good linking.", "past tense", "article + plural")
    }

    fun texts(language: String): Texts {
        val nb = " "
        return when {
            language.startsWith("ko") -> Texts(
                lesson = "면접 자기소개",
                goals = listOf("지금 하는 일 소개하기", "지원한 이유 말하기", "내 강점이 일에 도움 되는 이유 말하기"),
                reason = "'stay calm when … come up'이 더 자연스러워요. situation은 복수형으로 써요.",
                why = "situation은 셀 수 있는 명사라 복수형이어야 해요",
                coachMeaning = "요즘 [AI 프로젝트]를 하고 있는데, 아주 잘 되고 있어.",
                shadowPronunciation = "'taking the time'에서 the가 빠졌어요. 세 단어를 한 덩어리로 이어 말해 보세요.",
                shadowPacing = "속도는 원본과 거의 같아요. appreciate에 힘을 조금 더 주면 더 자연스러워요.",
                shadowFix = "'taking the time'만 한 번 더 따라 해 보세요.",
                examTitle = "오픽 IH", interviewTitle = "외국계 회사 면접")
            language.startsWith("ja") -> Texts(
                lesson = "面接の自己紹介",
                goals = listOf("今の仕事を紹介する", "応募した理由を話す", "自分の強みが仕事に活きる理由を話す"),
                reason = "「stay calm when … come up」のほうが自然です。situation は複数形にします。",
                why = "situation は数えられる名詞なので複数形にします",
                coachMeaning = "今[AIのプロジェクト]をやってて、すごく順調なんだ。",
                shadowPronunciation = "「taking the time」の the が抜けました。3語をひとかたまりで言ってみましょう。",
                shadowPacing = "スピードはお手本とほぼ同じです。appreciate をもう少し強く言うと自然です。",
                shadowFix = "「taking the time」だけもう一度まねしてみましょう。",
                examTitle = "TOEIC S&W", interviewTitle = "外資系企業の面接")
            language == "zh-Hans" -> Texts(
                lesson = "面试自我介绍",
                goals = listOf("介绍现在的工作", "说说为什么申请", "说说你的优势怎么帮到这份工作"),
                reason = "用“stay calm when … come up”更自然，situation 要用复数。",
                why = "situation 是可数名词，要用复数",
                coachMeaning = "我现在在做[一个AI项目]，进展很顺利。",
                shadowPronunciation = "“taking the time”里漏了 the。把这三个词连成一组说。",
                shadowPacing = "语速和原音差不多。appreciate 再重一点会更自然。",
                shadowFix = "再跟读一遍“taking the time”。",
                examTitle = "雅思口语 7分", interviewTitle = "外企面试")
            language.startsWith("zh") -> Texts(
                lesson = "面試自我介紹",
                goals = listOf("介紹現在的工作", "說說為什麼應徵", "說說你的優勢怎麼幫上這份工作"),
                reason = "用「stay calm when … come up」更自然，situation 要用複數。",
                why = "situation 是可數名詞，要用複數",
                coachMeaning = "我現在在做[一個AI專案]，進展很順利。",
                shadowPronunciation = "「taking the time」裡漏了 the。把這三個字連成一組說。",
                shadowPacing = "語速和原音差不多。appreciate 再重一點會更自然。",
                shadowFix = "再跟讀一次「taking the time」。",
                examTitle = "雅思口說 7分", interviewTitle = "外商面試")
            language.startsWith("es") -> Texts(
                lesson = "Entrevista",
                goals = listOf("Di a qué te dedicas", "Di por qué te postulaste", "Di cómo tus fortalezas encajan en el puesto"),
                reason = "«Stay calm when… come up» suena más natural, y situation va en plural.",
                why = "Situation es contable: va en plural.",
                coachMeaning = "Ahora estoy con [un proyecto de IA] y va muy bien.",
                shadowPronunciation = "Se te fue el «the» de «taking the time». Di las tres palabras de un tirón.",
                shadowPacing = "Vas al mismo ritmo que el original. Marca un poco más «appreciate».",
                shadowFix = "Repite solo «taking the time» una vez más.",
                examTitle = "IELTS Speaking 7.0", interviewTitle = "Entrevista en una empresa internacional")
            language.startsWith("fr") -> Texts(
                lesson = "Entretien",
                goals = listOf("Dire ce que tu fais", "Dire pourquoi tu postules", "Dire en quoi tes points forts collent au poste"),
                reason = "«${nb}Stay calm when… come up$nb» sonne plus naturel, et situation prend le pluriel.",
                why = "Situation est dénombrable$nb: il faut le pluriel.",
                coachMeaning = "Je bosse sur [un projet d’IA] en ce moment, et ça avance super bien.",
                shadowPronunciation = "Tu as oublié le «${nb}the$nb» de «${nb}taking the time$nb». Dis les trois mots d’un seul bloc.",
                shadowPacing = "Ton rythme colle à l’original. Appuie un peu plus sur «${nb}appreciate$nb».",
                shadowFix = "Répète juste «${nb}taking the time$nb» encore une fois.",
                examTitle = "IELTS Speaking 7.0", interviewTitle = "Entretien dans une boîte internationale")
            language.startsWith("de") -> Texts(
                lesson = "Jobinterview",
                goals = listOf("Sagen, was du machst", "Sagen, warum du dich bewirbst", "Sagen, warum deine Stärken passen"),
                reason = "„Stay calm when … come up“ klingt natürlicher, und situation steht im Plural.",
                why = "Situation ist zählbar, also Plural.",
                coachMeaning = "Ich arbeite gerade an [einem KI-Projekt], und es läuft richtig gut.",
                shadowPronunciation = "Bei „taking the time“ fehlt das „the“. Sag die drei Wörter in einem Zug.",
                shadowPacing = "Dein Tempo passt zum Original. Betone „appreciate“ etwas stärker.",
                shadowFix = "Sprich nur „taking the time“ noch einmal nach.",
                examTitle = "IELTS Speaking 7.0", interviewTitle = "Vorstellungsgespräch")
            else -> Texts(
                lesson = "Job interview intro",
                goals = listOf("Say what you do now", "Say why you applied", "Say how your strengths fit the job"),
                reason = "\"Stay calm when … come up\" sounds more natural, and situation needs the plural.",
                why = "Situation is countable, so it takes the plural.",
                coachMeaning = "",
                shadowPronunciation = "You dropped \"the\" in \"taking the time\". Say the three words as one chunk.",
                shadowPacing = "Your pace matches the original. Lean a little more on \"appreciate\".",
                shadowFix = "Shadow just \"taking the time\" once more.",
                examTitle = "IELTS Speaking 7.0", interviewTitle = "Job interview at a tech company")
        }
    }
}
