package com.roro.futurevoice

import com.roro.futurevoice.data.AppUsageLog
import org.junit.Assert.assertEquals
import org.junit.Test

/** Two devices used on one day add up (iOS `AppUsageDeviceTests`). */
class AppUsageDeviceTest {
    @Test
    fun theDayIsTheSumOfItsDevices() {
        val map = mapOf("2026-11-18|mac" to 1800, "2026-11-18|phone" to 1200, "2026-11-17|phone" to 60)
        assertEquals(3000, AppUsageLog.deviceSum(map, "2026-11-18"))
        assertEquals(60, AppUsageLog.deviceSum(map, "2026-11-17"))
        assertEquals(0, AppUsageLog.deviceSum(map, "2026-11-19"))
    }
}
