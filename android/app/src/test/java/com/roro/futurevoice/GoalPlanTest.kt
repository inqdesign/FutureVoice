package com.roro.futurevoice

import com.roro.futurevoice.data.StudyPlan
import com.roro.futurevoice.data.UpcomingGoal
import com.roro.futurevoice.talk.GoalPlan
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Calendar
import java.util.TimeZone

/** iOS `GoalPlanTests` (6aece49b), case for case. */
class GoalPlanTest {
    private val zone = TimeZone.getTimeZone("Europe/Berlin")
    private val now = Calendar.getInstance(zone).apply {
        clear(); set(2026, Calendar.NOVEMBER, 12, 9, 0)
    }.timeInMillis
    private val qs = (1..7).map { "Q$it" }

    private fun plan(days: Int, open: List<String>, talkDays: Set<Int> = (1..7).toSet()): GoalPlan {
        val day = StudyPlan.addDays(now, days, zone)
        val goal = UpcomingGoal(kind = UpcomingGoal.Kind.EXAM, title = "OPIc", date = day, language = "en")
        return GoalPlan.make(goal, open, total = 7, day = day, talkDays = talkDays, now = now, zone = zone)
    }

    @Test fun everyOpenQuestionGetsADayThenMockRunsThenTheDay() {
        val p = plan(18, qs)
        assertEquals(GoalPlan.Item.Question("Q1"), p.rows.first().item)
        assertEquals(qs, p.rows.mapNotNull { (it.item as? GoalPlan.Item.Question)?.text })
        assertEquals(listOf(GoalPlan.Item.Rehearse, GoalPlan.Item.Rehearse, GoalPlan.Item.TheDay),
            p.rows.takeLast(3).map { it.item })
        assertTrue(p.rows.any { it.item == GoalPlan.Item.CatchUp })
    }

    @Test fun shortRunDoublesUpAndSkipsTheMockRun() {
        val p = plan(4, qs)
        assertEquals(7, p.rows.count { it.item.isQuestion })
        assertFalse(p.rows.any { it.item == GoalPlan.Item.Rehearse })
        assertEquals(GoalPlan.Item.TheDay, p.rows.last().item)
    }

    @Test fun onlyTheRoutinesTalkDaysAreUsed() {
        // Mondays and Thursdays only.
        val p = plan(14, listOf("Q1", "Q2"), talkDays = setOf(2, 5))
        for (row in p.rows.dropLast(1)) {
            assertTrue(StudyPlan.weekday(row.date, zone) in setOf(2, 5))
        }
    }

    @Test fun everythingReadyIsAllMockRuns() {
        val p = plan(5, emptyList())
        assertEquals(1, p.rows.dropLast(1).map { it.item }.toSet().size)
        assertEquals(GoalPlan.Item.Rehearse, p.rows.first().item)
    }
}
