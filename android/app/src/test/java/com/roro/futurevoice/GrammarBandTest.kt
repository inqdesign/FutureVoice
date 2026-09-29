package com.roro.futurevoice

import com.roro.futurevoice.data.CefrLevel
import com.roro.futurevoice.ui.GrammarCeiling
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** iOS `GrammarBandTests` — range × accuracy, the lower wins. */
class GrammarBandTest {
    private fun band(slips: Double, score: Int = 0, scored: Int = 3,
                     range: CefrLevel? = null, vocab: CefrLevel? = null) =
        GrammarCeiling.band(scored, slips, score, range, vocab)

    @Test fun simpleAccurateSpeechReadsItsRangeNotC2() {
        val r = band(0.0, score = 96, range = CefrLevel.A2)
        assertEquals(CefrLevel.A2, r?.first)
        assertEquals(GrammarCeiling.Range(CefrLevel.A2), r?.second)
    }

    @Test fun rangeIsACeilingNotAFloor() {
        val r = band(6.0, range = CefrLevel.C1)
        assertEquals(CefrLevel.A2, r?.first)
        assertNull(r?.second)
    }

    @Test fun accurateWideSpeechReadsHigh() {
        val r = band(0.7, range = CefrLevel.C1)
        assertEquals(CefrLevel.C1, r?.first)
        assertNull(r?.second)
    }

    @Test fun legacyTalksAreCappedByVocabulary() {
        val r = band(0.0, score = 96, vocab = CefrLevel.A1)
        assertEquals(CefrLevel.A2, r?.first)
        assertEquals(GrammarCeiling.Vocabulary(CefrLevel.A2), r?.second)
        assertEquals(CefrLevel.C2, band(0.0, score = 96, vocab = CefrLevel.C2)?.first)
    }

    @Test fun rangeWinsOverVocabularyStandIn() {
        assertEquals(CefrLevel.B1, band(0.0, score = 96, range = CefrLevel.B1, vocab = CefrLevel.A1)?.first)
    }

    @Test fun noEvidenceIsNoBand() {
        assertNull(band(0.0, score = 0, range = CefrLevel.A1))
        assertNull(band(0.0, score = 90, scored = 0))
    }
}
