package com.roro.futurevoice.data

/**
 * Port of iOS `LanguageCatalog.swift`. Single source of truth for everything
 * that varies per TARGET language — see `docs/contracts/behavior.md` §7.
 *
 * Nothing outside this table may hardcode a language.
 */
object LanguageCatalog {

    enum class TokenStyle { WORD, SYLLABLE }

    data class Language(
        val code: String,
        val sttLocale: String,
        val tokenStyle: TokenStyle,
    )

    val targets = listOf(
        Language("en", "en-US", TokenStyle.WORD),
        Language("es", "es-ES", TokenStyle.WORD),
        Language("de", "de-DE", TokenStyle.WORD),
        Language("fr", "fr-FR", TokenStyle.WORD),
        Language("it", "it-IT", TokenStyle.WORD),
        Language("pt", "pt-BR", TokenStyle.WORD),
        Language("ja", "ja-JP", TokenStyle.SYLLABLE),
        Language("ko", "ko-KR", TokenStyle.SYLLABLE),
        Language("zh", "zh-CN", TokenStyle.SYLLABLE),
    )

    private val englishNames = mapOf(
        "en" to "English", "es" to "Spanish", "de" to "German", "fr" to "French",
        "it" to "Italian", "pt" to "Portuguese", "ja" to "Japanese",
        "ko" to "Korean", "zh" to "Chinese", "vi" to "Vietnamese",
        // Spelled out so a prompt told "Chinese" can't quietly write the
        // other script.
        "zh-Hant" to "Traditional Chinese", "zh-Hans" to "Simplified Chinese",
        "th" to "Thai", "id" to "Indonesian", "hi" to "Hindi", "ar" to "Arabic",
        "tr" to "Turkish", "ru" to "Russian", "pl" to "Polish", "nl" to "Dutch",
    )

    fun language(code: String): Language =
        targets.firstOrNull { it.code == code } ?: targets.first()

    fun sttLocale(code: String): String = language(code).sttLocale

    fun tokenStyle(code: String): TokenStyle = language(code).tokenStyle

    /** False for the languages that write no spaces between words — the one
     *  question [WordSplitter] asks. Chinese is here too, though it is not a
     *  selectable target: it must never be cut with the JAPANESE segmenter,
     *  so give `zh` its own before it gets a wordlist. */
    fun writesSpaces(code: String): Boolean = code.substringBefore('-') !in setOf("ja", "zh")

    fun englishName(code: String): String =
        englishNames[code] ?: code.uppercase()

    /** Targets offered in setup — everything with a graded word list. */
    val selectableTargets: List<Language>
        get() = targets.filter { it.code in setOf("en", "de", "ko", "ja") }

    /**
     * Languages a learner may name as NATIVE (`LanguageCatalog.swift`,
     * region-ordered). Coaching text is GENERATED per language, so the list
     * is wide; UI translation exists only for en/ko today.
     */
    val nativeLanguages: List<String> = listOf(
        // Chinese is listed BY SCRIPT: Traditional (Taiwan/HK/Macau) and
        // Simplified are different vocabularies, not just different glyphs,
        // and a learner has to be able to say which one they read.
        "ko", "ja", "zh-Hant", "zh-Hans", "vi", "th", "id", "ms", "fil", "km", "my", "lo", "mn",
        "hi", "bn", "ur", "ta", "te", "mr", "gu", "kn", "ml", "pa", "ne", "si",
        "ar", "fa", "tr", "he", "kk", "uz", "az", "ka", "hy", "ps",
        "en", "es", "pt", "fr", "de", "it", "ru", "pl", "uk", "nl", "ro", "el", "cs",
        "hu", "sv", "da", "fi", "no", "sk", "bg", "hr", "sr", "lt", "lv", "et",
        "sl", "ca",
        "sw", "am", "af", "ha", "yo", "zu",
    )

    /** Device-preferred languages first, then the regional list unchanged. */
    fun nativeChoices(): List<String> {
        val preferred = deviceLanguageCodes().filter { it in nativeLanguages }.distinct()
        return preferred + nativeLanguages.filter { it !in preferred }
    }

    /**
     * The same list, SPLIT by what picking it actually buys.
     *
     * A handful of languages are translated end to end; the other sixty only
     * get the LLM's coaching text, and the app's own screens stay English.
     * One flat list of sixty-six let someone pick Vietnamese and get an
     * English app without being told — the caveat has to be readable BEFORE
     * the tap, which is what the two groups are for. Both the setup step and
     * Me → App language read this, so they can never disagree.
     */
    data class NativeGroups(val translated: List<String>, val coachingOnly: List<String>)

    fun nativeGroups(): NativeGroups {
        val ui = com.roro.futurevoice.core.UILanguage.translated
        val all = nativeChoices()
        // A stored "zh" IS the Traditional column here, so it belongs above.
        fun isTranslated(code: String) =
            com.roro.futurevoice.core.UILanguage.normalize(code) != null && code in nativeLanguages ||
                code in ui
        return NativeGroups(
            translated = all.filter { isTranslated(it) },
            coachingOnly = all.filterNot { isTranslated(it) },
        )
    }

    fun defaultNative(): String =
        deviceLanguageCodes().firstOrNull { it in nativeLanguages } ?: "en"

