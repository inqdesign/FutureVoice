package com.roro.futurevoice.data

/**
 * Is a line written in the TARGET language's script? (iOS `TextScript`.)
 * A learner who slipped into Korean for a turn got an English card built on
 * a translation ("Show me the clock once") and a test item on top of it —
 * a card whose target isn't in the target script isn't material.
 */
object TextScript {
    fun isInTargetScript(text: String, language: String): Boolean {
        if (LanguageCatalog.writesSpaces(language)) {
            val words = text.split(Regex("\\s+")).filter { w -> w.any { it.isLetter() } }
            if (words.isEmpty()) return false
            val native = words.count { word ->
                val letters = word.codePoints().toArray().filter { Character.isLetter(it) }
                letters.count { matches(it, language) } * 2 > letters.size
            }
            return native.toDouble() / words.size >= 0.75
        }
        var letters = 0; var matching = 0
        text.codePoints().forEach { cp ->
            if (!Character.isLetter(cp)) return@forEach
            letters++
            if (matches(cp, language)) matching++
        }
        return letters > 0 && matching.toDouble() / letters > 0.5
    }

    private fun matches(v: Int, language: String): Boolean {
        val hangul = v in 0xAC00..0xD7A3 || v in 0x1100..0x11FF || v in 0x3130..0x318F
        val kana = v in 0x3040..0x30FF || v in 0x31F0..0x31FF || v in 0xFF66..0xFF9F
        val han = v in 0x4E00..0x9FFF || v in 0x3400..0x4DBF || v in 0x20000..0x2A6DF
        val latin = v < 0x0250 || v in 0x1E00..0x1EFF
        return when (language.substringBefore('-')) {
            "ko" -> hangul
            "ja" -> kana || han
            "zh" -> han
            else -> latin
        }
    }
}
