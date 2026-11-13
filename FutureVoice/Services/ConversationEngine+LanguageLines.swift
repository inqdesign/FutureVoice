import Foundation

/// Lines a call prompt carries for ONE target language only (2026-11-06).
///
/// Measured with `scripts/beginner-probe.py` + `scripts/reply-leak-probe.py`
/// on the live reply model (Haiku 5.5) and the hedge: the shared rules are
/// written with English examples, and the Korean, Japanese and German replies
/// kept their own native habits through them — "오늘 하루 어땠어?" /
/// 「最近どう？」 to an A1 learner, 「ケンさん」 to the learner
/// by name in タメ口, a first person that changed with each run (the model was
/// guessing the learner's gender), and in Spanish the words of Spain under a
/// Mexican voice plus a gendered "encantado/cansada" for a learner whose
/// gender nobody knows. Each line names the RIGHT form; quoting the wrong one
/// as a ban made Haiku say it and correct itself aloud ("ケンさん…じゃなくて").
///
/// Every function returns "" for any other language, so every other prompt is
/// byte-identical (`LanguageLineTests`).
extension ConversationEngine {

    /// Appended to `beginnerQuestions` (A1/A2 only, where that block exists).
    /// Probe, A1/A2 open questions: ko 20/74 → 10/75 (leaks 3 → 1), ja 13/72 →
    /// 0/76. Korean names only the right questions: listing the wrong ones
    /// doubled Haiku's spoken self-checks there. Japanese keeps its list:
    /// without it the open questions came back (7/74).
    /// A German line ("a reaction never asks why") was tried and dropped:
    /// "Warum denn?" stayed, and Haiku said its self-check aloud.
    static func beginnerQuestionLanguageLine(_ targetLanguage: String) -> String {
        switch LanguageCatalog.base(targetLanguage) {
        case "ko":
            return "\n- KOREAN, BEGINNER QUESTIONS: at this level every question is one they"
                + "\n  can answer in a word or with yes/no, the first turn included — like"
                + "\n  \"오늘 일했어?\", \"지금 집이야?\", \"커피 매일 마셔?\"."
        case "ja":
            return "\n- JAPANESE, BEGINNER QUESTIONS: at this level every question is one they"
                + "\n  can answer in a word or with yes/no, the first turn included:"
                + "\n  「今日は仕事だった？」「今、家にいる？」「毎日飲む？」. 「最近どう？」"
                + "\n  「どんな感じ？」「どんな一日だった？」「何してた？」 are open questions,"
                + "\n  so they are never asked."
        default:
            return ""
        }
    }

    /// After the form-of-address rule, only while the model IS the learner's
    /// future self (no cast person, no scene to infer a role from): a barista
    /// or a colleague says さん, the learner's own self never does.
    /// Probe: さん 3 → 0, mixed first person 4 → 0.
    static func selfAddressLine(_ targetLanguage: String, asFutureSelf: Bool) -> String {
        guard asFutureSelf else { return "" }
        switch LanguageCatalog.base(targetLanguage) {
        case "ja":
            return "\n- JAPANESE, HOW YOU CALL THEM: by their bare name (\"ミンジ\", \"ケン\") or"
                + "\n  きみ, the way you talk to yourself. Your own first person is 私 for the"
                + "\n  whole call, and most sentences need none."
        default:
            return ""
        }
    }

    /// Spanish, in HOW TO TALK after `varietyGuard`. The variety half only
    /// when no other variety was picked (Castilian has its own line); the
    /// gender half only while the model is the learner's future self — a cast
    /// person has their own gender. Probe: Spain-only words 11 → 0, guessed
    /// gender ~12 → 3 in 112. The gender line names only the neutral forms:
    /// quoting the gendered ones made Haiku say one and correct itself.
    static func spanishGuard(_ targetLanguage: String,
                             asFutureSelf: Bool,
                             accentId: String? = UserDefaults.standard.string(forKey: VoiceAccentCatalog.storedAccentKey)) -> String {
        guard LanguageCatalog.base(targetLanguage) == "es" else { return "" }
        var out = ""
        if asFutureSelf {
            out += "\n- SPANISH, GENDER: you are them, so you share their gender, and you don't"
                + "\n  know it until About the user says it or they show it in a word about"
                + "\n  themselves. Until then, say things in forms that have no gender (\"Mucho"
                + "\n  gusto.\", \"Qué gusto.\", \"No pasa nada.\", \"¿Estás bien?\"); once they"
                + "\n  show it, use that form for both of you for the rest of the call."
        }
        if VoiceAccentCatalog.writingVariety(for: targetLanguage, accentId: accentId) == nil {
            out += "\n- SPANISH, WHICH SPANISH: your voice has a Latin American accent, so speak"
                + "\n  everyday Latin American Spanish, the kind understood from Mexico to"
                + "\n  Argentina. Never the Spain-only words: vale, vaya, apetece, liado, guay,"
                + "\n  mola, coger, vosotros, café solo (say café negro)."
        }
        return out
    }

