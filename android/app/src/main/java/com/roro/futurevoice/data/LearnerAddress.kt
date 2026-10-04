package com.roro.futurevoice.data

import android.content.Context
import com.roro.futurevoice.core.UILanguage

/**
 * How the fluent self ADDRESSES the learner by name — `LearnerAddress.swift`.
 *
 * Not a formatter for displaying a name. This is for lines the future self
 * speaks in the first person ("보람아, 내가 계속하게 도와줄게"), where a bare
 * name reads like a label. Korean is the only language here that inflects:
 * 아 after a final consonant, 야 after a vowel — attached ONLY to a name
 * written in Hangul, and only when the app is in Korean.
 */
object LearnerAddress {
    /** The name ready for a "%s, …" line, or null when there is none — callers
     *  fall back to the nameless line rather than printing a stray comma. */
    fun vocative(context: Context, rawName: String?): String? =
        // No app language picked means the app follows the device (iOS
        // `UILanguage.chromeLanguage` defaults to it), so a Korean phone
        // still gets 보람아 — Android read a missing choice as "not Korean"
        // until 5.15.
        vocative(rawName, UILanguage.current(context) ?: java.util.Locale.getDefault().language)

    /** The rule itself, pure (plan 5.15). [chromeLanguage] is the language
     *  the app's own screens are in. */
    fun vocative(rawName: String?, chromeLanguage: String): String? {
        val name = rawName?.trim().orEmpty()
        if (name.isEmpty()) return null
        if (!chromeLanguage.startsWith("ko")) return name
        val last = name.last().code
        if (last !in 0xAC00..0xD7A3) return name
        // Hangul syllable block: the final-consonant index is the remainder
        // mod 28, and 0 means the syllable ends on a vowel.
        val endsOnConsonant = (last - 0xAC00) % 28 != 0
        return name + if (endsOnConsonant) "아" else "야"
    }
}
