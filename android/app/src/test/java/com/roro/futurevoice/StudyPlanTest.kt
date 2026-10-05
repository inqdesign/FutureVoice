package com.roro.futurevoice

import com.roro.futurevoice.data.ActivityEventLog
import com.roro.futurevoice.data.PlannerDay
import com.roro.futurevoice.data.PromiseStreak
import com.roro.futurevoice.data.StudyPlan
import com.roro.futurevoice.data.StudyPlan.Block
import com.roro.futurevoice.data.StudyPlan.Kind
import com.roro.futurevoice.data.StudyPlan.Scope
import com.roro.futurevoice.data.WeeklyTestSchedule
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Calendar
import java.util.TimeZone

/**
 * The study timetable — iOS `StudyPlanTests` (1.1.4, `ebf848e`). It schedules
 * the daily call, so the first thing it must do is ring exactly when the call
 * rang before it existed. The legacy-conversion cases (plans saved by older
 * iOS builds in minutes, with a review switch, or with a derived say it
 * again) have no Android counterpart: no Android build ever wrote one.
 */
class StudyPlanTest {

    private val zone = TimeZone.getTimeZone("Asia/Seoul")

    /** 2026-10-05 is a Monday. */
    private fun at(day: Int, hour: Int, minute: Int = 0): Long =
        Calendar.getInstance(zone).apply { clear(); set(2026, Calendar.OCTOBER, day, hour, minute) }.timeInMillis

    private fun t(h: Int, m: Int = 0) = h * 60 + m
    private fun every() = (1..7).toSet()

    // MARK: - The call

    @Test fun seededPlanRingsLikeTheOldCall() {
        val plan = StudyPlan.seeded(listOf(t(8), t(13)), 10, zone = zone)
        assertEquals(listOf(at(5, 8), at(5, 13)), plan.callDates(at(5, 7), zone))
        assertEquals(listOf(at(5, 13)), plan.callDates(at(5, 9), zone))
        assertEquals(listOf(at(6, 8)), plan.callDates(at(5, 14), zone))
    }

    @Test fun weekdaysAndRestDaysAreSkipped() {
        var plan = StudyPlan(blocks = listOf(Block(kind = Kind.TALK, weekdays = setOf(2, 4), hour = 8, minute = 0, minutes = 10)))
        assertEquals(listOf(at(7, 8)), plan.callDates(at(5, 20), zone))
        plan = plan.copy(restDays = setOf(StudyPlan.dayKey(at(7, 0), zone)))
        assertEquals(listOf(at(12, 8)), plan.callDates(at(5, 20), zone))
    }

    @Test fun noTalkBlocksMeansNoRing() {
        val plan = StudyPlan(blocks = listOf(Block(kind = Kind.REVIEW, weekdays = every(), hour = 8, minute = 0, minutes = 10)))
        assertEquals(emptyList<Long>(), plan.callDates(at(5, 7), zone))
    }

    // MARK: - Derived blocks

    @Test fun sayItAgainIsAnOrdinaryBlock() {
        val plan = StudyPlan.seeded(listOf(t(8), t(13)), 10, zone = zone)
        val again = plan.blocks.first { it.kind == Kind.SAY_IT_AGAIN }
        assertEquals(8 * 60 + 10, again.startMinute)
        val moved = plan.moving(again.id, at(6, 0), at(6, 20), Scope.EVERY_WEEK, zone)!!
        assertEquals(Kind.SAY_IT_AGAIN, moved.occurrences(at(6, 0), zone = zone).last().kind)
        assertEquals(at(6, 20), moved.occurrences(at(6, 0), zone = zone).last().start)
    }

    @Test fun weeklyTestLandsOnItsWeekday() {
        val sat = StudyPlan().occurrences(at(10, 0), WeeklyTestSchedule(7, 10, 0), zone)
        assertEquals(listOf(Kind.TEST), sat.map { it.kind })
    }

    @Test fun reviewLoadSplitsBetweenSlots() {
        val slots = listOf(at(5, 21), at(6, 21))
        val due = listOf(at(4, 9), at(5, 12), at(5, 22), at(6, 20), at(7, 9))
        val load = StudyPlan.reviewLoad(slots, due)
        assertEquals(2, load[at(5, 21)])
        assertEquals(2, load[at(6, 21)])
    }

