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
    ) {
        val total: Int get() = drillReps + shadowReps + wordReps + expressionReps
    }

    enum class Kind { DRILL, SHADOW, WORD, EXPRESSION }

    private val serializer = MapSerializer(String.serializer(), Day.serializer())

    private fun file(c: Context) = File(c.filesDir, "practice-log.json")

    private fun read(c: Context): Map<String, Day> {
        val f = file(c)
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
        val d = days[key] ?: Day()
        days[key] = when (kind) {
            Kind.DRILL -> d.copy(drillReps = d.drillReps + 1,
                drillDone = d.drillDone + if (finished) 1 else 0)
            Kind.SHADOW -> d.copy(shadowReps = d.shadowReps + 1,
                shadowDone = d.shadowDone + if (finished) 1 else 0)
            Kind.WORD -> d.copy(wordReps = d.wordReps + 1,
                wordDone = d.wordDone + if (finished) 1 else 0)
            Kind.EXPRESSION -> d.copy(expressionReps = d.expressionReps + 1,
                expressionDone = d.expressionDone + if (finished) 1 else 0)
        }
        val target = file(c)
        val tmp = File(target.parentFile, target.name + ".tmp")
        tmp.writeText(StoreJson.json.encodeToString(serializer, days))
        if (!tmp.renameTo(target)) { target.delete(); tmp.renameTo(target) }
    }

    fun day(c: Context, at: Long = System.currentTimeMillis()): Day? = read(c)[key(at)]

    /** The last [days] days, oldest first — the activity strip's bars. */
    fun recent(c: Context, days: Int, now: Long = System.currentTimeMillis()): List<Pair<String, Day>> {
        val log = read(c)
        val cal = Calendar.getInstance().apply { timeInMillis = now }
        cal.add(Calendar.DAY_OF_YEAR, -(days - 1))
        return (0 until days).map {
            val k = key(cal.timeInMillis)
            cal.add(Calendar.DAY_OF_YEAR, 1)
            k to (log[k] ?: Day())
        }
    }

    private val keyFormat = SimpleDateFormat("yyyy-MM-dd", Locale.US)

    private fun key(at: Long): String = keyFormat.format(Date(at))
}
