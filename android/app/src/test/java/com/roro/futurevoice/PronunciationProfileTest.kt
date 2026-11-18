package com.roro.futurevoice

import com.roro.futurevoice.data.PronunciationEntry
import com.roro.futurevoice.data.PronunciationProfile
import com.roro.futurevoice.talk.PronunciationResult
import com.roro.futurevoice.talk.SpeechPrompterTrack
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.UUID

/** iOS `PronunciationProfileTests` (14706881): the pronunciation standing is
 *  read across takes, and a word Azure never heard is not a mispronounced word. */
class PronunciationProfileTest {

    private fun word(w: String, acc: Int?, error: String = "None",
                     phonemes: List<Pair<String, Int>> = emptyList()) =
        PronunciationResult.Word(w, acc, error, 0, 0,
            phonemes.map { PronunciationResult.Phoneme(it.first, it.second) })

    private fun result(words: List<PronunciationResult.Word>, accuracy: Int = 90, locale: String = "en-US") =
        PronunciationResult(score = 85, accuracy = accuracy, fluency = 80, completeness = 100, prosody = null,
            locale = locale, recognized = "", words = words)

    private fun entry(r: List<PronunciationResult>, surface: String = "shadow") =
        PronunciationEntry.of(UUID.randomUUID().toString(), System.currentTimeMillis(), surface, r)!!

    @Test fun omissionAndInsertionAreNeverMarked() {
        val r = result(listOf(
            word("a", 0, error = "Omission"),
            word("works", 99, error = "Insertion"),
            word("think", 94, phonemes = listOf("θ" to 32, "ɪ" to 90, "ŋ" to 95)),
            word("some", 40),
        ))
        assertEquals(listOf("some", "think"), r.weakWords.map { it.word })
        assertFalse(r.words[0].isMispronounced)
        assertFalse(r.words[0].isShaky)
        assertEquals(2, r.judgedWords.size)
        assertEquals(90, r.soundScore)
    }

    @Test fun profileAveragesSoundsAcrossTakesAndNeedsSamples() {
        val entries = (0 until 3).map { i ->
            entry(listOf(result(listOf(
                word("think", 80, phonemes = listOf("θ" to 50 + i, "ɪ" to 95)),
                word("this", 85, phonemes = listOf("ð" to 40, "ɪ" to 90, "s" to 100)),
                word("only", 55),
            ))))
        }
        val p = PronunciationProfile.build(entries)
        assertEquals(3, p.takes)
        assertEquals(90, p.meanAccuracy)
        // θ: 3 samples < MIN_SAMPLES(4) → not a sound yet; ɪ: 6 samples at ~92.
        assertEquals(listOf("ɪ"), p.sounds.map { it.phoneme })
        assertTrue(p.weakSounds.isEmpty())
        // "only" low in three takes is a repeated low word.
        assertEquals(listOf("only"), p.weakWords.map { it.word })
    }

    @Test fun takeNoteNamesSoundsForEnglishAndRepeatedWordsElsewhere() {
        val en = result(listOf(
            word("think", 80, phonemes = listOf("θ" to 40, "ɪ" to 95)),
            word("thanks", 70, phonemes = listOf("θ" to 45, "æ" to 90)),
        ))
        assertEquals(listOf("θ"), PronunciationProfile.lowSounds(entry(listOf(en))).map { it.phoneme })

        // German: no phoneme names, so a word is named only when it is low
        // across takes.
        val de1 = result(listOf(word("ich", 40, phonemes = listOf("" to 40)), word("gut", 95)), locale = "de-DE")
        val de2 = result(listOf(word("ich", 45, phonemes = listOf("" to 45)), word("gut", 50)), locale = "de-DE")
        val e1 = entry(listOf(de1))
        val e2 = entry(listOf(de2))
        val profile = PronunciationProfile.build(listOf(e1, e2))
        assertTrue("an unnamed phoneme is no sample", e2.phonemes.isEmpty())
        assertEquals(listOf("ich"), profile.repeatedLowWords(e2).map { it.word })
    }

    @Test fun entryWeightsPiecesByJudgedWords() {
        val big = result((0 until 9).map { word("w$it", 80) }, accuracy = 80)
        val small = result(listOf(word("x", 20)), accuracy = 20)
        val e = entry(listOf(big, small), surface = "speech")
        assertEquals(74, e.accuracy)
        assertEquals(10, e.words.size)
    }

    @Test fun sentenceEndInTrack() {
        val t = SpeechPrompterTrack("Hello there. How are you?\" Fine", "en")
        assertTrue(t.endsSentence(1))
        assertFalse(t.endsSentence(2))
        assertTrue(t.endsSentence(4))
        assertFalse(t.endsSentence(5))
        assertFalse(t.endsSentence(99))
    }

    /** A piece with nothing judged (the stop's tail) is not a 0 for the take (iOS, 2026-11-18). */
    @Test fun pieceWithNothingJudgedIsLeftOut() {
        val heard = result(listOf(word("good", 90), word("morning", 88)), accuracy = 90)
        val tail = result(listOf(word("sunny", null, error = "Omission"), word("weekend", null, error = "Omission")), accuracy = 0)
        assertEquals(90, com.roro.futurevoice.ui.speech.SpeechTakeSession.pronunciation(listOf(heard, tail))?.first)
        assertEquals(null, com.roro.futurevoice.ui.speech.SpeechTakeSession.pronunciation(listOf(tail)))
    }
}
