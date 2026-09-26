package com.roro.futurevoice

import com.roro.futurevoice.data.PracticeLog
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The Home streak is NOT the Core's streak (iOS `9914570`). A day counts
 * when the learner DID something — talk in any language, or any practice rep
 * including a Watch scene. Opening the app is not enough.
 *
 * What a JVM can reach is the day's own predicate; the walk over days reads
 * files and is checked on a device.
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
}
