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
        /**
         * When the day was first seen with everything done (epoch ms). A kept
         * day stays kept: adding a block after finishing the day's plan
         * raises the bar for the days ahead, never takes back the one
         * already kept (iOS 2026-10-07 — a 5-minute talk added at night
         * turned a finished day grey). Optional, so older entries decode.
         */
        val keptAt: Long? = null,
        /**
         * Blocks with ANY progress that day. A day is kept when every block
         * was at least started (iOS 2026-10-11, founder: a whole day of study
         * broke the streak because one word block ended at 9 of 10). [done]
         * still counts finished blocks. Null on older entries; reads as [done].
         */
        val touched: Int? = null,
        /**
         * The keep rule the entry was judged by; null = finish-every-block,
         * 2 = every block started, 3 = the same without the weekly test.
         */
        val rule: Int? = null,
    ) {
        /** Nothing was planned that day: a rest day. */
        val isRest: Boolean get() = planned == 0 && keptAt == null
        val kept: Boolean get() = keptAt != null || (planned > 0 && (touched ?: done) >= planned)
    }

    /**
     * The rule [PromiseJudge] writes today: every block the LEARNER placed
     * was started. The weekly test is not one of them (2026-10-13).
     */
    const val CURRENT_RULE = 3

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

    /**
     * Planned and done for one day, by the plan as it stands now.
     *
     * The weekly test is not part of the promise (2026-10-13): the app puts
     * it there, not the learner, and it is "this week's" until the next
     * opening, so taking Saturday's test on Sunday cost a streak over a block
     * nobody placed. Only blocks from the plan itself are judged.
     */
    fun result(c: Context, day: Long, plan: StudyPlan): PromiseLedger.Entry {
        val start = StudyPlan.startOfDay(day)
        val occ = plan.occurrences(start)
        if (occ.isEmpty()) return PromiseLedger.Entry(0, 0, true)
        val end = StudyPlan.addDays(start, 1)
        val totals = PlannerDay.totals(
            talkSeconds = TalkTimeLog.secondsToday(c, start),
            log = PracticeLog.day(c, start),
            events = ActivityEventLog.events(c, start, end),
            testFinished = false)
        val progress = PlannerDay.progress(occ, totals).values
        return PromiseLedger.Entry(occ.size, progress.count { it >= 1.0 }, true,
            touched = progress.count { it > 0.0 }, rule = PromiseLedger.CURRENT_RULE)
    }

    /**
     * A day settled under an older rule, judged again by today's. Only ever
     * UPGRADES, and only when the plan still gives the day the blocks it had,
     * less [exempt] (that day's weekly test, for entries before rule 3) —
     * otherwise the old verdict stands.
     */
    fun rejudged(old: PromiseLedger.Entry, fresh: PromiseLedger.Entry, now: Long,
                 exempt: Int = 0): PromiseLedger.Entry {
        val out = old.copy(rule = PromiseLedger.CURRENT_RULE)
        return if (!old.kept && old.planned > 0 && fresh.planned + exempt == old.planned && fresh.kept)
            out.copy(touched = fresh.touched, keptAt = now) else out
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
    suspend fun refresh(c: Context, now: Long = System.currentTimeMillis(),
                        plan: StudyPlan = StudyPlanStore.current(c)) {
        val since = plan.streakSince ?: return
        val schedule = WeeklyTestSettings.schedule(c)
        val today = StudyPlan.startOfDay(now)
        var day = maxOf(StudyPlan.startOfDay(since), StudyPlan.addDays(today, -MAX_BACKFILL_DAYS))
        while (day < today) {
            val old = PromiseLedger.entry(c, day)
            if (old?.settled != true) {
                PromiseLedger.set(c, day, carryingKept(result(c, day, plan), old, now))
            } else if ((old.rule ?: 1) < PromiseLedger.CURRENT_RULE) {
                val exempt = plan.occurrences(day, schedule).count { it.kind == StudyPlan.Kind.TEST }
                PromiseLedger.set(c, day, rejudged(old, result(c, day, plan), now, exempt))
            }
            day = StudyPlan.addDays(day, 1)
        }
        PromiseLedger.set(c, today, carryingKept(result(c, today, plan),
            PromiseLedger.entry(c, today), now).copy(settled = false))
    }

    /** A day judged again keeps the moment it was first kept. */
    fun carryingKept(new: PromiseLedger.Entry, old: PromiseLedger.Entry?, now: Long): PromiseLedger.Entry =
        when {
            old?.keptAt != null -> new.copy(keptAt = old.keptAt)
            old?.kept == true || new.kept -> new.copy(keptAt = now)
            else -> new
        }
}

/**
 * How one day stands for the Home streak (iOS `PracticeStats.standing`).
 * The RULE is the learner's own: with no promise made, a day counts when they
 * studied at all; from the day the routine became a promise
 * (`StudyPlan.streakSince`), a day counts only when every block planned for
 * it was at least started, and a day with nothing planned is a rest day. Each promise day is
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
