package com.roro.futurevoice

import com.roro.futurevoice.data.PracticeLog
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** Two devices practising on one day add up (iOS `PracticeLogDeviceTests`). */
class PracticeLogDeviceTest {
    private fun day(drill: Int, done: Int = 0, scenes: Int = 0) =
        PracticeLog.Day(drillReps = drill, drillDone = done, sceneReps = scenes)

    @Test
    fun twoDevicesOnOneDayAddUp() {
        val devices = mapOf("2026-11-18|mac" to day(27, 5), "2026-11-18|phone" to day(10, 2),
            "2026-11-19|mac" to day(1))
        val d = PracticeLog.combined(day(27, 5), devices, "2026-11-18")!!
        assertEquals(37, d.drillReps)
        assertEquals(7, d.drillDone)
    }

    @Test
    fun aLegacyOnlyDayKeepsItsCount() {
        val d = PracticeLog.combined(day(12, scenes = 1), emptyMap(), "2026-11-01")!!
        assertEquals(12, d.drillReps)
        assertEquals(1, d.sceneReps)
        assertNull(PracticeLog.combined(null, emptyMap(), "2026-11-01"))
    }

    @Test
    fun aRepAddsToItsKind() {
        val d = PracticeLog.adding(PracticeLog.adding(PracticeLog.Day(), PracticeLog.Kind.SHADOW, true),
            PracticeLog.Kind.SCENE, false)
        assertEquals(1, d.shadowReps); assertEquals(1, d.shadowDone); assertEquals(1, d.sceneReps)
    }
}
