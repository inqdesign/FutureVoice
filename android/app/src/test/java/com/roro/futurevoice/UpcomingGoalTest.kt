package com.roro.futurevoice

import com.roro.futurevoice.data.UpcomingGoal
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDate
import java.time.ZoneId

class UpcomingGoalTest {
    private val zone = ZoneId.systemDefault()
    private val now = LocalDate.now(zone).atTime(12, 0).atZone(zone).toInstant().toEpochMilli()

    private fun goal(inDays: Int, now: Long) =
        UpcomingGoal(kind = UpcomingGoal.Kind.INTERVIEW, title = "Interview",
                     date = LocalDate.now(zone).plusDays(inDays.toLong()).atTime(9, 0)
                         .atZone(zone).toInstant().toEpochMilli(),
                     language = "en")

    @Test fun daysLeftGoesNegativeOnceTheDayHasPassed() {
        assertEquals(3, goal(3, now).daysLeft(now, zone))
        assertEquals(0, goal(0, now).daysLeft(now, zone))
        assertEquals(-2, goal(-2, now).daysLeft(now, zone))
    }

    @Test fun aPastGoalIsPast() {
        assertTrue(goal(-1, now).isPast(now))
        assertFalse(goal(0, now).isPast(now))
    }
}
