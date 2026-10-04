package com.roro.futurevoice.data

import kotlin.math.abs

/**
 * One day of the routine as it HAPPENED, and which planned blocks that
 * covers (iOS `PlannerDay`). Pure, so the page and the tests read the same
 * answer.
 *
 * The rule the whole page rests on: a planned block is done when the same
 * KIND of practice happened that day, at any time. Doing the 8:00 talk at
 * noon is doing it — a planner that marks it missed is the one people switch
 * off.
 */
object PlannerDay {

    /** What actually happened, grouped into sittings. */
    data class Actual(
        val kind: Kind,
        val start: Long,
        val end: Long,
        /** The talk's title, for a talk. */
        val title: String? = null,
        val sessionId: String? = null,
        val count: Int = 1,
    ) {
        enum class Kind(val raw: String) { TALK("talk"), REVIEW("review"), SHADOW("shadow"),
            SCENE("scene"), SAY_IT_AGAIN("sayItAgain") }

        val id: String get() = sessionId?.let { "talk-$it" } ?: "${kind.raw}-$start"

        /** The practice to open for this sitting; null for a Watch scene. */
        val planKind: StudyPlan.Kind? get() = when (kind) {
            Kind.TALK -> StudyPlan.Kind.TALK
            Kind.REVIEW -> StudyPlan.Kind.REVIEW
            Kind.SHADOW -> StudyPlan.Kind.SHADOW
            Kind.SAY_IT_AGAIN -> StudyPlan.Kind.SAY_IT_AGAIN
            Kind.SCENE -> null
        }

        /** Whether this sitting is the kind of practice a planned block asks for. */
        fun covers(planned: StudyPlan.Kind): Boolean = when (kind) {
            Kind.TALK -> planned == StudyPlan.Kind.TALK
            Kind.SHADOW -> planned == StudyPlan.Kind.SHADOW
            Kind.SAY_IT_AGAIN -> planned == StudyPlan.Kind.SAY_IT_AGAIN
            Kind.REVIEW -> planned == StudyPlan.Kind.REVIEW || planned.isFoldedIntoReview
            Kind.SCENE -> false
        }
    }

    data class Talk(val id: String, val start: Long, val end: Long, val title: String)

    /** Reps closer together than this are one sitting. */
    const val CLUSTER_GAP_MS = 10 * 60_000L
    /** A sitting of one rep still draws as a block this long. */
    const val MINIMUM_SPAN_MS = 5 * 60_000L
    /** A sitting that started this close to its plan is drawn as ONE block. */
    const val ABSORB_WINDOW_MS = 45 * 60_000L

    fun actuals(talks: List<Talk>, events: List<ActivityEventLog.Event>): List<Actual> {
        val out = talks.map {
            Actual(Actual.Kind.TALK, it.start, maxOf(it.end, it.start + MINIMUM_SPAN_MS),
                title = it.title, sessionId = it.id)
        }.toMutableList()
        fun group(k: ActivityEventLog.Kind): Actual.Kind = when (k) {
            // Every kind of review is one sitting of review (iOS 2026-10-03).
            ActivityEventLog.Kind.DRILL, ActivityEventLog.Kind.WORD,
            ActivityEventLog.Kind.EXPRESSION, ActivityEventLog.Kind.SHADOW -> Actual.Kind.REVIEW
            ActivityEventLog.Kind.SCENE -> Actual.Kind.SCENE
            ActivityEventLog.Kind.SAY_IT_AGAIN -> Actual.Kind.SAY_IT_AGAIN
        }
        for ((kind, events) in events.groupBy { group(it.kind) }) {
            var start = 0L; var last = 0L; var count = 0
            for (d in events.map { it.at }.sorted()) {
                if (count > 0 && d - last <= CLUSTER_GAP_MS) { last = d; count += 1 }
                else {
                    if (count > 0) out += Actual(kind, start, maxOf(last, start + MINIMUM_SPAN_MS), count = count)
                    start = d; last = d; count = 1
                }
            }
            if (count > 0) out += Actual(kind, start, maxOf(last, start + MINIMUM_SPAN_MS), count = count)
        }
        return out.sortedBy { it.start }
    }