    /// French, beside `spanishGuard` and for the same reason: French marks
    /// the speaker's gender too (enchanté/enchantée, content/contente), and
    /// with no line Haiku spoke as a man to a learner named Minji in every
    /// beginner-probe call that needed a form (2026-11-13). Neutral forms
    /// only, the Spanish lesson.
    static func frenchGuard(_ targetLanguage: String, asFutureSelf: Bool) -> String {
        guard LanguageCatalog.base(targetLanguage) == "fr", asFutureSelf else { return "" }
        return "\n- FRENCH, GENDER: you are them, so you share their gender, and you don't"
            + "\n  know it until About the user says it or they show it in a word about"
            + "\n  themselves. Until then, say things in forms that have no gender, meeting"
            + "\n  them included (\"Ça me fait plaisir de te rencontrer.\", \"Pas de souci.\","
            + "\n  \"Tu as bien dormi ?\"); once they show it, use that form for both of you"
            + "\n  for the rest of the call."
    }
}

// MARK: - Corrections, tutor and coach (2026-11-06)
//
// Measured with `scripts/correction-probe.py` (a copy that takes a native
// language — the script hardcodes English, which hid the first one), the
// coach probe and a five-language tutor probe, all on Haiku 5.5 as production
// runs them. Every function is "" outside its language.
extension ConversationEngine {

    /// The explanation notes ("why", "reason") came back in the TARGET
    /// language when the learner thinks in another one: Japanese 19/48 and
    /// German 7/48 with Korean as the native language (Spanish 0, English
    /// 1). After: German 0/48, Japanese 6/48 (only with the worked example).
    /// French (2026-11-13): Haiku wrote 5/36 in ENGLISH for a Korean speaker.
    static func notesLanguageGuard(_ targetLanguage: String, nativeLanguage: String) -> String {
        let target = LanguageCatalog.base(targetLanguage)
        let native = LanguageCatalog.base(nativeLanguage)
        guard ["ja", "de", "fr"].contains(target), native != target else { return "" }
        if target == "ja" && native == "ko" {
            return "\n- NOTES IN KOREAN: \"reason\" and every \"why\" are Korean sentences with"
                + "\n  the Japanese words that changed quoted inside them, like this:"
                + "\n  \"reason\": \"가는 곳은 「学校に」로 말해야 자연스러워요.\","
                + "\n  \"why\": \"가는 곳에는 「を」가 아니라 「に」를 써요.\". Never a Japanese"
                + "\n  sentence, not even a short one: this learner reads the notes in Korean."
        }
        let nativeName = LanguageCatalog.englishName(nativeLanguage)
        let targetName = LanguageCatalog.englishName(targetLanguage)
        let terms = target == "de" ? "Akkusativ, Perfekt, Partizip"
            : target == "fr" ? "passé composé, subjonctif, accord" : "助詞, 過去形, て形"
        return "\n- NOTES IN \(nativeName.uppercased()), EVERY ONE: each \"why\" and the \"reason\""
            + "\n  are read by someone who thinks in \(nativeName). Write every one of them in"
            + "\n  \(nativeName), never in \(targetName), even though what they explain is"
            + "\n  \(targetName): \(targetName) appears only as the quoted words that changed,"
            + "\n  and grammar names are said in \(nativeName) (not \(terms))."
    }

