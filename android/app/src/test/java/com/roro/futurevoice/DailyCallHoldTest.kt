package com.roro.futurevoice

import com.roro.futurevoice.data.DailyCallScheduler
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Calendar

/**
 * A ring that came due while a call was live settles as answered (iOS
 * `DailyCallScheduler.releaseAfterLiveCall`, 2026-09-28). This pins which
 * slots count as "came due during the call".
 */
class DailyCallHoldTest {

    private fun at(hour: Int, minute: Int, dayOffset: Int = 0): Long = Calendar.getInstance().apply {
        set(2026, Calendar.OCTOBER, 4, hour, minute, 0); set(Calendar.MILLISECOND, 0)
        add(Calendar.DAY_OF_YEAR, dayOffset)
    }.timeInMillis

    @Test fun aSlotInsideTheCallCameDue() {
        assertTrue(DailyCallScheduler.cameDueDuring(listOf(8 * 60), at(7, 55), at(8, 10)))
    }

    @Test fun aSlotBeforeOrAfterTheCallDidNot() {
        val slots = listOf(8 * 60, 13 * 60)
        assertFalse(DailyCallScheduler.cameDueDuring(slots, at(9, 0), at(9, 30)))
        // The ring that was ANSWERED to start this call is not "during" it.
        assertFalse(DailyCallScheduler.cameDueDuring(slots, at(8, 0), at(8, 20)))
    }

    @Test fun aCallAcrossMidnightSeesTheNextDaysSlot() {
        assertTrue(DailyCallScheduler.cameDueDuring(listOf(5), at(23, 50), at(0, 10, dayOffset = 1)))
    }
}
