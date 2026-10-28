package com.roro.futurevoice

import com.roro.futurevoice.data.HabitAdvisor
import com.roro.futurevoice.data.HabitFinding
import com.roro.futurevoice.data.StudyHabits
import com.roro.futurevoice.data.StudyHabits.Activity
import com.roro.futurevoice.data.StudyHabits.Sitting
import com.roro.futurevoice.data.StudyPlan
import com.roro.futurevoice.data.WeekRecap
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Calendar
import java.util.TimeZone

/**
 * The usage coaching ([StudyHabits], [HabitAdvisor]) — iOS `StudyHabitsTests`
 * (`dc51e6a9`): the same logs always give the same findings, and each finding
 * rests on its numbers.
 */
class StudyHabitsTest {

    private val zone = TimeZone.getTimeZone("Europe/Berlin")

    /** Monday 2026-10-19 00:00 Berlin. */
    private val monday: Long =
        Calendar.getInstance(zone).apply { clear(); set(2026, Calendar.OCTOBER, 19) }.timeInMillis

    private fun at(day: Int, hour: Int, minute: Int = 0): Long =
        Calendar.getInstance(zone).apply { timeInMillis = monday; add(Calendar.MINUTE, day * 1440 + hour * 60 + minute) }.timeInMillis

    private fun habits(sittings: List<Sitting>, days: Int = 7, corrections: Int = 0,
                       fixes: List<WeekRecap.Stumble> = emptyList(),
                       plan: List<StudyPlan.Block> = emptyList()): StudyHabits =
        StudyHabits.compute(monday, at(days, 0), sittings, corrections, fixes, plan, zone)

    @Test fun allInOneDayIsCramming() {
        val h = habits(listOf(Sitting(Activity.TALK, at(6, 20), 45.0), Sitting(Activity.TALK, at(6, 21), 10.0)))
        assertEquals(1, h.activeDays)
        val f = HabitAdvisor.findings(h)
        assertEquals("cramming", f.first().rule)
        assertEquals(HabitFinding.Tone.FIRM, f.first().tone)
    }

    @Test fun talkingWithoutReviewIsFirmAndAddsReviewAfterTheTalk() {
        val sittings = (0 until 5).map { Sitting(Activity.TALK, at(it, 8), 10.0) }
        val fix = WeekRecap.Stumble(was = "since three years", now = "for three years", count = 3)
        val h = habits(sittings, corrections = 14, fixes = listOf(fix))
        val f = HabitAdvisor.findings(h)
        val noReview = f.firstOrNull { it.rule == "no-review" }
        assertEquals(HabitFinding.Tone.FIRM, noReview?.tone)
        assertTrue(noReview?.facts?.any { it.contains("14") } == true)
        // Five of seven days is consistent — the good news is said too.
        assertTrue(f.any { it.tone == HabitFinding.Tone.GOOD })
        val base = listOf(StudyPlan.Block(kind = StudyPlan.Kind.TALK, weekdays = (1..7).toSet(), hour = 8, minute = 0, minutes = 10))
        val routine = HabitAdvisor.routine(base, h, f, 10)
        val review = routine.firstOrNull { it.block.kind == StudyPlan.Kind.REVIEW }
        assertEquals("no-review", review?.rule)
        assertEquals(8 * 60 + 15, review?.block?.startMinute)
        assertTrue(routine.any { it.block.kind == StudyPlan.Kind.SAY_IT_AGAIN })
    }

    @Test fun habitHourIsWhenTheyActuallyPractise() {
        val sittings = (0 until 4).map { Sitting(Activity.TALK, at(it, 22, 10), 8.0) } +
            Sitting(Activity.TALK, at(5, 9), 8.0)
        val h = habits(sittings)
        assertEquals(22, h.habitHour)
        assertEquals(0.8, h.habitShare, 0.01)
    }

    @Test fun plannedReviewNeverDoneMovesToTheHabitHour() {
        val sittings = (0 until 5).map { Sitting(Activity.TALK, at(it, 8), 10.0) }
        val plan = listOf(
            StudyPlan.Block(kind = StudyPlan.Kind.TALK, weekdays = (1..7).toSet(), hour = 8, minute = 0, minutes = 10),
            StudyPlan.Block(kind = StudyPlan.Kind.REVIEW, weekdays = (1..7).toSet(), hour = 21, minute = 30, minutes = 10))
        val h = habits(sittings, plan = plan)
        assertEquals(0, h.plan.firstOrNull { it.kind == StudyPlan.Kind.REVIEW }?.keptDays)
        val f = HabitAdvisor.findings(h)
        assertTrue(f.any { it.rule == "plan-missed-review" })
        val routine = HabitAdvisor.routine(plan, h, f, 10)
        assertEquals(8, routine.firstOrNull { it.block.kind == StudyPlan.Kind.REVIEW }?.block?.hour)
    }

    @Test fun aGapInsideTheWindowIsCountedFromTheFirstSitting() {
        val h = habits(listOf(Sitting(Activity.TALK, at(0, 9), 10.0), Sitting(Activity.TALK, at(6, 9), 10.0)), days = 8)
        assertEquals(5, h.longestGapDays)
        assertTrue(HabitAdvisor.findings(h).any { it.rule == "gap" || it.rule == "cramming" })
    }

    @Test fun neverMoreThanFourAndNeverOnlyCriticism() {
        val sittings = (0 until 6).map { Sitting(Activity.TALK, at(it, 8), 10.0) }
        val plan = StudyPlan.Kind.entries.filter { it != StudyPlan.Kind.TALK && it != StudyPlan.Kind.TEST }.map {
            StudyPlan.Block(kind = it, weekdays = (1..7).toSet(), hour = 21, minute = 0, minutes = 2)
        }
        val f = HabitAdvisor.findings(habits(sittings, corrections = 9,
            fixes = listOf(WeekRecap.Stumble(was = "a", now = "b", count = 2)), plan = plan))
        assertTrue(f.size <= HabitAdvisor.MAX_FINDINGS)
        assertEquals(HabitFinding.Tone.GOOD, f.last().tone)
    }

    @Test fun aShortTrialStillGetsEvidence() {
        // Three days, a talk each day, some review, corrections, no redo.
        val sittings = (0 until 3).map { Sitting(Activity.TALK, at(it, 18), 4.0) } +
            (0 until 11).map { Sitting(Activity.REVIEW, at(2, 19, it)) }
        val h = habits(sittings, days = 3, corrections = 7)
        val rules = HabitAdvisor.findings(h).map { it.rule }
        assertTrue("no-say-again" in rules)
        assertTrue("came-back" in rules || "reviewed" in rules)
        val routine = HabitAdvisor.routine(emptyList(), h, HabitAdvisor.findings(h), 10)
        assertEquals("no-say-again", routine.firstOrNull { it.block.kind == StudyPlan.Kind.SAY_IT_AGAIN }?.rule)
    }
}
