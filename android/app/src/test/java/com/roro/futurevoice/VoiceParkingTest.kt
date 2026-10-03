package com.roro.futurevoice

import com.roro.futurevoice.data.VoiceParking
import com.roro.futurevoice.data.VoiceRevival
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** iOS `VoiceParking` / `VoiceRevival` rules, ported 1:1. */
class VoiceParkingTest {

    @Test fun revivalOnlyForTheParkedVoice() {
        assertEquals(VoiceRevival.Decision.PROCEED, VoiceRevival.decide("v1", null, true))
        assertEquals(VoiceRevival.Decision.PROCEED, VoiceRevival.decide(null, "v1", true))
        // A stale mark on another voice never stands in front of a call.
        assertEquals(VoiceRevival.Decision.PROCEED, VoiceRevival.decide("v2", "v1", true))
        assertEquals(VoiceRevival.Decision.REBUILD, VoiceRevival.decide("v1", "v1", true))
        assertEquals(VoiceRevival.Decision.RECORD_AGAIN, VoiceRevival.decide("v1", "v1", false))
    }

    @Test fun serverCheckIsThrottledButForcedOnSignInAndPurchase() {
        val now = 1_000_000_000L
        assertTrue(VoiceParking.shouldCheck(false, false, null, now))
        assertFalse(VoiceParking.shouldCheck(false, false, now - 60_000, now))
        assertTrue(VoiceParking.shouldCheck(false, false, now - VoiceParking.CHECK_INTERVAL_MS, now))
        assertTrue(VoiceParking.shouldCheck(true, true, now, now))
        // Known parked: only a forced check re-reads it.
        assertFalse(VoiceParking.shouldCheck(true, false, null, now))
    }

    @Test fun parkedAtDecidesTheMark() {
        assertEquals("v1", VoiceParking.nextParkedId("v1", "2026-10-01T12:00:00Z"))
        assertNull(VoiceParking.nextParkedId("v1", null))
        assertNull(VoiceParking.nextParkedId("v1", ""))
    }

    @Test fun droppedVoiceIsNotRestored() {
        assertNull(VoiceParking.restoredVoiceId("v1", "v1"))
        assertEquals("v2", VoiceParking.restoredVoiceId("v2", "v1"))
        assertEquals("v1", VoiceParking.restoredVoiceId("v1", null))
        assertNull(VoiceParking.restoredVoiceId(null, "v1"))
    }
}
