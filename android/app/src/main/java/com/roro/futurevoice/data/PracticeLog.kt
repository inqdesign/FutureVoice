package com.roro.futurevoice.data

import android.content.Context
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.MapSerializer
import kotlinx.serialization.builtins.serializer
import java.io.File
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

/**
 * Day-bucketed practice effort log (`files/practice-log.json`, same shape and
 * filename as iOS `PracticeLog`).
 *
 * The stores only keep LATEST state (a card's last review date, a line's
 * attempts) — fine for scheduling, useless for showing effort over time. This
 * log records every rep as it happens so Progress can show an honest "you
 * showed up" strip. Counts only; no content, and NOT language-scoped: showing
 * up is showing up, whichever language it was in.
 *
 * Two files, as on iOS (2026-11-20): the per-day file syncs by the bigger
 * device's count per field, so on a day practised on a Mac and this phone the
 * smaller device's reps dropped out. The per-DEVICE file keys each day by
 * `day|device`: one writer per key, so the max merge is exact and a day is
 * the sum of its devices. The per-day file is still written for builds that
 * don't know the device file; each field reads the larger of the two.
 */
object PracticeLog {

    /**
     * Two numbers per kind, because they answer two different questions.
     *
     * `*Reps` = EFFORT: every time the learner handled the item at all —
     * bookmarking a word, pushing a card to tomorrow. That's what the activity
     * chart is about ("you showed up").
     *
     * `*Done` = FINISHED: the item was actually retired — "Got it" on a card,
     * a recorded shadow take. That's what a daily goal is about. The two were
     * one number on iOS once, so a day could be ticked complete by postponing
     * ten cards.
     */
    @Serializable
    data class Day(
        val drillReps: Int = 0,
        val shadowReps: Int = 0,
        val wordReps: Int = 0,
        val expressionReps: Int = 0,
        val drillDone: Int = 0,
        val shadowDone: Int = 0,
        val wordDone: Int = 0,
        val expressionDone: Int = 0,
        /**
         * A Watch scene the learner sat through — logged once, when its first
         * line is heard. Out of [total] and out of the daily goal (the goal
         * counts work the learner DID, and a scene plays itself), but it is
         * effort, so it keeps a streak alive. Zero is not encoded, so a day
         * written before this existed keeps its fingerprint.
         */
        val sceneReps: Int = 0,
    ) {
        val total: Int get() = drillReps + shadowReps + wordReps + expressionReps

        /** Anything at all happened today — what the streak asks. */
        val didSomething: Boolean get() = total > 0 || sceneReps > 0
    }

    enum class Kind { DRILL, SHADOW, WORD, EXPRESSION, SCENE }

    private val serializer = MapSerializer(String.serializer(), Day.serializer())

    /**
     * Every field written, zeros included: iOS writes the whole day, and the
     * sync reads this file as the record. With zeros dropped, every rep here
     * rewrote every past day into a shorter shape, so all of them looked
     * edited and went back up to Drive on the next pass; and iOS reads a
     * missing `shadowDone` as `shadowReps`, which inflated finished shadowing
     * on the other device.
     */
    private val fileJson = kotlinx.serialization.json.Json(StoreJson.json) { encodeDefaults = true }

    const val DEVICE_FILE = "practice-log-devices.json"

    private fun file(c: Context) = File(c.filesDir, "practice-log.json")
    private fun deviceFile(c: Context) = File(c.filesDir, DEVICE_FILE)

    private fun read(c: Context): Map<String, Day> = read(file(c))

    private fun read(f: File): Map<String, Day> {
        if (!f.exists()) return emptyMap()
        return runCatching {
            StoreJson.json.decodeFromString(serializer, f.readText())
        }.getOrElse { emptyMap() }
    }