    /// Spoken forms the correction prompts "fixed": Spanish present tense
    /// in reported speech that is still true ("me dijo que está bien" →
    /// "estaba", 2/2 runs; after 0/94 false, 0/24 missed) and German
    /// demonstrative pronouns ("der meinte" → "er meinte"; after 0/70, 0/24).
    /// French: Haiku put the dropped ne back ("je m'en souviens plus", 1 of
    /// 94 spoken lines; Gemini 0/94, 0/26 missed).
    static func spokenGrammarGuard(_ targetLanguage: String) -> String {
        switch LanguageCatalog.base(targetLanguage) {
        case "es":
            return "\n- SPANISH REPORTED SPEECH: after a past verb of saying (dijo, me contó,"
                + "\n  comentó) the reported verb may stay in the present when it is still true"
                + "\n  now (\"me dijo que está bien\", \"dijo que viene mañana\"): that is correct"
                + "\n  Spanish, not a slip; never turn it into the imperfect."
        case "de":
            return "\n- GERMAN DEMONSTRATIVES: in speech der / die / das stand for \"he / she /"
                + "\n  it\" at the start of a clause (\"der meinte, das passt\", \"die kommt"
                + "\n  morgen\"): correct spoken German, never a fix, and never swapped for"
                + "\n  er / sie / es."
        case "fr":
            return "\n- SPOKEN FRENCH: a negation said without its ne (\"je sais pas\", \"je m'en"
                + "\n  souviens plus\"), on for \"we\", a dropped il in \"faut que\", ça and t'as are"
                + "\n  how French is spoken: correct, never a fix, and never written back"
                + "\n  into the written form."
        default:
            return ""
        }
    }

    /// Tutor mode's own voice. Baseline: the Korean tutor slipped into 해요체
    /// or said the learner's 해요 line back in 반말 in 5 of 18 lines, the
    /// Japanese one spoke です/ます with あなた in 6 of 12. After: 0/16, 0/8.
    /// Spanish: the "say it again" calque, 4/4 → 0/6.
    static func tutorRegisterLine(_ targetLanguage: String) -> String {
        switch LanguageCatalog.base(targetLanguage) {
        case "ko":
            return "\n- Korean: your own words are 반말 in EVERY line, also right after an"
                + "\n  example line in 해요체 (\"좋아, 잘했어! 이제 세 번째야.\", never \"좋아요,"
                + "\n  잘했어요\"). A line you say back for them to repeat keeps the ending THEY"
                + "\n  used: they said 일해요, so you say \"회사에서 엔지니어로 일해요\", never \"일해\"."
        case "ja":
            return "\n- Japanese: your own words are plain form in EVERY line (\"じゃあ、言ってみて\","
                + "\n  never です/ます, ください or しましょう in your own words), and never あなた:"
                + "\n  say their name or nothing. A line you say back for them to repeat keeps"
                + "\n  the ending THEY used: they said しています, so it stays しています."
        case "es":
            // The ONCE MORE note says "so it sticks", and Haiku said it as
            // "para que se quede" 4/4 (a calque). Naming the reason the right
            // way ("para que se te quede") spread it onto every NOT YET too;
            // this one line, verbatim, is 0/6 with NOT YET unchanged.
            return "\n- Spanish, ONCE MORE: asking for it again is just \"¡Muy bien! Dilo otra vez.\""
                + " The reason stays unsaid."
        default:
            return ""
        }
    }
}

extension CoachSuggester {
    /// A coach placeholder bracketed the number without its noun ("seit
    /// [zwei] Jahren", "tengo [dos] hermanos"), so the learner's own "one"
    /// broke the agreement. German 15/24 → 0/24, Spanish 8/24 → 0/24.
    nonisolated static func bracketAgreementLine(_ target: String) -> String {
        switch LanguageCatalog.base(target) {
        case "de":
            return "\n- A bracket holds the WHOLE phrase that changes when they put in their"
                + " own fact: a number together with its noun, an article together with its"
                + " noun (\"seit [zwei Jahren]\", \"ich hab [einen Bruder]\" — never \"seit [zwei]"
                + " Jahren\"), because in German the noun and its ending change with the number."
        case "es":
            return "\n- A bracket holds the WHOLE phrase that changes when they put in their"
                + " own fact: a number together with its noun, an article together with its"
                + " noun (\"llevo [dos años]\", \"tengo [un hermano]\" — never \"tengo [dos]"
                + " hermanos\"), because in Spanish the noun changes with the number."
        default:
            return ""
        }
    }
}
