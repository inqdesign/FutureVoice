import Foundation

/// Single source of truth for everything that varies per TARGET language.
/// The app stores bare BCP-47 codes ("en", "ko") in settings; every
/// language-dependent capability — display names, the concrete STT locale,
/// how shadow scoring tokenizes, which graded wordlist ships — resolves
/// through here. Adding a language = one entry in `targets` plus optional
/// bundled resources; nothing else should hardcode a language.
enum LanguageCatalog {

    /// How ShadowEngine splits text for diff/scoring.
    enum TokenStyle {
        /// Whitespace-delimited scripts — compare word by word.
        case word
        /// CJK — spacing is absent (ja/zh) or too unstable in STT output (ko)
        /// to compare on; compare character by character instead.
        case syllable
    }

    struct Language {
        let code: String              // bare BCP-47 code, persisted in settings
        let sttLocale: String         // concrete locale for SFSpeechRecognizer
        let tokenStyle: TokenStyle
        let wordlistResource: String? // bundled graded-vocab TSV; nil = none yet
    }

    /// UserDefaults key for the current target language. Lives here (not in
    /// AppState) so non-UI services like CoreVocabulary can read it too.
    static let targetLanguageDefaultsKey = "futurevoice.targetLanguage"

    /// Languages offered as a practice target (order = setup picker order).
    static let targets: [Language] = [
        Language(code: "en", sttLocale: "en-US", tokenStyle: .word, wordlistResource: "cefr_words"),
        Language(code: "es", sttLocale: "es-ES", tokenStyle: .word, wordlistResource: nil),
        Language(code: "de", sttLocale: "de-DE", tokenStyle: .word, wordlistResource: nil),
        Language(code: "fr", sttLocale: "fr-FR", tokenStyle: .word, wordlistResource: nil),
        Language(code: "it", sttLocale: "it-IT", tokenStyle: .word, wordlistResource: nil),
        Language(code: "pt", sttLocale: "pt-BR", tokenStyle: .word, wordlistResource: nil),
        Language(code: "ja", sttLocale: "ja-JP", tokenStyle: .syllable, wordlistResource: nil),
        // Korean wordlist: 국립국어원 「한국어 학습용 어휘 목록」 (2003, 5,965
        // headwords, grades A/B/C) → A/B/C split by in-grade frequency rank
        // into a1/a2, b1/b2, c1/c2.
        Language(code: "ko", sttLocale: "ko-KR", tokenStyle: .syllable, wordlistResource: "cefr_words_ko"),
        Language(code: "zh", sttLocale: "zh-CN", tokenStyle: .syllable, wordlistResource: nil),
    ]

    /// Languages offered as the learner's NATIVE language — what every
    /// explanation, correction and word-card gloss is written in. Unlike
    /// `targets`, a native language needs NO STT locale, wordlist or
    /// tokenizer: it's only ever handed to the LLM as a display name, so any
    /// BCP-47 code the OS can name works. That's why this list is far wider
    /// than `targets` — it covers essentially every sizable language-learning
    /// market. Ordered by region (East/SE Asia → South Asia → Middle East &
    /// Central Asia → Europe → Africa); order = setup picker order.
    /// English included since multi-language: the practice target is
    /// user-selectable, so an English native learning Japanese is a real user.
    /// Pickers filter out whichever code sits on the other side.
    static let nativeLanguages: [String] = [
        // East & Southeast Asia
        "ko", "ja", "zh", "vi", "th", "id", "ms", "fil", "km", "my", "lo", "mn",
        // South Asia
        "hi", "bn", "ur", "ta", "te", "mr", "gu", "kn", "ml", "pa", "ne", "si",
        // Middle East & Central Asia
        "ar", "fa", "tr", "he", "kk", "uz", "az", "ka", "hy", "ps",
        // Europe
        "en", "es", "pt", "fr", "de", "it", "ru", "pl", "uk", "nl", "ro", "el", "cs",
        "hu", "sv", "da", "fi", "no", "sk", "bg", "hr", "sr", "lt", "lv", "et",
        "sl", "ca",
        // Africa
        "sw", "am", "af", "ha", "yo", "zu",
    ]

    static func language(_ code: String) -> Language? {
        let base = code.split(separator: "-").first.map(String.init) ?? code
        return targets.first { $0.code == base }
    }

    /// English display name — for prompts ("Reply in Korean only") and UI
    /// copy ("Your Korean"). Never feed a bare code into a prompt: models
    /// treat "en" and "English" differently.
    static func englishName(_ code: String) -> String {
        Locale(identifier: "en").localizedString(forLanguageCode: code)?.capitalized
            ?? code.uppercased()
    }

    /// Name in its own language ("Deutsch", "한국어") — for pickers.
    static func endonym(_ code: String) -> String {
        Locale(identifier: code).localizedString(forLanguageCode: code)?.capitalized
            ?? code.uppercased()
    }

    /// Concrete locale for SFSpeechRecognizer. Bare codes like "zh" don't
    /// reliably resolve to a supported recognizer; map to a real region.
    static func sttLocale(_ code: String) -> String {
        language(code)?.sttLocale ?? code
    }

    static func tokenStyle(_ code: String) -> TokenStyle {
        language(code)?.tokenStyle ?? .word
    }

    // MARK: - Level naming

    /// TOPIK equivalents of the CEFR bands, per the 국제통용 한국어 표준
    /// 교육과정 correspondence (A1→1급 … C2→6급).
    private static let topikByCEFR: [CEFRLevel: Int] = [
        .a1: 1, .a2: 2, .b1: 3, .b2: 4, .c1: 5, .c2: 6
    ]

    /// JLPT equivalents (JF Standard rough correspondence, A1→N5 … C1→N1).
    /// C2 sits past the JLPT scale, so it stays bare CEFR.
    private static let jlptByCEFR: [CEFRLevel: Int] = [
        .a1: 5, .a2: 4, .b1: 3, .b2: 2, .c1: 1
    ]

    /// How a CEFR level should read for a given target language. Internals
    /// stay CEFR everywhere; Korean learners think in TOPIK and Japanese
    /// learners in JLPT, so those labels carry the equivalence alongside.
    static func levelLabel(_ level: CEFRLevel, target: String) -> String {
        let cefr = level.rawValue.uppercased()
        switch language(target)?.code {
        case "ko":
            guard let topik = topikByCEFR[level] else { return cefr }
            return "\(cefr) · TOPIK \(topik)"
        case "ja":
            guard let jlpt = jlptByCEFR[level] else { return cefr }
            return "\(cefr) · JLPT N\(jlpt)"
        default:
            return cefr
        }
    }
}
