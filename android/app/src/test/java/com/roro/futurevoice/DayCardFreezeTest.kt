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

    private fun dayBack(n: Int) = Calendar.getInstance().apply { timeInMillis = now; add(Calendar.DAY_OF_YEAR, -n) }.timeInMillis
    private fun endOf(day: Long) = Calendar.getInstance().apply {
        timeInMillis = day; set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0)
        set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0); add(Calendar.DAY_OF_YEAR, 1)
    }.timeInMillis
    private fun file(day: Long) = java.io.File(dir,
        java.text.SimpleDateFormat("yyyy-MM-dd", java.util.Locale.US).format(java.util.Date(day)) + ".json")

    /** iOS `freezePastDays`: every past day WITH ACTIVITY is settled — not
     *  only a day with a photo — and an empty day, and today, never are. */
    @Test fun theSweepSettlesEveryActivePastDay() {
        val active = setOf(dayBack(1), dayBack(3), dayBack(45)).map { file(it).name }.toSet()
        val asked = mutableListOf<Long>()
        val n = DayCardStore.freezePastDaysIn(dir, now) { day ->
            asked += day
            if (file(day).name in active) card(day) else DayCardData(day, 0, 0, 0, 0)
        }
        assertEquals(3, n)
        assertEquals(45, asked.size)
        assertNull(DayCardStore.snapshotIn(dir, now))
        assertNull(DayCardStore.snapshotIn(dir, dayBack(2)))
        assertEquals(11, DayCardStore.snapshotIn(dir, dayBack(3))?.talkMinutes)
    }

    /** Settled once: a record written after its day ended is skipped on its
     *  file time, without building the day again. */
    @Test fun aSettledDayIsNotAskedAgain() {
        DayCardStore.freezePastDaysIn(dir, now) { card(it) }
        val asked = mutableListOf<Long>()
        assertEquals(0, DayCardStore.freezePastDaysIn(dir, now) { asked += it; card(it, talk = 30) })
        assertTrue(asked.isEmpty())
        assertEquals(11, DayCardStore.snapshotIn(dir, yesterday)?.talkMinutes)
    }

    /** A record written WHILE its day was running (an old build froze today
     *  on open) is re-settled — upward only. */
    @Test fun aRecordWrittenMidDayIsReSettled() {
        DayCardStore.freezeIn(dir, card(yesterday, talk = 7), now)
        file(yesterday).setLastModified(endOf(yesterday) - 3_600_000)
        assertTrue(DayCardStore.needsSettling(dir, yesterday))
        DayCardStore.freezePastDaysIn(dir, now) { day -> if (day == yesterday) card(day, talk = 11) else DayCardData(day, 0, 0, 0, 0) }
        assertEquals(11, DayCardStore.snapshotIn(dir, yesterday)?.talkMinutes)

        // Logs pruned since: a smaller re-read never replaces the record.
        file(yesterday).setLastModified(endOf(yesterday) - 3_600_000)
        DayCardStore.freezePastDaysIn(dir, now) { day -> if (day == yesterday) card(day, talk = 2) else DayCardData(day, 0, 0, 0, 0) }
        assertEquals(11, DayCardStore.snapshotIn(dir, yesterday)?.talkMinutes)
    }
}
