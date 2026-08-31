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

    /** The chrome language the widget draws in — the APP's, not the phone's. */
    fun chromeLanguage(context: Context): String =
        context.getSharedPreferences("futurevoice", 0)
            .getString("futurevoice.nativeLanguage", null) ?: "en"
}
