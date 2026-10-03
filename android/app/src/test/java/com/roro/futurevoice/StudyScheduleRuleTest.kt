package com.roro.futurevoice

import com.roro.futurevoice.data.DrillReminder
import com.roro.futurevoice.ui.brand.DrillBin
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.util.Calendar

/**
 * Plan 5.2 — the deck's time rules. iOS `StudyReminderPolicyTests` case for
 * case, plus the one folder implementation both decks read
 * (`DrillBin.folder(forReturnIn:)`: ≤12 h Soon · ≤48 h Tomorrow · else Later).
 */
class StudyScheduleRuleTest {
    private val hour = 3_600_000L

    /** Noon today, so "+1 minute" and "+3 days" stay inside waking hours. */
    private val noon = Calendar.getInstance().apply {
        set(Calendar.HOUR_OF_DAY, 12); set(Calendar.MINUTE, 0); set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
    }.timeInMillis

    @Test fun perItemCallbackFiresAtThePromisedTime() {
        val soon = noon + 60_000
        assertEquals("a 1-minute promise must fire in 1 minute, not park until 9am",
            soon, DrillReminder.fireDate(noon, soon, hasDueNow = false))
    }

    @Test fun aggregateDefersToTomorrowMorningWhenABacklogIsDue() {
        val fire = DrillReminder.fireDate(noon, noon + 60_000, hasDueNow = true)!!
        assertNotEquals(noon + 60_000, fire)
        val cal = Calendar.getInstance().apply { timeInMillis = fire }
        assertEquals(9, cal.get(Calendar.HOUR_OF_DAY))
        assertEquals(Calendar.getInstance().apply { timeInMillis = noon; add(Calendar.DAY_OF_YEAR, 1) }
            .get(Calendar.DAY_OF_YEAR), cal.get(Calendar.DAY_OF_YEAR))
    }

    @Test fun nothingWaitingSchedulesNothing() = assertNull(DrillReminder.fireDate(noon, null, hasDueNow = false))

    @Test fun aFolderIsAWindowOnTheReturnTime() {
        assertEquals(DrillBin.TEN_MINUTES, DrillBin.folder(10 * 60_000L))
        assertEquals(DrillBin.TEN_MINUTES, DrillBin.folder(12 * hour))
        assertEquals(DrillBin.TOMORROW, DrillBin.folder(12 * hour + 1))
        assertEquals(DrillBin.TOMORROW, DrillBin.folder(48 * hour))
        assertEquals(DrillBin.THREE_DAYS, DrillBin.folder(48 * hour + 1))
        assertEquals(DrillBin.THREE_DAYS, DrillBin.folder(30 * 24 * hour))
    }
}
