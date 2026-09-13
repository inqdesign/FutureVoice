package com.roro.futurevoice.core

import android.content.Context
import android.content.res.Configuration
import android.os.LocaleList
import java.util.Locale

/**
 * The language the app's OWN screens are written in: the one the learner
 * named as theirs (Me → App language), not the phone's and not the one they
 * are learning.
 *
 * iOS `UILanguage`. Chrome used to follow the TARGET language there, on the
 * theory that a tab bar seen a hundred times a day is free vocabulary at no
 * cost. It only holds if the words are incidental, and they aren't: a Korean
 * learning German got a German app, and even the English case put every
 * control of the product in a language the learner is by definition still
 * learning. Exposure belongs in MATERIAL, which is where it stays.
 *
 * Android resolves resources from the CONTEXT, so the choice is applied by
 * wrapping the base context of the activity and of the application — the
 * latter because notifications are built from the app context, and a
 * reminder in the wrong language is the app forgetting who it is talking to.
 */
object UILanguage {
    /** The columns that actually exist in the catalogs. Everything else falls
     *  back to English rather than showing half a translated app. */
    val translated = listOf("en", "ko", "ja", "zh-Hant")

    /** A stored native code as a UI language: a bare "zh" means Traditional
     *  here (Simplified is a separate translation that doesn't ship). */
    fun normalize(code: String?): String? = when (code) {
        null -> null
        "zh", "zh-Hans", "zh-Hant" -> "zh-Hant"
        else -> code.takeIf { it in translated }
    }

    fun current(context: Context): String? =
        normalize(context.getSharedPreferences("futurevoice", 0).getString("futurevoice.nativeLanguage", null))

    private fun locale(tag: String): Locale = when (tag) {
        // A resource folder carries a REGION, never a script — values-zh-rTW.
        "zh-Hant" -> Locale.forLanguageTag("zh-TW")
        else -> Locale.forLanguageTag(tag)
    }

    /** The same context, resolving strings in the learner's language. */
    fun wrap(base: Context): Context {
        val tag = current(base) ?: return base
        val l = locale(tag)
        Locale.setDefault(l)
        val config = Configuration(base.resources.configuration)
        config.setLocale(l)
        config.setLocales(LocaleList(l))
        return base.createConfigurationContext(config)
    }
}
