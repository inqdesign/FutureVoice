package com.roro.futurevoice

import com.roro.futurevoice.talk.PronunciationResult
import com.roro.futurevoice.talk.ShadowScore
import org.junit.Assert.assertEquals
import org.junit.Test

/** [ShadowScore.restoringClearWords] on the founder's take of 2026-11-17 (iOS ReadBackRestoreTests). */
class ReadBackRestoreTest {
    private fun w(word: String, acc: Int?, error: String = "None") = PronunciationResult.Word(word, acc, error)

    @Test fun brandNameAzureHeardIsPutBack() {
        val reference = "Good evening, ladies and gentlemen, and welcome aboard this nawana Air flight to London."
        val heard = "Good evening ladies and gentlemen and welcome aboard to this fly to London."
        val words = listOf(w("good", 97), w("evening", 97), w("ladies", 56, "Mispronunciation"), w("and", 100),
            w("gentlemen", 97), w("and", 100), w("welcome", 97), w("aboard", 94), w("this", 97),
            w("nawana", 94), w("air", 97), w("flight", 97), w("to", 100), w("london", 91))
        val (text, _) = ShadowScore.restoringClearWords(heard, reference, words, "en")
        assertEquals("Good evening ladies and gentlemen and welcome aboard this nawana air flight to London.", text)
        assertEquals(1.0, ShadowScore.analyze(reference, text).ratio, 0.001)
    }

    @Test fun wordsAzureFaultedKeepTheReadBack() {
        val reference = "your tray table is stowed. Please switch all mobile phones and other electronic devices"
        val heard = "your tray table is stored. Please switch all mobile devices and other electric devices"
        val words = listOf(w("your", 94), w("tray", 97), w("table", 97), w("is", 94), w("stowed", 29, "Mispronunciation"),
            w("please", 100), w("switch", 100), w("all", 100), w("mobile", 97),
            w("devices", 97, "Insertion"), w("phones", null, "Omission"), w("and", 97), w("other", 97),
            w("electronic", 19, "Mispronunciation"), w("devices", 100))
        val (text, restored) = ShadowScore.restoringClearWords(heard, reference, words, "en")
        assertEquals(0, restored)
        assertEquals(heard, text)
    }

    @Test fun droppedWordIsInsertedWhereItWasSaid() {
        val (text, restored) = ShadowScore.restoringClearWords("thank you for with us.", "thank you for flying with us.",
            listOf(w("thank", 97), w("you", 97), w("for", 97), w("flying", 92), w("with", 97), w("us", 97)), "en")
        assertEquals("thank you for flying with us.", text)
        assertEquals(1, restored)
    }

    @Test fun unspacedLanguagesAreLeftAlone() {
        assertEquals(0, ShadowScore.restoringClearWords("こんにちは", "今日は", listOf(w("今日は", 97)), "ja").second)
    }
}
