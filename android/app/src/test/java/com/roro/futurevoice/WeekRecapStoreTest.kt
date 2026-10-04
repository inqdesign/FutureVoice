package com.roro.futurevoice

import com.roro.futurevoice.data.WeekRecap
import com.roro.futurevoice.data.WeekRecapStore
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * A week's deck slides up once — these pin what counts as "the same week" and
 * that the archive lists each week once (iOS `WeekRecapStoreTests`). The
 * store's two rules are pure functions over the seen end and the list, so the
 * JVM can hold them without a Context.
 */
class WeekRecapStoreTest {
    private val day = 86_400_000L
    private val hour = 3_600_000L
    private val base = 1_790_000_000_000L

    private fun recap(end: Long, talkSeconds: Int = 600, active: Boolean = true) = WeekRecap(
        start = end - 7 * day, end = end,
        activeDays = listOf(active, false, false, false, false, false, false), streak = 1,
        talkSeconds = talkSeconds, previousTalkSeconds = 0, talks = emptyList(),
        usedCount = 0, used = emptyList(), cardsCleared = 0, wordsKnown = 0, expressionsKnown = 0,
        shadowTakes = 0, scenes = 0, nowYours = emptyList(), sentencesGot = emptyList(),
        newExpressionCount = 0, newExpressions = emptyList(), newCards = 0,
        stumbles = emptyList(), shakyLines = emptyList())

    @Test fun nothingSeenYet() {
        assertFalse(WeekRecapStore.isSeen(0L, base))
    }

    @Test fun seenWeekAndOlderWeeksStaySeen() {
        assertTrue(WeekRecapStore.isSeen(base, base))
        assertTrue(WeekRecapStore.isSeen(base, base - 7 * day))
    }

    /** Flying Seoul → Berlin moves "Sat 10:00" seven hours later; moving the
     *  test from Saturday to Wednesday moves it days. Neither is a new week. */
    @Test fun shiftedEndOfTheSameWeekIsSeen() {
        assertTrue(WeekRecapStore.isSeen(base, base + 7 * hour))
        assertTrue(WeekRecapStore.isSeen(base, base + 4 * day))
    }

    @Test fun theNextWeekIsNew() {
        // One hour short of seven days: a DST change still reads as next week.
        assertFalse(WeekRecapStore.isSeen(base, base + 7 * day - hour))
        assertFalse(WeekRecapStore.isSeen(base, base + 7 * day))
    }

    @Test fun archiveListsEachWeekOnceNewestFirstAndSkipsEmptyWeeks() {
        val list = listOf(
            recap(base + 14 * day, talkSeconds = 0, active = false),   // nothing in it
            recap(base + 7 * day),
            recap(base + 7 * hour),                                    // same week, shifted
            recap(base),
        )
        val ends = WeekRecapStore.archive(list).map { it.end }
        assertEquals(2, ends.size)
        assertEquals(base + 7 * day, ends.first())
    }
}