    /**
     * @param finished the item is done with (mastered / known / actually said
     *   out loud), as opposed to merely handled. Only finished work counts
     *   toward a daily goal.
     */
    @Synchronized
    fun record(c: Context, kind: Kind, finished: Boolean = false, at: Long = System.currentTimeMillis()) {
        val key = key(at)
        val days = read(c).toMutableMap()
        days[key] = adding(days[key] ?: Day(), kind, finished)
        write(file(c), days)
        val devices = read(deviceFile(c)).toMutableMap()
        val dk = key + "|" + AppUsageLog.device(c)
        devices[dk] = adding(devices[dk] ?: Day(), kind, finished)
        write(deviceFile(c), devices)
        // WHEN it happened, for the routine's day view (iOS: the same door).
        ActivityEventLog.record(c, ActivityEventLog.Kind.of(kind), at)
    }

    private fun write(target: File, days: Map<String, Day>) {
        val tmp = File(target.parentFile, target.name + ".tmp")
        tmp.writeText(fileJson.encodeToString(serializer, days))
        if (!tmp.renameTo(target)) { target.delete(); tmp.renameTo(target) }
    }

    fun adding(d: Day, kind: Kind, finished: Boolean): Day {
        val f = if (finished) 1 else 0
        return when (kind) {
            Kind.DRILL -> d.copy(drillReps = d.drillReps + 1, drillDone = d.drillDone + f)
            Kind.SHADOW -> d.copy(shadowReps = d.shadowReps + 1, shadowDone = d.shadowDone + f)
            Kind.WORD -> d.copy(wordReps = d.wordReps + 1, wordDone = d.wordDone + f)
            Kind.SCENE -> d.copy(sceneReps = d.sceneReps + 1)
            Kind.EXPRESSION -> d.copy(expressionReps = d.expressionReps + 1, expressionDone = d.expressionDone + f)
        }
    }

    /** The day as every device recorded it: each field the larger of the
     *  per-day count and the sum over devices (iOS `PracticeLog.combined`). */
    fun combined(legacy: Day?, devices: Map<String, Day>, day: String): Day? {
        val mine = devices.filterKeys { it.startsWith("$day|") }.values
        if (legacy == null && mine.isEmpty()) return null
        val l = legacy ?: Day()
        val s = mine.fold(Day()) { a, b -> Day(a.drillReps + b.drillReps, a.shadowReps + b.shadowReps,
            a.wordReps + b.wordReps, a.expressionReps + b.expressionReps, a.drillDone + b.drillDone,
            a.shadowDone + b.shadowDone, a.wordDone + b.wordDone, a.expressionDone + b.expressionDone,
            a.sceneReps + b.sceneReps) }
        return Day(maxOf(l.drillReps, s.drillReps), maxOf(l.shadowReps, s.shadowReps),
            maxOf(l.wordReps, s.wordReps), maxOf(l.expressionReps, s.expressionReps),
            maxOf(l.drillDone, s.drillDone), maxOf(l.shadowDone, s.shadowDone),
            maxOf(l.wordDone, s.wordDone), maxOf(l.expressionDone, s.expressionDone),
            maxOf(l.sceneReps, s.sceneReps))
    }

    fun day(c: Context, at: Long = System.currentTimeMillis()): Day? {
        val k = key(at)
        return combined(read(c)[k], read(deviceFile(c)), k)
    }

    /** The last [days] days, oldest first — the activity strip's bars. */
    fun recent(c: Context, days: Int, now: Long = System.currentTimeMillis()): List<Pair<String, Day>> {
        val log = read(c)
        val devices = read(deviceFile(c))
        val cal = Calendar.getInstance().apply { timeInMillis = now }
        cal.add(Calendar.DAY_OF_YEAR, -(days - 1))
        return (0 until days).map {
            val k = key(cal.timeInMillis)
            cal.add(Calendar.DAY_OF_YEAR, 1)
            k to (combined(log[k], devices, k) ?: Day())
        }
    }

    private val keyFormat = SimpleDateFormat("yyyy-MM-dd", Locale.US)

    private fun key(at: Long): String = keyFormat.format(Date(at))
}
