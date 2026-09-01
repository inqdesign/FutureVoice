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

    // MARK: - Enrollment

    /** Same key name as iOS's defaults key. */
    private const val ENROLLED_KEY = "futurevoice.enrolledLanguages"

    /**
     * Enrolled target languages, in enrollment order. NEVER empty — an
     * install that predates this reads as enrolled in whatever it is
     * currently learning, so the picker can't come up blank on an account
     * that has been using the app for months.
     */
    fun enrolled(context: Context): List<String> {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val stored = prefs.getString(ENROLLED_KEY, null)
            ?.split(",")?.map { it.trim() }?.filter { it.isNotEmpty() }
        return stored?.takeIf { it.isNotEmpty() } ?: listOf(active(context))
    }

    /** Idempotent: enrolling a language already on the list changes nothing. */
    fun enroll(context: Context, code: String) {
        val list = enrolled(context)
        if (code in list) return
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().putString(ENROLLED_KEY, (list + code).joinToString(",")).apply()
    }

    /**
     * The learner's level IN a given language. Per language because it has to
     * be: someone at C1 in English starting German is not a C1 German
     * speaker, and one shared level would pitch every scene and every reply
     * at the wrong band the moment they added a second one.
     */
    fun level(context: Context, code: String, fallback: String): String =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString("futurevoice.level.$code", null) ?: fallback

    fun setLevel(context: Context, code: String, level: String) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().putString("futurevoice.level.$code", level).apply()
    }
}