    // MARK: - Moving

    private fun weekdayTalk(id: String = "B") =
        StudyPlan(blocks = listOf(Block(id = id, kind = Kind.TALK, weekdays = (2..6).toSet(), hour = 8, minute = 0, minutes = 10)))

    @Test fun justThisDayLeavesTheWeekAlone() {
        val moved = weekdayTalk().moving("B", at(6, 0), at(6, 9), Scope.THIS_DAY, zone)!!
        assertEquals(at(6, 9), moved.occurrences(at(6, 0), zone = zone).first().start)
        assertEquals(at(7, 8), moved.occurrences(at(7, 0), zone = zone).first().start)
        assertEquals(at(13, 8), moved.occurrences(at(13, 0), zone = zone).first().start)
    }

    @Test fun everyWeekSplitsOneWeekdayOff() {
        val moved = weekdayTalk().moving("B", at(6, 0), at(6, 9), Scope.EVERY_WEEK, zone)!!
        assertEquals(at(13, 9), moved.occurrences(at(13, 0), zone = zone).first().start)
        assertEquals(at(14, 8), moved.occurrences(at(14, 0), zone = zone).first().start)
    }

    @Test fun allDaysMovesTheWholeBlock() {
        val moved = weekdayTalk().moving("B", at(6, 0), at(6, 7, 30), Scope.ALL_DAYS, zone)!!
        assertEquals(1, moved.blocks.size)
        assertEquals(at(9, 7, 30), moved.occurrences(at(9, 0), zone = zone).first().start)
    }

    @Test fun aFifthCallTimeIsRefused() {
        var plan = StudyPlan.seeded(listOf(t(7), t(8), t(12), t(18)), 10, zone = zone)
        val id = plan.blocks[0].id
        assertNull(plan.moving(id, at(6, 0), at(6, 21), Scope.THIS_DAY, zone))
        plan = plan.copy(blocks = plan.blocks.mapIndexed { i, b -> if (i == 0) b.copy(weekdays = setOf(3)) else b })
        // Moving the only 7:00 block (Tuesday) keeps four distinct times.
        assertNotNull(plan.moving(id, at(6, 0), at(6, 21), Scope.EVERY_WEEK, zone))
    }

    @Test fun callTimesEditedElsewhereAreAdopted() {
        var plan = StudyPlan.seeded(listOf(t(8)), 10, zone = zone)
        plan = plan.copy(blocks = plan.blocks.map { if (it.kind == Kind.TALK) it.copy(weekdays = setOf(2, 3)) else it })
        plan = plan.adoptingCallTimes(listOf(t(8), t(19)), 15)
        val talk = plan.blocks.filter { it.kind == Kind.TALK }
        assertEquals(2, talk.size)
        assertEquals(setOf(2, 3), talk.first { it.hour == 8 }.weekdays)
        assertEquals(every(), talk.first { it.hour == 19 }.weekdays)
        plan = plan.adoptingCallTimes(listOf(t(19)), 15)
        assertEquals(listOf(19), plan.blocks.filter { it.kind == Kind.TALK }.map { it.hour })
    }

    @Test fun draggedDayLandsFirstThenTheRestCanFollow() {
        val moved = weekdayTalk().moving("B", at(6, 0), at(6, 9), Scope.EVERY_WEEK, zone)!!
        assertEquals(at(6, 9), moved.occurrences(at(6, 0), zone = zone).first().start)
        assertEquals(at(7, 8), moved.occurrences(at(7, 0), zone = zone).first().start)
        val all = moved.following("B", 9, 0)!!
        assertEquals(1, all.blocks.size)
        assertEquals((2..6).toSet(), all.blocks[0].weekdays)
        assertEquals(at(7, 9), all.occurrences(at(7, 0), zone = zone).first().start)
    }

    // MARK: - What happened

