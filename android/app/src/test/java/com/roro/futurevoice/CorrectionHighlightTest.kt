package com.roro.futurevoice

import com.roro.futurevoice.talk.SpokenWords
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * iOS `highlightedCorrection` (plan 5.4) — what a correction card lights.
 * iOS has no unit test for it; these pairs follow its two paths line by line:
 * LCS over `spokenWords` folded onto display tokens for a spaced language,
 * LCS over letters for Japanese.
 */
class CorrectionHighlightTest {
    private fun lit(alt: String, said: String, lang: String = "en"): List<String> {
        val text = SpokenWords.displayText(alt, lang)
        return SpokenWords.changedRanges(alt, said, lang).map { text.substring(it.first, it.last + 1) }
    }

    /** Dictation expands contractions; "I'm" against "I am" is no mistake. */
    @Test fun aContractionTheTranscriberExpandedLightsNothing() {
        assertEquals(emptyList<String>(), lit("I'm building it", "I am building it"))
        assertEquals(emptyList<String>(), lit("I’m building it.", "i am building it"))
    }

    @Test fun onlyTheRealFixLights() {
        assertEquals(listOf("going", "the"), lit("I'm going to the office", "I am go to office"))
    }

    @Test fun punctuationIsNeverLit() {
        assertEquals(listOf("went"), lit("Well — I went there", "well I go there"))
    }

    @Test fun koreanLightsTheWordThatChanged() {
        assertEquals(listOf("학교에"), lit("어제 학교에 갔어", "어제 학교 갔어", "ko"))
    }

    /** くさ[かっ]た — the few characters it is, not the whole segment. */
    @Test fun japaneseLightsCharacters() {
        assertEquals(listOf("かっ"), lit("面倒くさかった", "面倒くさいでした", "ja"))
        assertEquals(emptyList<String>(), lit("はい、行きます。", "はい行きます", "ja"))
        assertEquals("はい、行きます。", SpokenWords.displayText("はい、行きます。", "ja"))
    }
}
