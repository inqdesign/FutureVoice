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
}

enum class CefrLevel(val code: String) {
    A1("a1"), A2("a2"), B1("b1"), B2("b2"), C1("c1"), C2("c2");

    companion object {
        fun from(raw: String?): CefrLevel =
            entries.firstOrNull { it.code.equals(raw, ignoreCase = true) } ?: B1
    }
}
