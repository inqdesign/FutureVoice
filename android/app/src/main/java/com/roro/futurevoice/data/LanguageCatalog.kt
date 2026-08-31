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
        "th" to "Thai", "id" to "Indonesian", "hi" to "Hindi", "ar" to "Arabic",
        "tr" to "Turkish", "ru" to "Russian", "pl" to "Polish", "nl" to "Dutch",
    )

    fun language(code: String): Language =
        targets.firstOrNull { it.code == code } ?: targets.first()

    fun sttLocale(code: String): String = language(code).sttLocale

    fun tokenStyle(code: String): TokenStyle = language(code).tokenStyle

    fun englishName(code: String): String =
        englishNames[code] ?: code.uppercase()

    /** Targets offered in setup — everything with a graded word list. */
    val selectableTargets: List<Language>
        get() = targets.filter { it.code in setOf("en", "de", "ko") }

    /**
     * Languages a learner may name as NATIVE (`LanguageCatalog.swift`,
     * region-ordered). Coaching text is GENERATED per language, so the list
     * is wide; UI translation exists only for en/ko today.
     */
    val nativeLanguages: List<String> = listOf(
        "ko", "ja", "zh", "vi", "th", "id", "ms", "fil", "km", "my", "lo", "mn",
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

    fun defaultNative(): String =
        deviceLanguageCodes().firstOrNull { it in nativeLanguages } ?: "en"

    private fun deviceLanguageCodes(): List<String> {
        val locales = android.os.LocaleList.getDefault()
        return (0 until locales.size()).map { locales.get(it).language }
    }

    /** Language name in its own language — "Deutsch", "한국어". */
    fun endonym(code: String): String =
        java.util.Locale(code).getDisplayLanguage(java.util.Locale(code))
            .replaceFirstChar { it.uppercase() }.ifEmpty { code.uppercase() }

    /** Language name in the LEARNER's language — "영어" for a Korean. */
    fun ownName(code: String, native: String): String =
        java.util.Locale(code).getDisplayLanguage(java.util.Locale(native))
            .replaceFirstChar { it.uppercase() }.ifEmpty { englishName(code) }

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
