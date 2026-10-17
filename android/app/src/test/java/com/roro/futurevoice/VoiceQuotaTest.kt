package com.roro.futurevoice

import com.roro.futurevoice.data.VoiceQuota
import com.roro.futurevoice.data.VoiceQuotaFull
import com.roro.futurevoice.talk.VoicePreset
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * iOS `VoiceQuotaTests` (2026-10-10): the server's answer when the account's
 * monthly voice allowance is spent. Its date moves every month, so it is read
 * from the body.
 */
class VoiceQuotaTest {
    @Test fun spentAllowanceCarriesItsDate() {
        val body = """{"error":"voice_quota_full","message":"…","available_at":"2026-10-12T09:24:07.000Z"}"""
        val parsed = VoiceQuota.availableAt(body)
        assertNotNull(parsed)
        assertEquals(1791797047000L, parsed!!.until)
    }

    @Test fun reservedAllowanceWithoutADateIsStillAQuotaAnswer() {
        val parsed = VoiceQuota.availableAt("""{"error":"voice_quota_reserved","message":"…","available_at":null}""")
        assertNotNull(parsed)          // a quota answer…
        assertNull(parsed!!.until)     // …that didn't say when
    }

    @Test fun otherFailuresAreNotQuotaAnswers() {
        assertNull(VoiceQuota.availableAt("""{"error":"upstream error"}"""))
        assertNull(VoiceQuota.availableAt("voice_limit_reached"))
    }

    @Test fun errorExposesTheDate() {
        val e = VoiceQuotaFull.from("""{"error":"voice_quota_full","available_at":"2026-10-12T09:24:07Z"}""")
        assertNotNull(e)
        assertEquals(1791797047000L, e!!.until)
        assertNull(VoiceQuotaFull.from("""{"error":"insufficient_credits"}"""))
    }

    @Test fun presetSlotsAreNeverAnyonesOwnVoice() {
        assertTrue(VoicePreset.isPreset("NDTYOmYEjbDIVCKB35i3"))
        assertFalse(VoicePreset.isPreset("999df508-4de5-40a7-8bd3-8c12f678c284"))
        assertFalse(VoicePreset.isPreset(null))
    }

    /** iOS `e9fcb2d`: every selectable target language speaks a Cartesia native. */
    @Test fun slotsSpeakNativeVoicesPerLanguage() {
        assertEquals("999df508-4de5-40a7-8bd3-8c12f678c284", VoicePreset.speaking("NDTYOmYEjbDIVCKB35i3", "en"))
        assertEquals("1ade29fc-6b82-4607-9e70-361720139b12", VoicePreset.speaking("NDTYOmYEjbDIVCKB35i3", "de-DE"))
        assertEquals("NDTYOmYEjbDIVCKB35i3", VoicePreset.speaking("NDTYOmYEjbDIVCKB35i3", "fr"))
        assertEquals("Lea", VoicePreset.name("NDTYOmYEjbDIVCKB35i3", "Paige", "de"))
    }
}
