package com.roro.futurevoice.data

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.util.Calendar
import java.util.TimeZone
import java.util.UUID

/**
 * The learner's study timetable — "나의 루틴" (iOS `StudyPlan`, 1.1.4 (71)).
 * What they mean to do, on which weekdays, at what time. It is shown on the
 * routine page laid over what actually happened, and it DRIVES the daily
 * call — a talk block with a set time is a call time.
 *
 * What is stored is a weekly TEMPLATE plus two kinds of per-date edits: a
 * rest day (nothing planned, nothing rings) and an exception (that date's
 * blocks replaced). The weekly test is not stored but derived from its own
 * settings ([WeeklyTestSettings]), so there is never a second copy to drift.
 * Review and "say it again" are ordinary blocks, placed like any other.
 *
 * Device-local, like the daily call it schedules (`files/study_plan.json`).
 * Pure: every function takes the time zone it reads days in, so the tests
 * pin one.
 */
@Serializable
data class StudyPlan(
    val blocks: List<Block> = emptyList(),
    /** 2 = counts (only a talk is measured in minutes) and the onboarding
     *  promise. iOS converts older plans on load; Android never had them. */
    val unitsVersion: Int? = 2,
    /** `yyyy-MM-dd` days with nothing planned and nothing ringing. */
    val restDays: Set<String> = emptySet(),
    /**
     * Weekdays the routine rests every week (Gregorian 1 = Sunday … 7 =
     * Saturday). The week is ONE plan that repeats, so rest is set by
     * weekday, not per date.
     */
    val offWeekdays: Set<Int>? = null,
    /**
     * The day (local midnight, epoch millis) the routine became the
     * learner's PROMISE. From then the streak counts a day only when every
     * block planned for it was done; a day with nothing planned is a rest day
     * that neither counts nor breaks it. null = the plain "studied today" rule.
     */
    val streakSince: Long? = null,
    /** `yyyy-MM-dd` → that date's own blocks, replacing the template's. */
    val exceptions: Map<String, List<Block>> = emptyMap(),
) {
    @Serializable
    enum class Kind(val raw: String) {
        @SerialName("talk") TALK("talk"),
        @SerialName("review") REVIEW("review"),
        @SerialName("sayItAgain") SAY_IT_AGAIN("sayItAgain"),
        // LEGACY kinds: folded into review on every update; nothing places them.
        @SerialName("words") WORDS("words"),
        @SerialName("expressions") EXPRESSIONS("expressions"),
        @SerialName("shadow") SHADOW("shadow"),
        @SerialName("test") TEST("test");

        /** Only a talk is measured in MINUTES (the talk meter). Every other
         *  kind is a COUNT the app actually keeps. */
        val isTimed: Boolean get() = this == TALK

        /** How much a new block of this kind asks for — the daily goals'
         *  own defaults ([GoalStore]). */
        val defaultAmount: Int get() = when (this) {
            TALK -> 10
            WORDS -> 10
            EXPRESSIONS -> 3
            REVIEW -> 20
            SHADOW -> 2
            SAY_IT_AGAIN, TEST -> 1
        }

        /** How tall the block is drawn in the editor, in minutes — a count
         *  has no length, so it gets a fixed one. */
        fun drawnMinutes(amount: Int): Int = if (isTimed) amount else 15

        val isFoldedIntoReview: Boolean get() = this == WORDS || this == EXPRESSIONS || this == SHADOW

        companion object {
            /** Kinds the learner places by hand — whole ACTIONS (iOS
             *  2026-10-03): talk, review, say it again. */
            val placeable = listOf(TALK, REVIEW, SAY_IT_AGAIN)
        }
    }

    @Serializable
    data class Block(
        val id: String = newId(),
        val kind: Kind,
        /** Gregorian weekdays, 1 = Sunday … 7 = Saturday. */
        val weekdays: Set<Int>,
        val hour: Int,
        val minute: Int,
        /** The AMOUNT promised: minutes for a talk, a count otherwise. The
         *  key stays `minutes` so the file reads like iOS's. */
        val minutes: Int,
        /** No set time: "some time today". `hour`/`minute` are ignored. */
        val anytime: Boolean? = null,
        /** A local reminder at the block's time. Talk blocks ignore it —
         *  they ring as the daily call. */
        val remind: Boolean = true,
    ) {
        val amount: Int get() = minutes
        val isAnytime: Boolean get() = anytime == true
        val startMinute: Int get() = hour * 60 + minute
    }

    /** One block placed on one date. */
    data class Occurrence(
        val kind: Kind,
        val start: Long,
        /** The amount promised (minutes for a talk, else a count). */
        val amount: Int,
        val source: Source,
        val remind: Boolean,
        /** No set time today; [start] is midnight. */
        val anytime: Boolean = false,
    ) {
        sealed interface Source {
            data class Template(val id: String) : Source
            data class Exception(val id: String) : Source
            data object Test : Source
        }

        /** How long it is drawn — a talk's own minutes, a fixed slot otherwise. */
        val minutes: Int get() = kind.drawnMinutes(amount)
        val end: Long get() = start + minutes * 60_000L

        val id: String get() = "$start-${kind.raw}-" + when (source) {
            is Source.Template -> "t${source.id}"
            is Source.Exception -> "x${source.id}"
            Source.Test -> "test"
        }

        val blockId: String? get() = when (source) {
            is Source.Template -> source.id
            is Source.Exception -> source.id
            Source.Test -> null
        }

        /** Whether the chance to do it has passed: an anytime block lasts
         *  until the day ends. */
        fun isOver(now: Long = System.currentTimeMillis(), zone: TimeZone = TimeZone.getDefault()): Boolean =
            if (anytime) startOfDay(now, zone) > startOfDay(start, zone) else end < now
    }

    /** What a drag changes: this date only, this weekday every week, or the
     *  block's time on every weekday it runs. */
    enum class Scope { THIS_DAY, EVERY_WEEK, ALL_DAYS }

    // MARK: - A day

    fun isRestDay(day: Long, zone: TimeZone = TimeZone.getDefault()): Boolean =
        dayKey(day, zone) in restDays

    /** The stored blocks for a date: its exception if it has one, else the
     *  template's blocks for that weekday. */
    fun storedBlocks(day: Long, zone: TimeZone = TimeZone.getDefault()): List<Block> {
        exceptions[dayKey(day, zone)]?.let { return it }
        val wd = weekday(day, zone)
        return blocks.filter { wd in it.weekdays }
    }

    /** Everything planned for a date, soonest first. */
    fun occurrences(day: Long, test: WeeklyTestSchedule? = null,
                    zone: TimeZone = TimeZone.getDefault()): List<Occurrence> {
        if (isRestDay(day, zone) || weekday(day, zone) in (offWeekdays ?: emptySet())) return emptyList()
        val isException = exceptions[dayKey(day, zone)] != null
        val out = storedBlocks(day, zone).map { b ->
            val start = if (b.isAnytime) startOfDay(day, zone) else at(day, b.hour, b.minute, zone)
            Occurrence(b.kind, start, b.minutes,
                if (isException) Occurrence.Source.Exception(b.id) else Occurrence.Source.Template(b.id),
                remind = b.remind && !b.isAnytime, anytime = b.isAnytime)
        }.toMutableList()
        if (test != null && weekday(day, zone) == test.weekday) {
            out += Occurrence(Kind.TEST, at(day, test.hour, test.minute, zone), 1,
                Occurrence.Source.Test, remind = false)
        }
        return out.sortedBy { it.start }
    }

    // MARK: - The call

    /**
     * Every daily-call ring to arm, soonest first: the rest of today's timed
     * talk blocks, else the first talk block of the next day that has one —
     * the shape `fireDates` always had, with weekdays, rest days and
     * exceptions honoured. Empty when nothing is planned in two weeks.
     */
    fun callDates(after: Long, zone: TimeZone = TimeZone.getDefault()): List<Long> {
        val today = startOfDay(after, zone)
        fun talks(day: Long) = occurrences(day, zone = zone)
            .filter { it.kind == Kind.TALK && !it.anytime }.map { it.start }
        val remaining = talks(today).filter { it > after }.distinct().sorted()
        if (remaining.isNotEmpty()) return remaining.take(MAX_CALL_TIMES)
        for (offset in 1..14) {
            talks(addDays(today, offset, zone)).minOrNull()?.let { return listOf(it) }
        }
        return emptyList()
    }

    /** The distinct times of day (minutes past midnight) talk blocks ring at,
     *  across the template and every exception — what the call mirrors. */
    val callTimes: List<Int>
        get() = (blocks + exceptions.values.flatten())
            .filter { it.kind == Kind.TALK && !it.isAnytime }
            .map { it.startMinute }.distinct().sorted()

    /** The weekdays a call time rings on, rest weekdays left out. */
    fun callWeekdays(minuteOfDay: Int): Set<Int> =
        blocks.filter { it.kind == Kind.TALK && !it.isAnytime && it.startMinute == minuteOfDay }
            .flatMap { it.weekdays }.toSet() - (offWeekdays ?: emptySet())

    /** Whether any talk block has a set time — only then does the routine
     *  decide when the daily call rings. */
    val hasTimedTalk: Boolean
        get() = (blocks + exceptions.values.flatten()).any { it.kind == Kind.TALK && !it.isAnytime }

    /** Whether the plan stays within what the call can ring. */
    val isCallable: Boolean get() = callTimes.size <= MAX_CALL_TIMES

    /** Any review block planned — then the review reminder rings there only. */
    val hasReviewBlocks: Boolean get() = blocks.any { it.kind == Kind.REVIEW }

    // MARK: - Review slots

    /** The review slots from [now] on, across [days] days, soonest first. */
    fun reviewSlots(now: Long, days: Int = 14, zone: TimeZone = TimeZone.getDefault()): List<Long> {
        val today = startOfDay(now, zone)
        return (0 until days).flatMap { off ->
            occurrences(addDays(today, off, zone), zone = zone)
                .filter { it.kind == Kind.REVIEW && !it.anytime && it.start > now }.map { it.start }
        }.sorted()
    }

    // MARK: - Editing

    /**
     * Move a stored block. [day] is the date it was dragged on; [newStart]
     * the new start (a drag can cross into another weekday). Null when the
     * result would ring at more call times than the call can.
     */
    fun moving(blockId: String, day: Long, newStart: Long, scope: Scope,
               zone: TimeZone = TimeZone.getDefault()): StudyPlan? {
        val c = cal(newStart, zone)
        val hour = c.get(Calendar.HOUR_OF_DAY)
        val minute = c.get(Calendar.MINUTE)
        val fromKey = dayKey(day, zone)
        val toDay = startOfDay(newStart, zone)
        val toKey = dayKey(toDay, zone)
        val fromWeekday = weekday(day, zone)
        val toWeekday = weekday(toDay, zone)
        var plan = this
        when (scope) {
            Scope.EVERY_WEEK, Scope.ALL_DAYS -> {
                val idx = blocks.indexOfFirst { it.id == blockId }
                // An exception block has no weekly self; "every week" from it
                // means the same move, just this once.
                if (idx < 0) return moving(blockId, day, newStart, Scope.THIS_DAY, zone)
                val block = blocks[idx]
                val list = blocks.toMutableList()
                if (scope == Scope.ALL_DAYS && fromWeekday == toWeekday) {
                    list[idx] = block.copy(hour = hour, minute = minute)
                } else if (block.weekdays.size == 1) {
                    list[idx] = block.copy(weekdays = setOf(toWeekday), hour = hour, minute = minute)
                } else {
                    // The block also runs on other days: split this weekday off.
                    list[idx] = block.copy(weekdays = block.weekdays - fromWeekday)
                    list += block.copy(id = newId(), weekdays = setOf(toWeekday), hour = hour, minute = minute)
                }
                // A template move overrides any one-off edit of the same day.
                plan = copy(blocks = list, exceptions = exceptions - fromKey).mergingTwins()
            }
            Scope.THIS_DAY -> {
                val fromBlocks = storedBlocks(day, zone).toMutableList()
                val idx = fromBlocks.indexOfFirst { it.id == blockId }
                if (idx < 0) return null
                val block = fromBlocks.removeAt(idx).copy(hour = hour, minute = minute)
                plan = if (fromKey == toKey) {
                    copy(exceptions = exceptions + (fromKey to (fromBlocks + block)))
                } else {
                    val withFrom = copy(exceptions = exceptions + (fromKey to fromBlocks))
                    val toBlocks = withFrom.storedBlocks(toDay, zone) + block.copy(id = newId())
                    withFrom.copy(exceptions = withFrom.exceptions + (toKey to toBlocks))
                }
            }
        }
        return plan.takeIf { it.isCallable }
    }

    /** After one weekday of a block was dragged to a new time, take the rest
     *  of its weekdays there too. The halves become one block again. */
    fun following(blockId: String, toHour: Int, minute: Int): StudyPlan? {
        val idx = blocks.indexOfFirst { it.id == blockId }
        if (idx < 0) return null
        val list = blocks.toMutableList()
        list[idx] = list[idx].copy(hour = toHour, minute = minute)
        return copy(blocks = list).mergingTwins().takeIf { it.isCallable }
    }

    /** Two template blocks of the same kind, time and length are one block
     *  on more weekdays. */
    fun mergingTwins(): StudyPlan {
        val merged = mutableListOf<Block>()
        for (b in blocks) {
            val i = merged.indexOfFirst {
                it.kind == b.kind && it.hour == b.hour && it.minute == b.minute &&
                    it.minutes == b.minutes && it.remind == b.remind && it.isAnytime == b.isAnytime
            }
            if (i >= 0) merged[i] = merged[i].copy(weekdays = merged[i].weekdays + b.weekdays)
            else merged += b
        }
        return copy(blocks = merged.filter { it.weekdays.isNotEmpty() })
    }

    /** Forget exceptions and rest days already in the past. */
    fun prunedBefore(now: Long, zone: TimeZone = TimeZone.getDefault()): StudyPlan {
        val todayKey = dayKey(now, zone)
        return copy(exceptions = exceptions.filterKeys { it >= todayKey },
            restDays = restDays.filter { it >= todayKey }.toSet())
    }

    /**
     * Bring the template's talk blocks in line with a call-time list edited
     * elsewhere (Me → Call, onboarding). A time that stays keeps its
     * weekdays; a new time runs every day; a removed one goes.
     */
    fun adoptingCallTimes(times: List<Int>, defaultMinutes: Int): StudyPlan {
        // An "any time" talk routine: the call needs a time, so its talks
        // take the call's times (same minutes, same days).
        if (!hasTimedTalk) {
            if (times.isEmpty()) return this
            val anytime = blocks.filter { it.kind == Kind.TALK && it.isAnytime }
            val minutes = anytime.firstOrNull()?.minutes ?: defaultMinutes
            val days = anytime.firstOrNull()?.weekdays ?: (1..7).toSet()
            val kept = blocks.filterNot { it.kind == Kind.TALK && it.isAnytime }
            return copy(blocks = kept + times.distinct().sorted().map {
                Block(kind = Kind.TALK, weekdays = days, hour = it / 60, minute = it % 60, minutes = minutes)
            })
        }
        val wanted = times.toSet()
        if (wanted == callTimes.toSet()) return this
        fun keep(b: Block) = !(b.kind == Kind.TALK && b.startMinute !in wanted)
        val list = blocks.filter(::keep).toMutableList()
        val ex = exceptions.mapValues { (_, v) -> v.filter(::keep) }
        val have = list.filter { it.kind == Kind.TALK }.map { it.startMinute }.toSet()
        for (t in (wanted - have).sorted()) {
            list += Block(kind = Kind.TALK, weekdays = (1..7).toSet(), hour = t / 60, minute = t % 60,
                minutes = defaultMinutes)
        }
        return copy(blocks = list, exceptions = ex)
    }

    /**
     * Words, expressions and shadowing were blocks of their own once; each
     * becomes a review block at the same time, keeping its count. Two review
     * blocks landing on the same slot add up into one.
     */
    fun foldingIntoReview(): StudyPlan {
        fun fold(list: List<Block>): List<Block> {
            if (list.none { it.kind.isFoldedIntoReview }) return list
            val out = mutableListOf<Block>()
            for (raw in list) {
                val b = if (raw.kind.isFoldedIntoReview) raw.copy(kind = Kind.REVIEW) else raw
                val i = if (b.kind != Kind.REVIEW) -1 else out.indexOfFirst {
                    it.kind == Kind.REVIEW && it.weekdays == b.weekdays && it.isAnytime == b.isAnytime &&
                        (b.isAnytime || (it.hour == b.hour && it.minute == b.minute))
                }
                if (i >= 0) out[i] = out[i].copy(minutes = out[i].minutes + b.minutes) else out += b
            }
            return out
        }
        val plan = copy(blocks = fold(blocks), exceptions = exceptions.mapValues { fold(it.value) })
        return if (plan != this) plan.mergingTwins() else plan
    }

    companion object {
        /** The same ceiling as [DailyCallStore.MAX_TIMES]. */
        const val MAX_CALL_TIMES = 4
        const val SAY_IT_AGAIN_MINUTES = 5

        fun newId(): String = UUID.randomUUID().toString().uppercase()

        /**
         * The first routine: what the learner already told the app in
         * onboarding — talk X minutes a day. With the daily call on, at its
         * times (and a say-it-again right after the first); without it,
         * "some time today", never a made-up hour. It IS the learner's
         * promise from the start.
         */
        fun seeded(callTimes: List<Int>, goalMinutes: Int, callEnabled: Boolean = true,
                   now: Long = System.currentTimeMillis(),
                   zone: TimeZone = TimeZone.getDefault()): StudyPlan {
            val minutes = maxOf(5, goalMinutes)
            val every = (1..7).toSet()
            val blocks = if (callEnabled && callTimes.isNotEmpty()) {
                val talks = callTimes.distinct().sorted().map {
                    Block(kind = Kind.TALK, weekdays = every, hour = it / 60, minute = it % 60, minutes = minutes)
                }
                val end = callTimes.min() + minutes
                if (end + SAY_IT_AGAIN_MINUTES <= 24 * 60) {
                    talks + Block(kind = Kind.SAY_IT_AGAIN, weekdays = every, hour = end / 60,
                        minute = end % 60, minutes = 1)
                } else talks
            } else {
                listOf(Block(kind = Kind.TALK, weekdays = every, hour = 0, minute = 0,
                    minutes = minutes, anytime = true))
            }
            return StudyPlan(blocks = blocks, streakSince = startOfDay(now, zone), unitsVersion = 2)
        }

        /**
         * How many review items each upcoming slot will find waiting,
         * assuming the learner clears every slot: the first gets everything
         * due by then (overdue included), each later one what came due since.
         */
        fun reviewLoad(slots: List<Long>, dueDates: List<Long>): Map<Long, Int> {
            val out = LinkedHashMap<Long, Int>()
            var previous: Long? = null
            for (slot in slots.sorted()) {
                val prev = previous
                out[slot] = dueDates.count { it <= slot && (prev == null || it > prev) }
                previous = slot
            }
            return out
        }

        // MARK: - Calendar helpers (all in the zone given)

        fun cal(at: Long, zone: TimeZone): Calendar =
            Calendar.getInstance(zone).apply { timeInMillis = at }

        fun startOfDay(at: Long, zone: TimeZone = TimeZone.getDefault()): Long = cal(at, zone).apply {
            set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
        }.timeInMillis

        fun at(day: Long, hour: Int, minute: Int, zone: TimeZone = TimeZone.getDefault()): Long =
            cal(day, zone).apply {
                set(Calendar.HOUR_OF_DAY, hour); set(Calendar.MINUTE, minute)
                set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
            }.timeInMillis

        /** Whole days through the calendar, never fixed millis (DST). */
        fun addDays(day: Long, by: Int, zone: TimeZone = TimeZone.getDefault()): Long =
            cal(day, zone).apply { add(Calendar.DAY_OF_YEAR, by) }.timeInMillis

        /** Gregorian weekday, 1 = Sunday … 7 = Saturday. */
        fun weekday(at: Long, zone: TimeZone = TimeZone.getDefault()): Int =
            cal(at, zone).get(Calendar.DAY_OF_WEEK)

        fun dayKey(at: Long, zone: TimeZone = TimeZone.getDefault()): String {
            val c = cal(at, zone)
            return String.format(java.util.Locale.US, "%04d-%02d-%02d",
                c.get(Calendar.YEAR), c.get(Calendar.MONTH) + 1, c.get(Calendar.DAY_OF_MONTH))
        }

        fun isSameDay(a: Long, b: Long, zone: TimeZone = TimeZone.getDefault()): Boolean =
            startOfDay(a, zone) == startOfDay(b, zone)

        /** The routine's week runs Monday–Sunday whatever the locale (iOS's
         *  weekly plan, CLAUDE.md "Monday–Sunday"); stored weekdays stay
         *  1 = Sunday … 7 = Saturday. */
        val ROUTINE_WEEK_ORDER: List<Int> = listOf(2, 3, 4, 5, 6, 7, 1)

        /** The Monday that starts the routine week holding [at]. */
        fun startOfRoutineWeek(at: Long, zone: TimeZone = TimeZone.getDefault()): Long {
            val c = cal(startOfDay(at, zone), zone)
            val back = (c.get(Calendar.DAY_OF_WEEK) - Calendar.MONDAY + 7) % 7
            return addDays(c.timeInMillis, -back, zone)
        }

        /** The week holding [at], from the locale's first weekday. */
        fun startOfWeek(at: Long, zone: TimeZone = TimeZone.getDefault()): Long {
            val c = cal(startOfDay(at, zone), zone)
            val back = (c.get(Calendar.DAY_OF_WEEK) - c.firstDayOfWeek + 7) % 7
            return addDays(c.timeInMillis, -back, zone)
        }
    }
}
