package com.roro.futurevoice

import com.roro.futurevoice.data.CefrLevel
import com.roro.futurevoice.data.LevelBands
import com.roro.futurevoice.ui.ProgressBands
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * iOS `ProgressTab`'s band tables (plan 5.11): half-open lookups, an
 * off-scale value takes the last band, wall-clock pace shifted +20 before
 * banding, the vocabulary bar rising with the level. (Range × accuracy is
 * `GrammarBandTest`.)
 */
class LevelBandsTest {
    @Test fun fluency() {
        assertNull(LevelBands.fluencyBand(0.0, true))
        assertEquals(CefrLevel.A1, LevelBands.fluencyBand(59.9, true))
        assertEquals(CefrLevel.A2, LevelBands.fluencyBand(60.0, true))
        assertEquals(CefrLevel.B1, LevelBands.fluencyBand(70.0, false))   // 70 + 20 = 90
        assertEquals(CefrLevel.C2, LevelBands.fluencyBand(250.0, true))   // past the table
    }

    @Test fun expression() {
        assertNull(LevelBands.expressionBand(0.0))
        assertEquals(CefrLevel.A1, LevelBands.expressionBand(5.0))
        assertEquals(CefrLevel.A2, LevelBands.expressionBand(6.0))
        assertEquals(CefrLevel.B2, LevelBands.expressionBand(16.0))
        assertEquals(CefrLevel.C2, LevelBands.expressionBand(100.0))
    }

    @Test fun grammarScoreFallback() {
        assertNull(LevelBands.grammarBand(0))
        assertEquals(CefrLevel.A1, LevelBands.grammarBand(39))
        assertEquals(CefrLevel.A2, LevelBands.grammarBand(40))
        assertEquals(CefrLevel.B1, LevelBands.grammarBand(69))
        assertEquals(CefrLevel.B2, LevelBands.grammarBand(70))
        assertEquals(CefrLevel.C1, LevelBands.grammarBand(91))
        assertEquals(CefrLevel.C2, LevelBands.grammarBand(92))
    }

    /** Verified slips per 100 words, best first. */
    @Test fun grammarDensity() {
        fun b(v: Double) = ProgressBands.band(v, ProgressBands.grammarDensity)
        assertEquals(CefrLevel.C2, b(0.49))
        assertEquals(CefrLevel.C1, b(0.5))
        assertEquals(CefrLevel.B1, b(3.9))
        assertEquals(CefrLevel.A2, b(4.0))
        assertEquals(CefrLevel.A1, b(20.0))
    }

    @Test fun vocabularyNeedsABaselineAndARisingBar() {
        assertNull(LevelBands.vocabularyLevel(mapOf(CefrLevel.A1 to 14)))
        assertEquals(CefrLevel.A1, LevelBands.vocabularyLevel(mapOf(CefrLevel.A1 to 15)))
        // Five B1 words are under the B1 bar of 8; the A2 bar of 6 is met.
        assertEquals(CefrLevel.A2, LevelBands.vocabularyLevel(
            mapOf(CefrLevel.A1 to 10, CefrLevel.A2 to 6, CefrLevel.B1 to 5)))
        // The highest band whose bar is met wins, even past a gap.
        assertEquals(CefrLevel.C1, LevelBands.vocabularyLevel(
            mapOf(CefrLevel.A1 to 20, CefrLevel.C1 to 12)))
        // Lucky hard words alone don't mint a level: nothing met → A1.
        assertEquals(CefrLevel.A1, LevelBands.vocabularyLevel(
            mapOf(CefrLevel.A1 to 5, CefrLevel.C2 to 11)))
    }
}
