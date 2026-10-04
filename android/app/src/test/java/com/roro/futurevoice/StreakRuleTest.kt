package com.roro.futurevoice

import com.roro.futurevoice.data.PracticeLog
import com.roro.futurevoice.data.TalkTimeLog
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The Home streak is NOT the Core's streak (iOS `9914570`). A day counts
 * when the learner DID something — talk in any language, or any practice rep
 * including a Watch scene. Opening the app is not enough.
 *
 * The day's predicate, and the walk over days (iOS `PracticeStats.computeStreak`)
 * against a set of active days — anchored to TODAY when today counts and to
 * yesterday otherwise, because a streak is alive until its day is over.
 */
class StreakRuleTest {

    @Test fun anyRepMakesTheDayCount() {
        assertTrue(PracticeLog.Day(drillReps = 1).didSomething)
        assertTrue(PracticeLog.Day(wordReps = 1).didSomething)
        assertTrue(PracticeLog.Day(expressionReps = 1).didSomething)
        assertTrue(PracticeLog.Day(shadowReps = 1).didSomething)
    }

    /** A scene plays itself, so it is out of the goal — but sitting through
     *  one is effort, and it keeps the streak alive. */
    @Test fun aWatchSceneCountsForTheStreakButNotTheGoal() {
        val day = PracticeLog.Day(sceneReps = 1)
        assertTrue(day.didSomething)
        assertFalse(day.total > 0)
    }

    @Test fun anEmptyDayCountsForNothing() {
        assertFalse(PracticeLog.Day().didSomething)
    }

    // ── The walk (plan 5.1) ──

    private val zone = java.util.TimeZone.getTimeZone("Europe/Berlin")
    private fun at(y: Int, m: Int, d: Int, h: Int = 12): Long =
        java.util.Calendar.getInstance(zone).apply { clear(); set(y, m - 1, d, h, 0) }.timeInMillis
    private fun key(t: Long) = java.text.SimpleDateFormat("yyyy-MM-dd").apply { timeZone = zone }
        .format(java.util.Date(t))
    private fun walk(now: Long, vararg days: String) =
        TalkTimeLog.streakWalk(now, java.util.Calendar.getInstance(zone)) { key(it) in days }

    @Test fun todayCountsWhenItIsAlreadyDone() {
        assertEquals(3, walk(at(2026, 10, 4), "2026-10-04", "2026-10-03", "2026-10-02"))
    }

    @Test fun anUnfinishedTodayDoesNotBreakTheStreak() {
        // Morning, nothing yet today: the run up to yesterday still stands.
        assertEquals(2, walk(at(2026, 10, 4, 8), "2026-10-03", "2026-10-02"))
    }

    @Test fun aMissedYesterdayIsZero() {
        assertEquals(0, walk(at(2026, 10, 4), "2026-10-02", "2026-10-01"))
    }

    @Test fun aGapEndsTheRun() {
        assertEquals(1, walk(at(2026, 10, 4), "2026-10-04", "2026-10-02", "2026-10-01"))
    }

    /** Calendar steps, not 86 400 000 ms: the 25-hour night of 25 Oct in
     *  Berlin must neither skip nor repeat a day. */
    @Test fun aDaylightSavingNightIsOneDay() {
        assertEquals(3, walk(at(2026, 10, 26, 0), "2026-10-26", "2026-10-25", "2026-10-24"))
        assertEquals(3, walk(at(2026, 3, 30, 0), "2026-03-30", "2026-03-29", "2026-03-28"))
    }
}