    /**
     * Device-preferred languages as entries of [nativeLanguages] — script
     * qualified where the list is, so a phone set to zh-TW lands on
     * Traditional rather than on whatever a bare "zh" resolves to.
     */
    private fun deviceLanguageCodes(): List<String> {
        val locales = android.os.LocaleList.getDefault()
        return (0 until locales.size()).mapNotNull { i ->
            val l = locales.get(i)
            val script = l.script.takeIf { it.isNotEmpty() }
                ?: when (l.country) { "TW", "HK", "MO" -> "Hant"; "CN", "SG" -> "Hans"; else -> null }
            val qualified = script?.let { "${l.language}-$it" }
            when {
                qualified != null && qualified in nativeLanguages -> qualified
                l.language in nativeLanguages -> l.language
                else -> null
            }
        }
    }

    /**
     * A stored code as a native language. A bare "zh" was a valid choice
     * before Chinese was split by script; it means Simplified everywhere
     * else on the platform, so it maps there.
     */
    fun normalizedNative(code: String): String = if (code == "zh") "zh-Hans" else code

    /** True when two codes name the same language whatever the script or
     *  region — "zh-Hant" and "zh-Hans", "pt" and "pt-BR". */
    fun sameLanguage(a: String, b: String): Boolean = a.substringBefore('-') == b.substringBefore('-')

    /** Language name in its own language — "Deutsch", "한국어", "繁體中文". */
    fun endonym(code: String): String = name(code, code)

    /** Language name in the LEARNER's language — "영어" for a Korean. */
    fun ownName(code: String, native: String): String = name(code, native)

    /**
     * The name of [code] written in [locale] — the ONE helper every on-screen
     * language name goes through, because it keeps the SCRIPT.
     * `getDisplayLanguage` drops it, so both Chinese columns came back as
     * plain 中文 and the two rows of the picker read identically.
     */
    /**
     * The two Chinese scripts as iOS names them (`localizedString(forIdentifier:)`,
     * CLDR's short form). Android's ICU writes "Chinese (Traditional Han)" /
     * "中文 (繁體中文)" — the script's TECHNICAL name, and twice the length on a
     * picker row. Keyed by the locale's base language (zh by script).
     */
    private val chineseNames: Map<String, Pair<String, String>> = mapOf(
        "en" to ("Chinese, Traditional" to "Chinese, Simplified"),
        "ko" to ("중국어(번체)" to "중국어(간체)"),
        "ja" to ("中国語（繁体字）" to "中国語（簡体字）"),
        // Read off the iOS 26 simulator's App language page: in Chinese,
        // `localizedString(forIdentifier:)` names the script first.
        "zh-Hant" to ("繁體中文" to "簡體中文"),
        "zh-Hans" to ("繁体中文" to "简体中文"),
        "es" to ("Chino tradicional" to "Chino simplificado"),
        "fr" to ("Chinois traditionnel" to "Chinois simplifié"),
        "de" to ("Chinesisch (traditionell)" to "Chinesisch (vereinfacht)"),
    )

    private fun name(code: String, locale: String): String {
        // iOS's own spellings first (generated table), Android's ICU only for
        // a pair the table doesn't hold.
        if (code == locale) LanguageNames.endonyms[code]?.let { return it }
        val ui = when {
            locale in LanguageNames.inLocale -> locale
            locale.startsWith("zh") -> if (locale.contains("Hans") || locale.endsWith("CN")) "zh-Hans" else "zh-Hant"
            else -> locale.substringBefore('-')
        }
        LanguageNames.inLocale[ui]?.get(code)?.let { return it }
        if (code == "zh-Hant" || code == "zh-Hans") {
            val loc = java.util.Locale.forLanguageTag(locale)
            val key = if (loc.language == "zh") (if (loc.script == "Hans" || locale.endsWith("Hans")) "zh-Hans" else "zh-Hant")
                else loc.language
            chineseNames[key]?.let { return if (code == "zh-Hant") it.first else it.second }
        }
        val of = java.util.Locale.forLanguageTag(code)
        val inLocale = java.util.Locale.forLanguageTag(locale)
        val display = if (of.script.isNotEmpty()) of.getDisplayName(inLocale)
        else of.getDisplayLanguage(inLocale)
        return display.replaceFirstChar { it.uppercase() }.ifEmpty { englishName(code) }
    }

    private val topikByCefr = mapOf(CefrLevel.A1 to 1, CefrLevel.A2 to 2, CefrLevel.B1 to 3,
        CefrLevel.B2 to 4, CefrLevel.C1 to 5, CefrLevel.C2 to 6)
    private val jlptByCefr = mapOf(CefrLevel.A1 to 5, CefrLevel.A2 to 4, CefrLevel.B1 to 3,
        CefrLevel.B2 to 2, CefrLevel.C1 to 1)

    /** CEFR everywhere internally; Korean thinks in TOPIK, Japanese in JLPT. */
    fun levelLabel(level: CefrLevel, target: String): String {
        val cefr = level.code.uppercase()
        return when (target) {
            "ko" -> topikByCefr[level]?.let { "$cefr · TOPIK $it" } ?: cefr
            "ja" -> jlptByCefr[level]?.let { "$cefr · JLPT N$it" } ?: cefr
            else -> cefr
        }
    }
}

enum class CefrLevel(val code: String) {
    A1("a1"), A2("a2"), B1("b1"), B2("b2"), C1("c1"), C2("c2");

    companion object {
        fun from(raw: String?): CefrLevel =
            entries.firstOrNull { it.code.equals(raw, ignoreCase = true) } ?: B1
    }
}
