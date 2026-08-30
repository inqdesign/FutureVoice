package com.roro.futurevoice.data

import android.content.Context
import java.io.File

/**
 * The multi-language contract (`docs/contracts/data-model.md`): every
 * learning record belongs to (user, lang); identity and assets belong to the
 * user alone. Locally that is one directory per enrolled target language,
 * `filesDir/lang/<code>/` — the same layout iOS keeps under `Documents/`, so
 * a backup exported from either platform files into the other unchanged.
 *
 * Android has no single-language legacy to migrate, so nothing may ever
 * write a learning record to the root.
 */
object LanguageScope {

    private const val PREFS = "futurevoice"
    /** Same key name as iOS's defaults key, for the reader's sake. */
    private const val ACTIVE_KEY = "futurevoice.targetLanguage"

    fun active(context: Context): String =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(ACTIVE_KEY, null) ?: "en"

    fun setActive(context: Context, code: String) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().putString(ACTIVE_KEY, code).apply()
    }

    /** `filesDir/lang/<code>/`, created on demand. */
    fun directory(context: Context, code: String): File =
        File(File(context.filesDir, "lang"), code).apply { mkdirs() }

    fun activeDirectory(context: Context): File = directory(context, active(context))
}
