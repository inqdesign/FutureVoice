package com.roro.futurevoice

import com.roro.futurevoice.data.ActivityEventLog
import com.roro.futurevoice.data.PromiseLedger
import com.roro.futurevoice.data.StudyPlan
import com.roro.futurevoice.sync.RoutineSync
import com.roro.futurevoice.sync.SyncSide
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Test

/**
 * The routine, promise days and rep times cross to an iPhone or Mac in the
 * bytes iOS writes. A payload read here and written back must come out
 * byte-identical, or the two devices push the same record to each other on
 * every pass.
 */
class RoutineSyncTest {

    /** What iOS's `StudyPlanKind` sends: sorted keys, ISO dates to the
     *  second, nil fields left out, set fields sorted. */
    private val iosPlan = """{"autoReview":false,"autoSayItAgain":false,"blocks":[""" +
        """{"anytime":true,"hour":8,"id":"6F1C2A9E-1B2C-4D3E-8F90-0A1B2C3D4E5F","kind":"talk","minute":0,"minutes":10,"remind":true,"weekdays":[1,2,3,4,5,6,7]},""" +
        """{"hour":21,"id":"0B7E5D11-2C3D-4E5F-9A0B-1C2D3E4F5A6B","kind":"review","minute":30,"minutes":20,"remind":false,"weekdays":[2,4,6]}],""" +
        """"editedAt":"2026-11-18T03:04:05Z","exceptions":{"2026-11-20":[{"hour":9,"id":"1A2B3C4D-5E6F-4A7B-8C9D-0E1F2A3B4C5D","kind":"shadow","minute":0,"minutes":2,"remind":true,"weekdays":[6]}]},""" +
        """"offWeekdays":[1,7],"restDays":["2026-11-25"],"reviewHour":21,"reviewMinute":0,"reviewMinutes":20,""" +
        """"shadowIsOwn":true,"streakSince":"2026-11-01T15:00:00Z","unitsVersion":2}"""

    @Test
    fun aRoutineFromIosGoesBackUpByteForByte() {
        val plan = assertNotNullAndGet(RoutineSync.plan(iosPlan))
        assertEquals(1_793_545_200_000L, plan.streakSince)
        assertEquals(1_794_971_045_000L, plan.editedAt)
        assertEquals(iosPlan, RoutineSync.planPayload(plan))
    }

    @Test
    fun setsGoUpSortedAndDatesToTheSecond() {
        val plan = RoutineSync.plan(iosPlan)!!
        val shuffled = plan.copy(
            offWeekdays = linkedSetOf(7, 1),
            editedAt = plan.editedAt!! + 678,
            blocks = plan.blocks.map { it.copy(weekdays = it.weekdays.reversed().toSet()) })
        assertEquals(iosPlan, RoutineSync.planPayload(shuffled))
    }

    @Test
    fun aRealRoutineBeatsASeedThenTheLaterEdit() {
        val real = RoutineSync.plan(iosPlan)!!
        val seed = real.copy(isSeed = true, editedAt = real.editedAt!! + 60_000)
        assertEquals(real, StudyPlan.later(real, seed))
        val newer = real.copy(editedAt = real.editedAt!! + 1_000)
        assertEquals(newer, StudyPlan.later(real, newer))
        // Neither stamped (both from before the stamps): kept the longest.
        val a = real.copy(editedAt = null, streakSince = 1_000L)
        val b = real.copy(editedAt = null, streakSince = 2_000L)
        assertEquals(a, StudyPlan.later(a, b))
    }

    @Test
    fun anUnstampedAndroidRoutineLosesToAnEditedIosOne() {
        val ios = iosPlan
        val android = RoutineSync.planPayload(RoutineSync.plan(iosPlan)!!.copy(editedAt = null, blocks = emptyList()))
        assertEquals(ios, RoutineSync.mergePlan(SyncSide(android, 5L, false), SyncSide(ios, 1L, false)))
    }

    @Test
    fun aPromiseDayRoundTrips() {
        val ios = """{"done":2,"keptAt":"2026-11-17T12:00:00Z","planned":3,"rule":3,"settled":true,"touched":2}"""
        val e = RoutineSync.entry(ios)!!
        assertEquals(1_794_916_800_000L, e.keptAt)
        assertEquals(ios, RoutineSync.entryPayload(e))
        val bare = """{"done":0,"planned":0,"settled":true}"""
        assertEquals(bare, RoutineSync.entryPayload(RoutineSync.entry(bare)!!))
    }

    @Test
    fun theKeptDayWinsTheEarlierKeepStanding() {
        val kept = PromiseLedger.Entry(3, 1, true, keptAt = 2_000L, touched = 1)
        val earlier = PromiseLedger.Entry(3, 0, true, keptAt = 1_000L, touched = 1)
        val missed = PromiseLedger.Entry(3, 0, true, touched = 0)
        assertEquals(kept, RoutineSync.fullerDay(kept, missed))
        assertEquals(kept, RoutineSync.fullerDay(missed, kept))
        assertEquals(earlier, RoutineSync.fullerDay(kept, earlier))
    }

    @Test
    fun repTimesUseIosKeysAndBytes() {
        val e = ActivityEventLog.Event(ActivityEventLog.Kind.SAY_IT_AGAIN, 1_794_963_723_456L)
        val same = ActivityEventLog.Event(ActivityEventLog.Kind.SAY_IT_AGAIN, 1_794_963_723_900L)
        val keys = RoutineSync.eventKeys(listOf(e, same)).map { it.first }
        assertEquals(listOf("sayItAgain|1794963723|0", "sayItAgain|1794963723|1"), keys)
        val ios = """{"at":"2026-11-18T01:02:03Z","kind":"sayItAgain"}"""
        assertEquals(ios, RoutineSync.eventPayload(e))
        assertEquals(ios, RoutineSync.eventPayload(RoutineSync.event(ios)!!))
    }

    private fun <T> assertNotNullAndGet(v: T?): T { assertNotNull(v); return v!! }
}
