package com.roro.futurevoice

import com.roro.futurevoice.data.CefrLevel
import com.roro.futurevoice.data.LevelBands.VocabShare
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** iOS `VocabSophisticationTests`: the vocabulary level reads the MEAN LEVEL
 *  of the words said, minus function words, and the assessment's precision
 *  read decides above B1. */
class VocabShareTest {
    private val en = VocabShare.profiles.getValue("en")
    private fun read(mean: Double, graded: Int = 1000) = VocabShare.Read(graded, Math.round(mean * graded).toInt(), 3)
    private fun band(mean: Double, graded: Int = 1000, precision: CefrLevel? = null) =
        VocabShare.level(read(mean, graded), en, precision)

    @Test fun tooLittleSpeechReadsNoLevel() = assertNull(band(0.5, 299, CefrLevel.C2))

    @Test fun bandsFollowTheCalibration() {
        assertEquals(CefrLevel.A1, band(0.23)?.first)
        assertEquals(CefrLevel.A2, band(0.28)?.first)
        assertEquals(CefrLevel.B1, band(0.33)?.first)
        assertEquals(CefrLevel.B2, band(0.38)?.first)
        assertNull(band(0.28)?.second)
    }

    @Test fun aboveB1WithoutPrecisionSaysSo() = assertEquals(VocabShare.Ceiling(null), band(0.33)?.second)

    @Test fun precisionDecidesAboveB1() {
        assertEquals(CefrLevel.B2, band(0.33, precision = CefrLevel.B2)?.first)
        assertEquals(CefrLevel.B2, band(0.33, precision = CefrLevel.C1)?.first)
        assertEquals(CefrLevel.C1, band(0.38, precision = CefrLevel.C1)?.first)
    }

    @Test fun precisionNeverGoesBelowWhatIsMeasured() {
        assertEquals(CefrLevel.B1, band(0.33, precision = CefrLevel.A2)?.first)
        assertEquals(CefrLevel.A2, band(0.28, precision = CefrLevel.C2)?.first)
    }

    private val toy = mapOf("buy" to CefrLevel.A1, "bread" to CefrLevel.A1, "price" to CefrLevel.A1,
        "negotiate" to CefrLevel.B2, "fine" to CefrLevel.A1, "that" to CefrLevel.B2, "will" to CefrLevel.B2)

    @Test fun functionWordsDoNotCount() {
        val r = VocabShare.read(listOf(listOf("That will be fine.")), en, { it }) { toy[it] }
        assertEquals(1, r.graded)
        assertEquals(0, r.levelSum)
    }

    @Test fun meanIsStableAsTalkGrows() {
        val talk = listOf("I buy bread.", "I negotiate the price.")
        val once = VocabShare.read(listOf(talk), en, { it }) { toy[it] }
        val ten = VocabShare.read(List(10) { talk }, en, { it }) { toy[it] }
        assertEquals(4, once.graded)
        assertEquals(3, once.levelSum)
        assertEquals(once.mean, ten.mean, 0.001)
        assertEquals(10, ten.talks)
    }

    @Test fun windowStopsOnceFull() {
        val talk = List(400) { "buy bread" }
        val r = VocabShare.read(List(5) { talk }, en, { it }) { toy[it] }
        assertEquals(2, r.talks)
        assertEquals(1600, r.graded)
    }
}