    @Test fun countsFillBlocksInOrder() {
        val plan = StudyPlan(blocks = listOf(
            Block(kind = Kind.TALK, weekdays = setOf(3), hour = 8, minute = 0, minutes = 10),
            Block(kind = Kind.TALK, weekdays = setOf(3), hour = 20, minute = 0, minutes = 10),
            Block(kind = Kind.REVIEW, weekdays = setOf(3), hour = 19, minute = 0, minutes = 10)))
        val occ = plan.occurrences(at(6, 0), zone = zone)
        val totals = PlannerDay.Totals(talkMinutes = 15.0, words = 4.0)
        val p = PlannerDay.progress(occ, totals)
        val talks = occ.filter { it.kind == Kind.TALK }
        assertEquals(1.0, p[talks[0].id]!!, 0.001)
        assertEquals(0.5, p[talks[1].id]!!, 0.001)
        assertEquals(0.4, p[occ.first { it.kind == Kind.REVIEW }.id]!!, 0.001)
        assertEquals(setOf(talks[0].id), PlannerDay.done(occ, totals))
    }

    @Test fun wordsExpressionsAndShadowFoldIntoReview() {
        val plan = StudyPlan(blocks = listOf(
            Block(kind = Kind.WORDS, weekdays = setOf(2, 4), hour = 19, minute = 0, minutes = 10),
            Block(kind = Kind.EXPRESSIONS, weekdays = setOf(2, 4), hour = 19, minute = 0, minutes = 3),
            Block(kind = Kind.SHADOW, weekdays = setOf(7), hour = 11, minute = 0, minutes = 2),
            Block(kind = Kind.TALK, weekdays = every(), hour = 8, minute = 0, minutes = 10)))
        val folded = plan.foldingIntoReview()
        assertFalse(folded.blocks.any { it.kind.isFoldedIntoReview })
        val review = folded.blocks.filter { it.kind == Kind.REVIEW }
        assertEquals(2, review.size)
        assertEquals(13, review.first { it.hour == 19 }.minutes)
        assertEquals(2, review.first { it.hour == 11 }.minutes)
        assertEquals(folded, folded.foldingIntoReview())
    }

    @Test fun reviewCountsEveryKindOfReview() {
        val totals = PlannerDay.Totals(words = 4.0, expressions = 2.0, cards = 5.0, shadow = 1.0)
        assertEquals(12.0, totals.amount(Kind.REVIEW), 0.001)
    }

    /** iOS `testASpeechTakeKeepsASpeechBlock` (`8f135c24`). */
    @Test fun aSpeechTakeKeepsASpeechBlock() {
        val plan = StudyPlan(blocks = listOf(Block(kind = Kind.SPEECH, weekdays = setOf(3), hour = 20, minute = 0, minutes = 1)))
        val occ = plan.occurrences(at(6, 0), zone = zone)
        assertTrue(PlannerDay.done(occ, PlannerDay.Totals()).isEmpty())
        assertEquals(setOf(occ[0].id), PlannerDay.done(occ, PlannerDay.Totals(speech = 1.0)))
        val acts = PlannerDay.actuals(emptyList(), listOf(ActivityEventLog.Event(ActivityEventLog.Kind.SPEECH, at(6, 20, 5))))
        assertEquals(listOf(PlannerDay.Actual.Kind.SPEECH), acts.map { it.kind })
        assertEquals(1, PlannerDay.absorbed(occ, acts).size)
        assertTrue(Kind.SPEECH in Kind.placeable)
    }

    @Test fun repsCloseTogetherAreOneSitting() {
        val events = listOf(at(6, 20, 0), at(6, 20, 4), at(6, 20, 9), at(6, 21, 0))
            .map { ActivityEventLog.Event(ActivityEventLog.Kind.DRILL, it) }
        assertEquals(listOf(3, 1), PlannerDay.actuals(emptyList(), events).map { it.count })
    }

    @Test fun aSittingOnThePlanIsOneBlock() {
        val plan = StudyPlan(blocks = listOf(Block(kind = Kind.TALK, weekdays = setOf(3, 4), hour = 8, minute = 0, minutes = 10)))
        val tue = plan.occurrences(at(6, 0), zone = zone)
        val onTime = PlannerDay.actuals(listOf(PlannerDay.Talk("a", at(6, 8, 3), at(6, 8, 15), "x")), emptyList())
        assertEquals(1, PlannerDay.absorbed(tue, onTime).size)
        val atNoon = PlannerDay.actuals(listOf(PlannerDay.Talk("b", at(6, 12), at(6, 12, 10), "x")), emptyList())
        assertTrue(PlannerDay.absorbed(tue, atNoon).isEmpty())
    }