    /** What a day added up to, in the units blocks are promised in. */
    data class Totals(
        val talkMinutes: Double = 0.0,
        val words: Double = 0.0,
        val expressions: Double = 0.0,
        val cards: Double = 0.0,
        val shadow: Double = 0.0,
        val sayItAgain: Double = 0.0,
        val test: Double = 0.0,
    ) {
        fun amount(kind: StudyPlan.Kind): Double = when (kind) {
            StudyPlan.Kind.TALK -> talkMinutes
            StudyPlan.Kind.WORDS -> words
            StudyPlan.Kind.EXPRESSIONS -> expressions
            // Review is every kind of review counted together.
            StudyPlan.Kind.REVIEW -> words + expressions + cards + shadow
            StudyPlan.Kind.SHADOW -> shadow
            StudyPlan.Kind.SAY_IT_AGAIN -> sayItAgain
            StudyPlan.Kind.TEST -> test
        }
    }

    /**
     * A day's totals from the logs that already count them: the talk meter
     * (the ring's seconds), the practice log's FINISHED counts — the numbers
     * the daily goals are judged by, so postponing a card is not doing it —
     * and finished say-it-again runs and tests.
     */
    fun totals(talkSeconds: Int, log: PracticeLog.Day?, events: List<ActivityEventLog.Event>,
               testFinished: Boolean): Totals {
        val d = log ?: PracticeLog.Day()
        return Totals(
            talkMinutes = talkSeconds / 60.0,
            words = d.wordDone.toDouble(),
            expressions = d.expressionDone.toDouble(),
            cards = d.drillDone.toDouble(),
            shadow = d.shadowDone.toDouble(),
            sayItAgain = events.count { it.kind == ActivityEventLog.Kind.SAY_IT_AGAIN }.toDouble(),
            test = if (testFinished) 1.0 else 0.0,
        )
    }

    /**
     * How far along each planned block is, 0…1. Blocks of the same kind fill
     * in plan order: two 10-minute talks are half done at 10 minutes, not
     * both.
     */
    fun progress(planned: List<StudyPlan.Occurrence>, totals: Totals): Map<String, Double> {
        val out = LinkedHashMap<String, Double>()
        val left = HashMap<StudyPlan.Kind, Double>()
        for (occ in planned.sortedBy { it.start }) {
            val have = left[occ.kind] ?: totals.amount(occ.kind)
            val need = maxOf(1, occ.amount).toDouble()
            out[occ.id] = (have / need).coerceIn(0.0, 1.0)
            left[occ.kind] = maxOf(0.0, have - need)
        }
        return out
    }

    fun done(planned: List<StudyPlan.Occurrence>, totals: Totals): Set<String> =
        progress(planned, totals).filterValues { it >= 1.0 }.keys

    /** Planned blocks a real sitting landed ON — same kind, within
     *  [ABSORB_WINDOW_MS]. Keyed by occurrence id, valued by the actual's id. */
    fun absorbed(planned: List<StudyPlan.Occurrence>, actuals: List<Actual>): Map<String, String> {
        val out = HashMap<String, String>()
        val used = HashSet<String>()
        for (occ in planned.sortedBy { it.start }) {
            val match = actuals.firstOrNull { a ->
                a.id !in used && a.covers(occ.kind) && abs(a.start - occ.start) <= ABSORB_WINDOW_MS
            } ?: continue
            out[occ.id] = match.id
            used += match.id
        }
        return out
    }

    /** Practice that happened outside every planned block of its kind. */
    fun unplanned(actuals: List<Actual>, planned: List<StudyPlan.Occurrence>): List<Actual> {
        val kinds = planned.map { it.kind }.toSet()
        val talkPlans = planned.count { it.kind == StudyPlan.Kind.TALK }
        var talkSeen = 0
        return actuals.filter { a ->
            when (a.kind) {
                Actual.Kind.TALK -> { talkSeen += 1; talkSeen > talkPlans }
                Actual.Kind.REVIEW -> kinds.none { it == StudyPlan.Kind.REVIEW || it.isFoldedIntoReview }
                Actual.Kind.SHADOW -> StudyPlan.Kind.SHADOW !in kinds
                Actual.Kind.SAY_IT_AGAIN -> StudyPlan.Kind.SAY_IT_AGAIN !in kinds
                Actual.Kind.SCENE -> true
            }
        }
    }
}
