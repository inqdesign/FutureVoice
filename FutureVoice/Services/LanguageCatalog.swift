import Foundation
import Speech

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

    /// UserDefaults key for the learner's NATIVE language — the language every
    /// explanation, correction note and report is written in. Same reasoning as
    /// `targetLanguageDefaultsKey`: prompt builders in `Services/` need it and
    /// must not reach into AppState.
    static let nativeLanguageDefaultsKey = "futurevoice.nativeLanguage"

    /// Current native language, for the non-UI callers that can't be handed one.
    /// Mirrors AppState's default so both agree before setup writes a choice.
    static var currentNative: String {
        UserDefaults.standard.string(forKey: nativeLanguageDefaultsKey) ?? defaultNative
    }

    /// Best guess at the learner's native language from the device, used to
    /// pre-select the setup picker.
    ///
    /// Falls back to English, NOT to the launch market. A wrong guess here is
    /// not neutral: it decides which language every explanation is written in,
    /// and it silently removes that language from the target picker (the two
    /// can't coincide). Defaulting an unrecognized device to Korean told a
    /// Spanish speaker they were Korean and then coached them in Korean;
    /// English is the one guess that degrades to "a language I can probably
    /// read" instead of "a language I've never seen".
    static var defaultNative: String {
        for identifier in Locale.preferredLanguages {
            let code = Locale(identifier: identifier).language.languageCode?.identifier
                ?? identifier.split(separator: "-").first.map(String.init)
            if let code, nativeLanguages.contains(code) { return code }
        }
        return "en"
    }

    /// Languages offered as a practice target (order = setup picker order).
    static let targets: [Language] = [
        Language(code: "en", sttLocale: "en-US", tokenStyle: .word, wordlistResource: "cefr_words"),
        Language(code: "es", sttLocale: "es-ES", tokenStyle: .word, wordlistResource: nil),
        // German wordlist: Goethe-Institut A1–B1 vocabulary (content words)
        // plus curated B2–C2 — cased headwords (nouns capitalized), matched
        // case-insensitively by CoreVocabulary.
        Language(code: "de", sttLocale: "de-DE", tokenStyle: .word, wordlistResource: "cefr_words_de"),
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
    ///
    /// This list was once narrowed to the three languages with a translated
    /// `Localizable.xcstrings` column, on the theory that an untranslated
    /// native language reads as a broken app. That trade was wrong, and the
    /// filtering above is why: a Spanish speaker who honestly picked English
    /// as their native language lost English from the TARGET picker, and the
    /// only way back to it was to declare themselves Korean or German and take
    /// every explanation in a language they don't speak. Narrowing the list
    /// didn't lower the quality bar — it closed the market.
    ///
    /// What a language without a catalog column actually gets today:
    /// - LLM coaching text — correction notes, scorecard commentary, weekly
    ///   report prose, drill memory hooks, word glosses — is GENERATED from
    ///   `CoachingLanguage.contract`, so it comes back in their real language.
    ///   That's the majority of the words a learner reads.
    /// - Static `explain()` copy falls back to English via `Bundle.explanations`
    ///   (whose `.main` fallback is deliberate — see UILanguage).
    /// - Chrome is unaffected: it follows the TARGET language, and every
    ///   selectable target has a column.
    ///
    /// So the cost of listing a language here is bounded and known, and a
    /// language earns its column by showing up in the numbers. Ordered by
    /// region (East/SE Asia → South Asia → Middle East & Central Asia →
    /// Europe → Africa).
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

    /// `nativeLanguages` reordered so the device's own languages come first.
    ///
    /// Region order is the right *reference* order and the wrong *picker*
    /// order: at 66 entries the honest answer is a scroll away for everyone
    /// whose language isn't Korean. The device already knows, so the answer
    /// rides at the top and the regional list follows unchanged for anyone
    /// whose phone is set to a language they don't actually think in.
    static var nativeChoices: [String] {
        var seen = Set<String>()
        let preferred = Locale.preferredLanguages
            .compactMap { Locale(identifier: $0).language.languageCode?.identifier }
            .filter { nativeLanguages.contains($0) && seen.insert($0).inserted }
        return preferred + nativeLanguages.filter { !seen.contains($0) }
    }

    /// The languages the APP itself is written in — the ones with a real
    /// column in `Localizable.xcstrings`, so `explain()` copy resolves instead
    /// of falling back to English. Read from the built bundle's `.lproj`
    /// folders rather than a hand-kept list: adding a column is still just a
    /// catalog edit, and this can't drift from it.
    ///
    /// Everything in `nativeChoices` beyond these still gets LLM coaching text
    /// in the learner's own language (see the note above) — the picker groups
    /// on this so the difference is visible BEFORE they choose, not after.
    static var translatedLanguages: [String] {
        let bundled = Set(Bundle.main.localizations.compactMap {
            Locale(identifier: $0).language.languageCode?.identifier
        })
        return nativeLanguages.filter { bundled.contains($0) }
    }

    static func language(_ code: String) -> Language? {
        let base = code.split(separator: "-").first.map(String.init) ?? code
        return targets.first { $0.code == base }
    }

    /// Targets a user may actually PICK. A target without a graded wordlist
    /// still talks, corrects, drills and shadows perfectly — but its whole
    /// vocabulary layer comes up empty (nothing is ever collected from a
    /// talk, the CEFR filter has nothing to filter, pickup words and the word
    /// widget stay blank), and that reads as a bug, not as a missing extra.
    /// So the picker only offers what the app can deliver end to end; the
    /// rest stay in `targets` — already wired for STT, scoring and the clone
    /// script — and return on their own the moment a list ships for them.
    static var selectableTargets: [Language] {
        targets.filter { $0.wordlistResource != nil }
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
    /// The concrete locale to hand `SFSpeechRecognizer`.
    ///
    /// The `targets` table only covers the nine languages the app teaches,
    /// but dictation also runs in the learner's NATIVE language — and that
    /// list is sixty-odd. Falling back to the bare code ("vi", "th") built a
    /// recognizer iOS refuses to make, so dictation silently did nothing for
    /// everyone whose native language happened not to also be a practice
    /// target. Ask the system what it actually supports instead of keeping a
    /// second table that would drift.
    static func sttLocale(_ code: String) -> String {
        if let known = language(code)?.sttLocale { return known }
        return systemRecognizerLocale(for: code) ?? code
    }

    /// True when iOS can dictate in this language at all. Callers use it to
    /// avoid offering a mic that can only fail.
    static func canDictate(_ code: String) -> Bool {
        language(code) != nil || systemRecognizerLocale(for: code) != nil
    }

    /// EVERY language this device can dictate in, as bare codes.
    ///
    /// Dictation choice used to be "your native language or the one you're
    /// learning" — a made-up pair. A Japanese speaker living in Germany and
    /// learning English may well find it easiest to describe a situation in
    /// German, and there is no reason the app should refuse. The device
    /// already knows what it can hear; offer that.
    static func dictatableLanguages() -> [String] {
        if let cached = dictatableCache { return cached }
        var seen = Set<String>()
        var codes: [String] = []
        for locale in SFSpeechRecognizer.supportedLocales() {
            guard let base = locale.language.languageCode?.identifier,
                  seen.insert(base).inserted else { continue }
            codes.append(base)
        }
        let sorted = codes.sorted { endonym($0).localizedCaseInsensitiveCompare(endonym($1)) == .orderedAscending }
        dictatableCache = sorted
        return sorted
    }
    private static var dictatableCache: [String]?

    /// Best supported recognizer locale for a bare language code — the
    /// device's own region first ("pt-BR" for a Brazilian), else whichever
    /// region the system lists. Cached: `supportedLocales()` walks every
    /// installed locale and this is called per dictation start.
    private static var recognizerLocaleCache: [String: String?] = [:]
    private static func systemRecognizerLocale(for code: String) -> String? {
        let base = code.split(separator: "-").first.map(String.init) ?? code
        if let cached = recognizerLocaleCache[base] { return cached }
        let supported = SFSpeechRecognizer.supportedLocales()
        let matches = supported.filter {
            ($0.language.languageCode?.identifier ?? "") == base
        }
        let preferredRegion = Locale.current.region?.identifier
        let pick = matches.first { $0.region?.identifier == preferredRegion }
            ?? matches.sorted { $0.identifier < $1.identifier }.first
        let result = pick?.identifier
        recognizerLocaleCache[base] = result
        return result
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
