package com.roro.futurevoice

import com.roro.futurevoice.data.LearnerGender
import com.roro.futurevoice.sync.SYNCED_DEFAULTS_KEYS
import com.roro.futurevoice.sync.SyncKind
import com.roro.futurevoice.sync.SyncSchema
import com.roro.futurevoice.talk.LanguageLines
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** The learner's gender for French and Spanish sentences (iOS
 *  `LearnerGenderTests`, 2026-11-13). */
class LearnerGenderTest {

    /** Only clearly low or clearly high voices are guessed. */
    @Test fun pitchGuessLeavesTheOverlapAlone() {
        assertEquals(LearnerGender.MALE, LearnerGender.guess(110.0))
        assertEquals(LearnerGender.FEMALE, LearnerGender.guess(220.0))
        assertNull(LearnerGender.guess(165.0))
        assertNull(LearnerGender.guess(150.0))
        assertNull(LearnerGender.guess(185.0))
    }

    @Test fun onlyFrenchAndSpanishCare() {
        assertTrue(LearnerGender.matters("fr"))
        assertTrue(LearnerGender.matters("es"))
        for (lang in listOf("en", "de", "ko", "ja", "zh")) {
            assertFalse(lang, LearnerGender.matters(lang))
            assertEquals(lang, "", LanguageLines.genderLine(lang, asFutureSelf = true, gender = LearnerGender.FEMALE))
            assertNull(lang, LanguageLines.genderAboutLine(lang, LearnerGender.FEMALE))
        }
    }

    @Test fun theFutureSelfTakesTheirGender() {
        val fem = LanguageLines.genderLine("fr", asFutureSelf = true, gender = LearnerGender.FEMALE)
        assertTrue(fem.contains("a woman") && fem.contains("contente"))
        val masc = LanguageLines.genderLine("es", asFutureSelf = true, gender = LearnerGender.MALE)
        assertTrue(masc.contains("a man") && masc.contains("cansado"))
        val unsaid = LanguageLines.genderLine("fr", asFutureSelf = true, gender = LearnerGender.UNSAID)
        assertTrue(unsaid.contains("prefer not to say"))
        // Nothing on file: the measured neutral-until-shown line, unchanged.
        assertTrue(LanguageLines.genderLine("fr", asFutureSelf = true, gender = null).contains("once they show it"))
        assertTrue(LanguageLines.spanishGuard("es", asFutureSelf = true, accentId = null, gender = null)
            .contains("SPANISH, GENDER"))
    }

    /** A cast person hears it only as how to talk ABOUT the learner. */
    @Test fun aCastPersonOnlyHearsAKnownGender() {
        assertTrue(LanguageLines.genderLine("fr", asFutureSelf = false, gender = LearnerGender.FEMALE).contains("THE LEARNER"))
        assertEquals("", LanguageLines.genderLine("fr", asFutureSelf = false, gender = LearnerGender.UNSAID))
        assertEquals("", LanguageLines.genderLine("es", asFutureSelf = false, gender = null))
        assertFalse(LanguageLines.spanishGuard("es", asFutureSelf = false, accentId = null, gender = null)
            .contains("GENDER"))
    }

    @Test fun freeTalkCarriesItAsAFact() {
        assertTrue(LanguageLines.genderAboutLine("es", LearnerGender.FEMALE)!!.contains("a woman"))
        assertTrue(LanguageLines.genderAboutLine("fr", null)!!.contains("not known"))
    }

    /** Older builds must freeze the new settings, not tombstone them. */
    @Test fun theSettingIsStampedAboveOlderBuilds() {
        assertEquals(2, SyncSchema.stamp(SyncKind.DEFAULTS, LearnerGender.VALUE_KEY))
        assertEquals(2, SyncSchema.stamp(SyncKind.DEFAULTS, LearnerGender.SOURCE_KEY))
        assertEquals(1, SyncSchema.stamp(SyncKind.DEFAULTS, "futurevoice.speechSpeed"))
        assertTrue(LearnerGender.VALUE_KEY in SYNCED_DEFAULTS_KEYS)
        // This build reads its own gender records at 2…
        assertFalse(2 > SyncSchema.readable(SyncKind.DEFAULTS, LearnerGender.VALUE_KEY))
        assertFalse(2 > SyncSchema.readable(SyncKind.DEFAULTS, LearnerGender.SOURCE_KEY))
        // …and still freezes everything else stamped 2, an iOS speech take first.
        assertTrue(2 > SyncSchema.readable(SyncKind.SPEECH_TAKE, "take-1"))
        assertTrue(2 > SyncSchema.readable(SyncKind.DEFAULTS, "futurevoice.speechSpeed"))
    }
}
