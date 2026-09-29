package com.roro.futurevoice.widget

import android.content.Context
import com.roro.futurevoice.data.StoreJson
import com.roro.futurevoice.data.IsoDateMillisSerializer
import kotlinx.serialization.Serializable
import java.io.File

/**
 * The widget snapshot contract (`StudyWidgetShared.swift`). The APP writes
 * these; the widget only ever READS — it must not touch the stores, so a
 * home-screen redraw can never be blocked on a decode.
 *
 * On iOS this crosses an App Group; on Android the widget runs in the app's
 * own process, so a file in `filesDir` is the same contract with no extra
 * plumbing. Same JSON shape either way.
 */
@Serializable
data class StudyWidgetItem(
    val text: String,
    /** Short trailing caption: CEFR level, or usage count. */
    val note: String = "",
)

@Serializable
data class StudyWidgetSnapshot(
    @Serializable(with = IsoDateMillisSerializer::class)
    val updatedAt: Long = 0L,
    /** Size of the whole collection, not just the window — the badge. */
    val total: Int = 0,
    val items: List<StudyWidgetItem> = emptyList(),
    /** Written only when more than one language is enrolled; else noise. */
    val language: String? = null,
)

/**
 * Where the learner stands TODAY (`StudyProgressSnapshot`) — what the
 * Progress and Streak widgets draw. Every number is computed app-side by the
 * same code the app's own screens use; the widget never recounts.
 */
@Serializable
data class StudyProgressSnapshot(
    @Serializable(with = IsoDateMillisSerializer::class)
    val updatedAt: Long = 0L,
    /** Metered talk seconds today, every language — the home ring's number. */
    val todaySeconds: Int = 0,
    val goalMinutes: Int = 10,
    /** The Home streak ([com.roro.futurevoice.data.TalkTimeLog.streakDays]). */
    val streakDays: Int = 0,
    val dueCount: Int = 0,
    val studyingWords: Int = 0,
    val studyingExpressions: Int = 0,
    /**
     * Whether today already counts toward the streak — the STREAK's rule
     * (anything studied or used today), decided by the same predicate that
     * counts [streakDays]. Never `todaySeconds >= goal`: judging the face by
     * the goal put "about to lose it" on a streak already extended.
     */
    val metToday: Boolean = false,
)

/** The one in-progress book the Continue widget points at (`StudyBookSnapshot`). */
@Serializable
data class StudyBookSnapshot(
    @Serializable(with = IsoDateMillisSerializer::class)
    val updatedAt: Long = 0L,
    val hasBook: Boolean = false,
    /** "talk" | "watch" */
    val kind: String = "talk",
    val id: String = "",
    val title: String = "",
    /** Already in the APP language — the widget can only draw data. */
    val subtitle: String = "",
    val mastered: Int = 0,
    val total: Int = 0,
) {
    /** The book's page, or the Practice shelf when there is no book. */
    val deepLink: String get() =
        if (!hasBook || id.isEmpty()) "futurevoice://practice"
        else "futurevoice://book?type=$kind&id=$id"
}

/** The two independent widgets — everything that differs hangs off here. */
enum class StudyWidgetSection(val key: String) {
    WORDS("words"), EXPRESSIONS("expressions");

    val filename: String get() = "widget_$key.json"
    /** Deep link the tap opens — handled in RootTabView on iOS, MainActivity here. */
    val deepLink: String get() = if (this == WORDS) "futurevoice://vocab" else "futurevoice://expressions"
    /** Words carry a CEFR note; expressions carry a use count only when > 1. */
    val showsNote: Boolean get() = this == WORDS
}

object StudyWidgetSnapshotStore {
    fun file(context: Context, section: StudyWidgetSection): File =
        File(context.filesDir, section.filename)

    fun load(context: Context, section: StudyWidgetSection): StudyWidgetSnapshot {
        val f = file(context, section)
        if (!f.exists()) return StudyWidgetSnapshot()
        return runCatching {
            StoreJson.json.decodeFromString(StudyWidgetSnapshot.serializer(), f.readText())
        }.getOrElse { StudyWidgetSnapshot() }
    }

    fun save(context: Context, snapshot: StudyWidgetSnapshot, section: StudyWidgetSection) {
        val target = file(context, section)
        val tmp = File(context.filesDir, "${section.filename}.tmp")
        tmp.writeText(StoreJson.json.encodeToString(StudyWidgetSnapshot.serializer(), snapshot))
        if (!tmp.renameTo(target)) { target.delete(); tmp.renameTo(target) }
    }

    private const val PROGRESS_FILE = "widget_progress.json"
    private const val BOOK_FILE = "widget_book.json"

    fun loadProgress(context: Context): StudyProgressSnapshot =
        read(context, PROGRESS_FILE)?.let {
            runCatching { StoreJson.json.decodeFromString(StudyProgressSnapshot.serializer(), it) }.getOrNull()
        } ?: StudyProgressSnapshot()

    fun saveProgress(context: Context, snapshot: StudyProgressSnapshot) =
        write(context, PROGRESS_FILE,
            StoreJson.json.encodeToString(StudyProgressSnapshot.serializer(), snapshot))

    fun loadBook(context: Context): StudyBookSnapshot =
        read(context, BOOK_FILE)?.let {
            runCatching { StoreJson.json.decodeFromString(StudyBookSnapshot.serializer(), it) }.getOrNull()
        } ?: StudyBookSnapshot()

    fun saveBook(context: Context, snapshot: StudyBookSnapshot) =
        write(context, BOOK_FILE, StoreJson.json.encodeToString(StudyBookSnapshot.serializer(), snapshot))

    private fun read(context: Context, name: String): String? =
        File(context.filesDir, name).takeIf { it.exists() }?.let { runCatching { it.readText() }.getOrNull() }

    private fun write(context: Context, name: String, text: String) {
        val target = File(context.filesDir, name)
        val tmp = File(context.filesDir, "$name.tmp")
        tmp.writeText(text)
        if (!tmp.renameTo(target)) { target.delete(); tmp.renameTo(target) }
    }

    /**
     * The Futureself palette the widgets wear. iOS mirrors it into the App
     * Group because the extension can't read the app's defaults; here the
     * widget runs in the app's own process, so it reads the same key the
     * app's picker writes.
     */
    fun themeIndex(context: Context): Int =
        context.getSharedPreferences("futurevoice", 0)
            .getInt(com.roro.futurevoice.ui.brand.FutureselfTheme.PREF_KEY, 0)

    /** The chrome language the widget draws in — the APP's, not the phone's. */
    fun chromeLanguage(context: Context): String =
        context.getSharedPreferences("futurevoice", 0)
            .getString("futurevoice.nativeLanguage", null) ?: "en"

    /**
     * A widget string in the APP's language.
     *
     * Glance draws outside the app's composition, so `stringResource` would
     * resolve against the SYSTEM locale — a learner whose phone is English
     * and whose app is Korean would get an English widget beside a Korean
     * app. The resources are read through a context configured for the app
     * language instead.
     */
    fun chrome(context: Context, resId: Int): String =
        chromeContext(context).getString(resId)

    /** [chrome] for a format string (`with %s`). */
    fun chrome(context: Context, resId: Int, vararg args: Any): String =
        chromeContext(context).getString(resId, *args)

    private fun chromeContext(context: Context): Context {
        val locale = java.util.Locale.forLanguageTag(chromeLanguage(context))
        val config = android.content.res.Configuration(context.resources.configuration)
        config.setLocale(locale)
        return context.createConfigurationContext(config)
    }
}
