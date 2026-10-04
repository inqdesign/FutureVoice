package com.roro.futurevoice

import com.roro.futurevoice.data.DayCardStore
import com.roro.futurevoice.ui.brand.DayCardData
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.nio.file.Files
import java.util.Calendar

/**
 * iOS `DayCardStore.freeze` / `resolve` (plan 5.12): a card is what a day
 * WAS, so a past day is settled and read back from its snapshot — and TODAY
 * is never frozen and always read live.
 */
class DayCardFreezeTest {
    private val dir = Files.createTempDirectory("daycards").toFile()
    private val now = Calendar.getInstance().apply { set(2026, 9, 4, 14, 0) }.timeInMillis
    private val yesterday = Calendar.getInstance().apply { timeInMillis = now; add(Calendar.DAY_OF_YEAR, -1) }.timeInMillis
    private fun card(day: Long, talk: Int = 11, talks: Int = 2) =
        DayCardData(day, talkMinutes = talk, studyMinutes = talk + 5, streakDays = 3, talks = talks)

    @Test fun todayIsNeverFrozen() {
        assertFalse(DayCardStore.freezeIn(dir, card(now), now))
        assertNull(DayCardStore.snapshotIn(dir, now))
    }

    @Test fun todayIsAlwaysReadLiveEvenWithASnapshotOnDisk() {
        // A snapshot an older build wrote for today must be ignored.
        val k = java.text.SimpleDateFormat("yyyy-MM-dd", java.util.Locale.US).format(java.util.Date(now))
        java.io.File(dir, "$k.json").writeText(
            """{"talkMinutes":7,"studyMinutes":7,"streakDays":3,"talks":1,"reviews":0,"shadowTakes":0,"topics":[]}""")
        assertEquals(11, DayCardStore.resolveIn(dir, now, now) { card(now) }.talkMinutes)
    }

    @Test fun aPastDayIsSettledAndReadBack() {
        assertTrue(DayCardStore.freezeIn(dir, card(yesterday), now))
        // The logs may have been pruned since; the snapshot wins.
        assertEquals(11, DayCardStore.resolveIn(dir, yesterday, now) { card(yesterday, talk = 0) }.talkMinutes)
    }

    @Test fun anEmptyDayIsNoCard() {
        assertFalse(DayCardStore.freezeIn(dir, DayCardData(yesterday, 0, 0, 0, 0), now))
        assertNull(DayCardStore.snapshotIn(dir, yesterday))
    }

    @Test fun aSettledDayIsNeverWalkedBackwards() {
        DayCardStore.freezeIn(dir, card(yesterday, talk = 11), now)
        assertFalse(DayCardStore.freezeIn(dir, card(yesterday, talk = 4), now))
        assertEquals(11, DayCardStore.snapshotIn(dir, yesterday)?.talkMinutes)
        assertTrue(DayCardStore.freezeIn(dir, card(yesterday, talk = 12), now))
        assertEquals(12, DayCardStore.snapshotIn(dir, yesterday)?.talkMinutes)
    }
}