    // MARK: - The promise

    private fun walk(marks: Map<Int, PromiseStreak.Standing>, today: Int): Int =
        PromiseStreak.streak(at(today, 12), at(1, 0), zone) { d ->
            marks[Calendar.getInstance(zone).apply { timeInMillis = d }.get(Calendar.DAY_OF_MONTH)]
                ?: PromiseStreak.Standing.MISSED
        }

    @Test fun restDaysNeitherCountNorBreak() {
        val k = PromiseStreak.Standing.KEPT
        assertEquals(3, walk(mapOf(1 to k, 2 to PromiseStreak.Standing.REST, 3 to k, 4 to k), 4))
    }

    @Test fun todayIsAliveUntilItIsOver() {
        val k = PromiseStreak.Standing.KEPT
        assertEquals(2, walk(mapOf(3 to k, 4 to k, 5 to PromiseStreak.Standing.MISSED), 5))
        assertEquals(3, walk(mapOf(3 to k, 4 to k, 5 to k), 5))
    }

    @Test fun aMissedDayEndsIt() {
        val k = PromiseStreak.Standing.KEPT
        assertEquals(1, walk(mapOf(2 to k, 3 to PromiseStreak.Standing.MISSED, 4 to k), 4))
    }

    @Test fun restWeekdaysPlanNothing() {
        val plan = StudyPlan.seeded(listOf(t(8)), 10, zone = zone).copy(offWeekdays = setOf(1, 7))
        assertTrue(plan.occurrences(at(10, 0), zone = zone).isEmpty())   // Saturday
        assertFalse(plan.occurrences(at(9, 0), zone = zone).isEmpty())   // Friday
        assertEquals(listOf(at(12, 8)), plan.callDates(at(9, 20), zone))
    }

    @Test fun anAnytimeTalkTakesTheCallsTime() {
        var plan = StudyPlan.seeded(emptyList(), 15, callEnabled = false, zone = zone)
        assertFalse(plan.hasTimedTalk)
        plan = plan.adoptingCallTimes(listOf(t(8)), 10)
        val talks = plan.blocks.filter { it.kind == Kind.TALK }
        assertEquals(1, talks.size)
        assertEquals(8, talks.first().hour)
        assertEquals("keeps the routine's own minutes", 15, talks.first().minutes)
        assertFalse(talks.first().isAnytime)
        assertEquals(at(5, 8), plan.callDates(at(5, 7), zone).first())
    }

    @Test fun onboardingRoutineWithoutACallIsAnytime() {
        val plan = StudyPlan.seeded(listOf(t(8)), 15, callEnabled = false, now = at(5, 9), zone = zone)
        assertEquals(1, plan.blocks.size)
        assertTrue(plan.blocks[0].isAnytime)
        assertEquals(15, plan.blocks[0].minutes)
        assertNotNull(plan.streakSince)
        assertFalse(plan.hasTimedTalk)
        val occ = plan.occurrences(at(6, 0), zone = zone)[0]
        assertFalse(occ.isOver(at(6, 23, 59), zone))
        assertTrue(occ.isOver(at(7, 0, 1), zone))
    }

    @Test fun thePlanRoundTripsThroughItsFile() {
        val plan = StudyPlan.seeded(listOf(t(8)), 10, zone = zone).copy(offWeekdays = setOf(1),
            exceptions = mapOf("2026-10-06" to listOf(Block(kind = Kind.REVIEW, weekdays = emptySet(), hour = 20, minute = 0, minutes = 20))))
        val json = com.roro.futurevoice.data.StoreJson.json
        val text = json.encodeToString(StudyPlan.serializer(), plan)
        assertTrue("iOS raw value on disk", "\"sayItAgain\"" in text)
        assertEquals(plan, json.decodeFromString(StudyPlan.serializer(), text))
    }
}
