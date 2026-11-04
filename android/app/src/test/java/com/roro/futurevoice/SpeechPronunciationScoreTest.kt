package com.roro.futurevoice

import com.roro.futurevoice.talk.SpeechAnalyzer
import org.junit.Assert.assertEquals
import org.junit.Test

/** iOS `SpeechPronunciationScoreTests` (2026-11-04): pronunciation is a quarter of the overall. */
class SpeechPronunciationScoreTest {
    @Test fun withoutPronunciationTheOldWeightingStands() {
        assertEquals(96, SpeechAnalyzer.overall(100, 100, 100, 100, 75, 1.0))
        val m = SpeechAnalyzer.analyze("one two three four.", "one two three four", "en", null)
        assertEquals(SpeechAnalyzer.SCORING_WITHOUT_PRONUNCIATION, m.scoring)
    }

    @Test fun aPerfectReadNeedsPerfectSoundsForAHundred() {
        assertEquals(99, SpeechAnalyzer.overall(100, 100, 100, 100, 100, 1.0, 96))
        assertEquals(95, SpeechAnalyzer.overall(100, 100, 100, 100, 100, 1.0, 80))
        assertEquals(100, SpeechAnalyzer.overall(100, 100, 100, 100, 100, 1.0, 100))
        val m = SpeechAnalyzer.analyze("one two three four.", "one two three four", "en", null, 80)
        assertEquals(SpeechAnalyzer.SCORING_VERSION, m.scoring)
        assertEquals(80, m.pronunciation)
    }

    @Test fun pronunciationIsScaledByCoverageLikeDelivery() {
        assertEquals(50, SpeechAnalyzer.overall(50, 100, 100, 100, 100, 0.5, 100))
    }
}
