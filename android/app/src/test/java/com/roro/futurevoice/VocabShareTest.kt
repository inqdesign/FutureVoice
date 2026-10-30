package com.roro.futurevoice

import com.roro.futurevoice.data.CefrLevel
import com.roro.futurevoice.data.LevelBands.VocabShare
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** iOS `VocabSophisticationTests`: the vocabulary level reads the SHARE of
 *  advanced word tokens, not a count of advanced words. */
class VocabShareTest {
    private fun read(graded: Int, share: Double) =
        VocabShare.Read(graded, Math.round(graded * share / 100).toInt(), 3)

    @Test fun tooLittleSpeechReadsNoLevel() {
        assertNull(VocabShare.level(read(399, 9.0), CefrLevel.C2))
    }

    @Test fun bandsFollowTheCalibration() {
        listOf(2.1 to CefrLevel.A1, 3.3 to CefrLevel.A2, 4.5 to CefrLevel.B1, 5.5 to CefrLevel.B2)
            .forEach { (share, want) -> assertEquals("$share%", want, VocabShare.level(read(1000, share), null)?.first) }
    }

    @Test fun c1ShareWithoutPrecisionStopsAtB2() {
        val r = VocabShare.level(read(1000, 6.5), null)
        assertEquals(CefrLevel.B2, r?.first)
        assertEquals(VocabShare.Ceiling(null), r?.second)
    }

    @Test fun precisionHoldsTheTopDown() {
        val r = VocabShare.level(read(1000, 7.5), CefrLevel.C1)
        assertEquals(CefrLevel.C1, r?.first)
        assertEquals(VocabShare.Ceiling(CefrLevel.C1), r?.second)
    }

    @Test fun lowPrecisionNeverGoesBelowB2() {
        assertEquals(CefrLevel.B2, VocabShare.level(read(1000, 6.5), CefrLevel.A2)?.first)
    }

    @Test fun precisionNeverRaises() {
        val r = VocabShare.level(read(1000, 6.2), CefrLevel.C2)
        assertEquals(CefrLevel.C1, r?.first)
        assertNull(r?.second)
    }

    private val toy = mapOf("go" to CefrLevel.A1, "shop" to CefrLevel.A1, "buy" to CefrLevel.A1,
        "bread" to CefrLevel.A1, "negotiate" to CefrLevel.B2)

    @Test fun shareIsStableAsTalkGrows() {
        val talk = listOf("I go to the shop and buy bread", "I negotiate the price")
        val once = VocabShare.read(listOf(talk)) { toy[it] }
        val ten = VocabShare.read(List(10) { talk }) { toy[it] }
        assertEquals(5, once.graded)
        assertEquals(1, once.advanced)
        assertEquals(once.share, ten.share, 0.001)
        assertEquals(10, ten.talks)
    }

    @Test fun windowStopsOnceFull() {
        val talk = List(200) { "go shop buy bread" }
        val r = VocabShare.read(List(5) { talk }) { toy[it] }
        assertEquals(2, r.talks)
        assertEquals(1600, r.graded)
    }
}
