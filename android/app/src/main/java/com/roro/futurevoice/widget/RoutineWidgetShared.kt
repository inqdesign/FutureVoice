package com.roro.futurevoice.widget

import android.content.Context
import androidx.compose.ui.graphics.Color
import com.roro.futurevoice.data.IsoDateMillisSerializer
import com.roro.futurevoice.data.StoreJson
import kotlinx.serialization.Serializable
import java.io.File
import java.util.Calendar

/**
 * The routine widget's contract (iOS `RoutineWidgetBlock` /
 * `RoutineWidgetSnapshot` in StudyWidgetShared.swift, and the day rules in
 * RoutineWidgetShared.swift, a0836bbe). The APP resolves everything the
 * learner reads (titles, the "now" line, the labels); the widget only draws.
 */
@Serializable
data class RoutineWidgetBlock(
    val id: String,
    /** `StudyPlan.Kind.raw`, for the tint, the icon and the deep link. */
    val kind: String,
    @Serializable(with = IsoDateMillisSerializer::class)
    val start: Long,
    @Serializable(with = IsoDateMillisSerializer::class)
    val end: Long,
    /** No set time today; [start] is midnight. */
    val anytime: Boolean = false,
    /** "Review 20 items" */
    val title: String,
    /** "Ready to review" — shown while its time is on. */
    val nowLine: String,
    val done: Boolean = false,
    /** How far along, 0…1 — Activity's ring. */
    val progress: Double? = null,
) {
    /** Same deep link for every surface that means "do this block". */
    val deepLink: String get() = "futurevoice://routine?kind=$kind"

    /** Its time is on: started, not finished, not done. An anytime block is
     *  never "now" — it has no moment to arrive at. */
    fun isNow(at: Long): Boolean = !done && !anytime && start <= at && at < end
}

@Serializable
data class RoutineWidgetSnapshot(
    @Serializable(with = IsoDateMillisSerializer::class)
    val updatedAt: Long = 0L,
    /** Start of the day [today] belongs to. */
    @Serializable(with = IsoDateMillisSerializer::class)
    val day: Long = 0L,
    val today: List<RoutineWidgetBlock> = emptyList(),
    val tomorrow: List<RoutineWidgetBlock> = emptyList(),
    /** Chrome, resolved app-side for the same reason as the titles. */
    val labels: Map<String, String> = emptyMap(),
) {
    fun label(key: String): String = labels[key] ?: ""

    /** The blocks of the day [at] falls on. Past midnight `tomorrow` becomes
     *  today, so the widget keeps going until the app next writes. */
    fun blocks(at: Long): List<RoutineWidgetBlock> = when {
        sameDay(at, day) -> today
        sameDay(at, addDay(day)) -> tomorrow
        else -> emptyList()
    }

    /** The block whose time is on. */
    fun now(at: Long): RoutineWidgetBlock? = blocks(at).firstOrNull { it.isNow(at) }

    /** The next timed block still to come, else an anytime one not done,
     *  else one whose time passed undone — done any time that day still
     *  counts, so it is still on the day. */
    fun next(at: Long): RoutineWidgetBlock? {
        val b = blocks(at)
        return b.firstOrNull { !it.done && !it.anytime && it.start > at }
            ?: b.firstOrNull { !it.done && it.anytime }
            ?: b.firstOrNull { !it.done }
    }

    /** Tomorrow's first block — what an empty or finished day points at. */
    fun tomorrowFirst(at: Long): RoutineWidgetBlock? = if (sameDay(at, day)) tomorrow.firstOrNull() else null

    /** What a tap on the whole widget opens: the block due or next. */
    fun deepLink(at: Long): String = (now(at) ?: next(at))?.deepLink ?: "futurevoice://routine"

    /** Every moment the face changes from [after] on: each timed block's
     *  start and end, and midnight. iOS hands these to WidgetKit as timeline
     *  entries; here they are the times an alarm redraws the widget. */
    fun edges(after: Long): List<Long> {
        val midnight = addDay(startOfDay(after))
        return ((today + tomorrow).filter { !it.anytime }.flatMap { listOf(it.start, it.end) } + midnight)
            .filter { it > after }.distinct().sorted()
    }

    companion object {
        fun sameDay(a: Long, b: Long): Boolean {
            val ca = Calendar.getInstance().apply { timeInMillis = a }
            val cb = Calendar.getInstance().apply { timeInMillis = b }
            return ca.get(Calendar.YEAR) == cb.get(Calendar.YEAR) &&
                ca.get(Calendar.DAY_OF_YEAR) == cb.get(Calendar.DAY_OF_YEAR)
        }

        fun startOfDay(t: Long): Long = Calendar.getInstance().apply {
            timeInMillis = t
            set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
        }.timeInMillis

        fun addDay(t: Long): Long = Calendar.getInstance().apply {
            timeInMillis = t; add(Calendar.DAY_OF_YEAR, 1)
        }.timeInMillis
    }
}

/** 24-hour, like Activity's day list. */
fun routineClock(t: Long): String {
    val c = Calendar.getInstance().apply { timeInMillis = t }
    return String.format(java.util.Locale.ROOT, "%d:%02d", c.get(Calendar.HOUR_OF_DAY), c.get(Calendar.MINUTE))
}

/** `StudyPlan.Kind.color()` (RoutineCommon.kt). Keep in step. */
fun routineTint(kind: String): Color = when (kind) {
    "talk" -> Color(0xFF007AFF)
    "sayItAgain" -> Color(0xFF30B0C7)
    "review" -> Color(0xFF34C759)
    "words", "speech" -> Color(0xFFAF52DE)
    "expressions" -> Color(0xFFFF2D55)
    "shadow" -> Color(0xFFFFCC00)
    "test" -> Color(0xFFFF9500)
    "listen" -> Color(0xFF32ADE6)
    else -> Color(0xFF8E8E93)
}

/** The routine snapshot, its own file beside the others. */
object RoutineWidgetStore {
    private const val FILE = "widget_routine.json"

    fun load(context: Context): RoutineWidgetSnapshot =
        File(context.filesDir, FILE).takeIf { it.exists() }?.let { f ->
            runCatching { StoreJson.json.decodeFromString(RoutineWidgetSnapshot.serializer(), f.readText()) }.getOrNull()
        } ?: RoutineWidgetSnapshot()

    fun save(context: Context, snapshot: RoutineWidgetSnapshot) {
        val target = File(context.filesDir, FILE)
        val tmp = File(context.filesDir, "$FILE.tmp")
        tmp.writeText(StoreJson.json.encodeToString(RoutineWidgetSnapshot.serializer(), snapshot))
        if (!tmp.renameTo(target)) { target.delete(); tmp.renameTo(target) }
    }
}
