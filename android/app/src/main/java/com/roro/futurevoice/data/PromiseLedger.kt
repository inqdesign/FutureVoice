package com.roro.futurevoice.data

import android.content.Context
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.MapSerializer
import kotlinx.serialization.builtins.serializer
import java.io.File
import java.util.TimeZone

/**
 * What each day of a PROMISE looked like: how many blocks were planned and
 * how many were done (iOS `PromiseLedger`). Kept per day and FROZEN once the
 * day is over, because a day is judged by the plan it had — raise the bar on
 * Thursday and Monday stays kept. Today's entry is provisional and rewritten
 * as the day moves. Device-local (`files/promise_days.json`).
 */
object PromiseLedger {

    @Serializable
    data class Entry(
        val planned: Int,
        val done: Int,
        /** False while the day is still running; judged again once it is over. */
        val settled: Boolean = true,
    ) {
        /** Nothing was planned that day: a rest day. */
        val isRest: Boolean get() = planned == 0
        val kept: Boolean get() = planned > 0 && done >= planned
    }

    private val serializer = MapSerializer(String.serializer(), Entry.serializer())
    private var cache: Map<String, Entry>? = null

    private fun file(c: Context) = File(c.filesDir, "promise_days.json")

    @Synchronized
    private fun all(c: Context): Map<String, Entry> = cache ?: runCatching {
        file(c).takeIf { it.exists() }?.readText()?.let { StoreJson.json.decodeFromString(serializer, it) }
    }.getOrNull().orEmpty().also { cache = it }

    fun entry(c: Context, day: Long): Entry? = all(c)[StudyPlan.dayKey(day)]

    @Synchronized
    fun set(c: Context, day: Long, entry: Entry) {
        val next = all(c) + (StudyPlan.dayKey(day) to entry)
        cache = next
        runCatching {
            val target = file(c)
            val tmp = File(target.parentFile, target.name + ".tmp")
            tmp.writeText(StoreJson.json.encodeToString(serializer, next))
            if (!tmp.renameTo(target)) { target.delete(); tmp.renameTo(target) }
        }
    }

    /** Capture seeding only. */
    @Synchronized
    fun replaceAll(c: Context, entries: Map<String, Entry>) {
        cache = entries
        runCatching { file(c).writeText(StoreJson.json.encodeToString(serializer, entries)) }
    }
}

/** Judges promise days from the stores and writes them into the ledger. */
object PromiseJudge {
    /** How far back an unsettled stretch is filled in — the talk meter keeps 45. */
    const val MAX_BACKFILL_DAYS = 45

    /** Planned and done for one day, by the plan as it stands now. */
    fun result(c: Context, day: Long, plan: StudyPlan, testDays: Set<String>): PromiseLedger.Entry {
        val start = StudyPlan.startOfDay(day)
        val occ = plan.occurrences(start, WeeklyTestSettings.schedule(c))
        if (occ.isEmpty()) return PromiseLedger.Entry(0, 0, true)
        val end = StudyPlan.addDays(start, 1)
        val totals = PlannerDay.totals(
            talkSeconds = TalkTimeLog.secondsToday(c, start),
            log = PracticeLog.day(c, start),
            events = ActivityEventLog.events(c, start, end),
            testFinished = StudyPlan.dayKey(start) in testDays)
        return PromiseLedger.Entry(occ.size, PlannerDay.done(occ, totals).size, true)
    }

    /** Days a weekly test was finished, in the active language. */
    suspend fun testDays(c: Context): Set<String> = runCatching {
        WeeklyTestStore.shared(c).load(LanguageScope.active(c)).mapNotNull { it.finishedAt }
            .map { StudyPlan.dayKey(it) }.toSet()
    }.getOrDefault(emptySet())

    /**
     * Settle every promise day not yet frozen (up to yesterday) and rewrite
     * today's provisional entry. Cheap when nothing is pending: one entry.
     */
    suspend fun refresh(c: Context, now: Long = System.currentTimeMillis()) {
        val plan = StudyPlanStore.current(c)
        val since = plan.streakSince ?: return
        val tests = testDays(c)
        val today = StudyPlan.startOfDay(now)
        var day = maxOf(StudyPlan.startOfDay(since), StudyPlan.addDays(today, -MAX_BACKFILL_DAYS))
        while (day < today) {
            if (PromiseLedger.entry(c, day)?.settled != true) {
                PromiseLedger.set(c, day, result(c, day, plan, tests))
            }
            day = StudyPlan.addDays(day, 1)
        }
        PromiseLedger.set(c, today, result(c, today, plan, tests).copy(settled = false))
    }
}

/**
 * How one day stands for the Home streak (iOS `PracticeStats.standing`).
 * The RULE is the learner's own: with no promise made, a day counts when they
 * studied at all; from the day the routine became a promise
 * (`StudyPlan.streakSince`), a day counts only when everything planned for it
 * was done, and a day with nothing planned is a rest day. Each promise day is
 * judged by the plan it had ([PromiseLedger]), so raising the bar never
 * rewrites the past.
 */
object PromiseStreak {
    enum class Standing { KEPT, MISSED, REST }

    fun standing(c: Context, day: Long, studied: (Long) -> Boolean): Standing {
        val d = StudyPlan.startOfDay(day)
        PromiseLedger.entry(c, d)?.let {
            return if (it.isRest) Standing.REST else if (it.kept) Standing.KEPT else Standing.MISSED
        }
        val since = StudyPlanStore.current(c).streakSince
        // A promise day not judged yet (nothing has refreshed since): not
        // counted, not broken.
        if (since != null && d >= StudyPlan.startOfDay(since)) return Standing.REST
        return if (studied(d)) Standing.KEPT else Standing.MISSED
    }

    fun isPromise(c: Context): Boolean = StudyPlanStore.current(c).streakSince != null

    /** Furthest back the walk goes — rest days have no end of their own. */
    const val MAX_WALK_DAYS = 1100

    /**
     * The walk itself, pure: today counts only once it is kept (a day is
     * alive until it is over), rest days are stepped over, the first missed
     * day ends it. [floor] bounds the walk.
     */
    fun streak(now: Long, floor: Long?, zone: TimeZone = TimeZone.getDefault(),
               standing: (Long) -> Standing): Int {
        var cursor = StudyPlan.startOfDay(now, zone)
        if (standing(cursor) != Standing.KEPT) cursor = StudyPlan.addDays(cursor, -1, zone)
        val stop = floor?.let { StudyPlan.startOfDay(it, zone) }
            ?: StudyPlan.addDays(cursor, -MAX_WALK_DAYS, zone)
        var count = 0
        while (cursor >= stop) {
            when (standing(cursor)) {
                Standing.KEPT -> count += 1
                Standing.REST -> Unit
                Standing.MISSED -> return count
            }
            cursor = StudyPlan.addDays(cursor, -1, zone)
        }
        return count
    }
}
