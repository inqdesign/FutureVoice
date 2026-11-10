package com.roro.futurevoice.talk

import com.roro.futurevoice.data.LanguageCatalog

/**
 * iOS `ConversationEngine+LanguageLines.swift` (5a462332, 2026-11-06): prompt
 * lines for ONE target language each, measured with the beginner, reply-leak,
 * correction and tutor probes on Haiku 5.5. Every function is "" for any
 * other language, so those prompts stay byte-identical. The coach's bracket
 * line (`CoachSuggester.bracketAgreementLine`) lives on [CoachSuggester].
 *
 * Hand-ported (logic + text); the generated prompts call these, and
 * `ConversationPromptVectorTest` holds the assembled prompts to iOS.
 */
object LanguageLines {
    private fun base(code: String) = code.substringBefore('-')

    /** iOS `beginnerQuestionLanguageLine` — appended to `beginnerQuestions`
     *  (A1/A2 only, where that block exists). */
    fun beginnerQuestion(targetLanguage: String): String = when (base(targetLanguage)) {
        "ko" -> "\n- KOREAN, BEGINNER QUESTIONS: at this level every question is one they" +
            "\n  can answer in a word or with yes/no, the first turn included — like" +
            "\n  \"오늘 일했어?\", \"지금 집이야?\", \"커피 매일 마셔?\"."
        "ja" -> "\n- JAPANESE, BEGINNER QUESTIONS: at this level every question is one they" +
            "\n  can answer in a word or with yes/no, the first turn included:" +
            "\n  「今日は仕事だった？」「今、家にいる？」「毎日飲む？」. 「最近どう？」" +
            "\n  「どんな感じ？」「どんな一日だった？」「何してた？」 are open questions," +
            "\n  so they are never asked."
        else -> ""
    }

    /** iOS `selfAddressLine` — after the form-of-address rule, only while the
     *  model IS the learner's future self (no cast person, no topic). */
    fun selfAddress(targetLanguage: String, asFutureSelf: Boolean): String {
        if (!asFutureSelf) return ""
        return when (base(targetLanguage)) {
            "ja" -> "\n- JAPANESE, HOW YOU CALL THEM: by their bare name (\"ミンジ\", \"ケン\") or" +
                "\n  きみ, the way you talk to yourself. Your own first person is 私 for the" +
                "\n  whole call, and most sentences need none."
            else -> ""
        }
    }

    /** iOS `spanishGuard` — in HOW TO TALK after the variety guard. The gender
     *  half only as the future self; the variety half only when no other
     *  variety was picked (Castilian has its own line). */
    fun spanishGuard(targetLanguage: String, asFutureSelf: Boolean,
                     accentId: String? = LanguageVariety.accentId): String {
        if (base(targetLanguage) != "es") return ""
        var out = ""
        if (asFutureSelf) {
            out += "\n- SPANISH, GENDER: you are them, so you share their gender, and you don't" +
                "\n  know it until About the user says it or they show it in a word about" +
                "\n  themselves. Until then, say things in forms that have no gender (\"Mucho" +
                "\n  gusto.\", \"Qué gusto.\", \"No pasa nada.\", \"¿Estás bien?\"); once they" +
                "\n  show it, use that form for both of you for the rest of the call."
        }
        if (LanguageVariety.writingVariety(targetLanguage, accentId) == null) {
            out += "\n- SPANISH, WHICH SPANISH: your voice has a Latin American accent, so speak" +
                "\n  everyday Latin American Spanish, the kind understood from Mexico to" +
                "\n  Argentina. Never the Spain-only words: vale, vaya, apetece, liado, guay," +
                "\n  mola, coger, vosotros, café solo (say café negro)."
        }
        return out
    }

    /** iOS `notesLanguageGuard` — the explanation notes ("why", "reason") in
     *  the learner's own language when the target is Japanese or German. */
    fun notesLanguageGuard(targetLanguage: String, nativeLanguage: String): String {
        val target = base(targetLanguage)
        val native = base(nativeLanguage)
        if (!(target == "ja" || target == "de") || native == target) return ""
        if (target == "ja" && native == "ko") {
            return "\n- NOTES IN KOREAN: \"reason\" and every \"why\" are Korean sentences with" +
                "\n  the Japanese words that changed quoted inside them, like this:" +
                "\n  \"reason\": \"가는 곳은 「学校に」로 말해야 자연스러워요.\"," +
                "\n  \"why\": \"가는 곳에는 「を」가 아니라 「に」를 써요.\". Never a Japanese" +
                "\n  sentence, not even a short one: this learner reads the notes in Korean."
        }
        val nativeName = LanguageCatalog.englishName(nativeLanguage)
        val targetName = LanguageCatalog.englishName(targetLanguage)
        val terms = if (target == "de") "Akkusativ, Perfekt, Partizip" else "助詞, 過去形, て形"
        return "\n- NOTES IN ${nativeName.uppercase()}, EVERY ONE: each \"why\" and the \"reason\"" +
            "\n  are read by someone who thinks in $nativeName. Write every one of them in" +
            "\n  $nativeName, never in $targetName, even though what they explain is" +
            "\n  $targetName: $targetName appears only as the quoted words that changed," +
            "\n  and grammar names are said in $nativeName (not $terms)."
    }

    /** iOS `spokenGrammarGuard` — spoken forms the correction prompts "fixed". */
    fun spokenGrammarGuard(targetLanguage: String): String = when (base(targetLanguage)) {
        "es" -> "\n- SPANISH REPORTED SPEECH: after a past verb of saying (dijo, me contó," +
            "\n  comentó) the reported verb may stay in the present when it is still true" +
            "\n  now (\"me dijo que está bien\", \"dijo que viene mañana\"): that is correct" +
            "\n  Spanish, not a slip; never turn it into the imperfect."
        "de" -> "\n- GERMAN DEMONSTRATIVES: in speech der / die / das stand for \"he / she /" +
            "\n  it\" at the start of a clause (\"der meinte, das passt\", \"die kommt" +
            "\n  morgen\"): correct spoken German, never a fix, and never swapped for" +
            "\n  er / sie / es."
        else -> ""
    }

    /** iOS `tutorRegisterLine` — tutor mode's own voice. */
    fun tutorRegisterLine(targetLanguage: String): String = when (base(targetLanguage)) {
        "ko" -> "\n- Korean: your own words are 반말 in EVERY line, also right after an" +
            "\n  example line in 해요체 (\"좋아, 잘했어! 이제 세 번째야.\", never \"좋아요," +
            "\n  잘했어요\"). A line you say back for them to repeat keeps the ending THEY" +
            "\n  used: they said 일해요, so you say \"회사에서 엔지니어로 일해요\", never \"일해\"."
        "ja" -> "\n- Japanese: your own words are plain form in EVERY line (\"じゃあ、言ってみて\"," +
            "\n  never です/ます, ください or しましょう in your own words), and never あなた:" +
            "\n  say their name or nothing. A line you say back for them to repeat keeps" +
            "\n  the ending THEY used: they said しています, so it stays しています."
        // The ONCE MORE note's "so it sticks" came out as the calque "para
        // que se quede" 4/4; this line, verbatim, is 0/6 (iOS).
        "es" -> "\n- Spanish, ONCE MORE: asking for it again is just \"¡Muy bien! Dilo otra vez.\"" +
            " The reason stays unsaid."
        else -> ""
    }
}
