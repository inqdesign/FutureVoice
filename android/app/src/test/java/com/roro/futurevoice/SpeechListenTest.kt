package com.roro.futurevoice

import com.roro.futurevoice.talk.PronunciationResult
import com.roro.futurevoice.talk.SpeechAnalyzer
import com.roro.futurevoice.talk.SpeechListenText
import com.roro.futurevoice.talk.SpeechPhrase
import com.roro.futurevoice.talk.SpeechPhraseMark
import com.roro.futurevoice.talk.SpeechReading
import com.roro.futurevoice.talk.SpeechReadingScore
import com.roro.futurevoice.talk.SpeechReference
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToLong

/** iOS `SpeechListenTests`: the listening reading's marks and the phrase drill's rules. */
class SpeechListenTest {
    private fun w(word: String, s: Int, e: Int) = SpeechReference.Word(word, s, e)

    @Test fun breathOnlyInsideASentence() {
        val body = "All right, everyone, come a little closer. Don't be shy."
        val words = listOf(w("all", 0, 200), w("right", 210, 400), w("everyone", 410, 900),
            w("come", 1300, 1500), w("a", 1500, 1560), w("little", 1560, 1800),
            w("closer", 1800, 2200), w("don't", 2800, 3000), w("be", 3000, 3100), w("shy", 3100, 3400))
        val tokens = SpeechListenText(body, words).paragraphs[0]
        assertEquals(10, tokens.size)
        assertTrue("a 0.4 s stop after a comma is a breath", tokens[2].breath)
        assertFalse("a stop after a full stop is not marked", tokens[6].breath)
        assertTrue("come‿a", tokens[3].runsOn)
        assertFalse("a little: next word starts with a consonant", tokens[4].runsOn)
    }

    @Test fun untimedWordTakesThePreviousEnd() {
        val text = SpeechListenText("one two three", listOf(w("one", 0, 300), w("three", 600, 900)))
        assertEquals(0.3, text.paragraphs[0][1].start, 0.001)
        assertNull(text.sentenceEnd(0.0))
    }

    @Test fun phraseAroundAStopHoldsTheNextWord() {
        val written = "Then, on a quiet Monday morning in August of nineteen eleven, while".split(" ")
        val stop = SpeechPhraseMark(5, SpeechPhraseMark.Kind.STOP, 0.6)   // after "morning"
        val r = SpeechPhrase.around(stop, written)
        assertEquals("on", written[r.first])
        assertTrue("the word after the stop is in the phrase", r.contains(6))
        assertTrue(r.last - stop.word <= 4)
    }

    @Test fun judgeFindsAStopTheFluentReadingDoesNotMake() {
        val phrase = "on a quiet Monday morning in August"
        val fluent = SpeechListenText.display(phrase, listOf(
            w("on", 0, 80), w("a", 80, 130), w("quiet", 130, 450), w("monday", 450, 830),
            w("morning", 830, 1250), w("in", 1250, 1330), w("august", 1330, 1800)))
        val stopped = SpeechListenText.display(phrase, listOf(
            w("on", 0, 90), w("a", 90, 140), w("quiet", 140, 470), w("monday", 470, 860),
            w("morning", 860, 1290), w("in", 1900, 1980), w("august", 1980, 2450)))
        val j = SpeechPhrase.judge(stopped, fluent)
        assertEquals(listOf("morning"), j.stops)
        assertFalse(j.matched)

        val same = SpeechPhrase.judge(fluent, fluent)
        assertTrue(same.matched)
        assertEquals(1.0, same.rhythm ?: 0.0, 0.001)
    }
}

/** iOS `SpeechPriceListTests`: scoring 8's price list, by area (2026-11-13). */
class SpeechPriceListTest {
    private fun score(stops: Int, slips: Int, sounds: Int?, rhythm: Double, speed: Double,
                      coverage: Double = 1.0, words: Int = 253) = SpeechReadingScore(
        version = 8, gender = "male",
        parts = SpeechReadingScore.Parts(79, 77, 98, 99, 96),
        coverage = coverage, speed = speed, rhythm = rhythm, pausesPer100 = 0.0, slipsPer100 = 0.0,
        soundAccuracy = 96, slips = slips,
        extraPauses = (0 until stops).map { SpeechReadingScore.Pause("w$it", 0.4) },
        held = emptyList(), missed = emptyList(), weakest = emptyList(), weakSounds = sounds, scriptWords = words)

    @Test fun foundersReceipt() {
        val r = score(4, 3, 11, 0.77, 0.79)
        assertEquals(4.4, r.deductions.first { it.part == SpeechReadingScore.Part.PRONUNCIATION }.points, 0.0001)
        assertEquals(76, r.total)
        assertEquals(SpeechReadingScore.Part.RHYTHM, r.focus)
    }

    @Test fun nothingLostIsAHundredAndAnythingLostIsUnder() {
        assertEquals(100, score(0, 0, 0, 0.93, 0.95).total)
        assertEquals(99, score(0, 0, 1, 0.93, 0.95).total)
    }

    @Test fun stoppingEarlyCostsEveryWordNotReached() {
        val r = score(0, 0, 0, 0.93, 0.95, coverage = 0.9, words = 200)
        assertEquals(20, r.unreadWords)
        assertEquals(80, r.total)
    }

    @Test fun eachAreaIsTwentyAndStopsAtZero() {
        // 30 stops cost 30, but the pauses area holds only 20 of the 100.
        val r = score(30, 0, 0, 0.93, 0.95)
        assertEquals(0, r.areaScore(r.deductions.first { it.part == SpeechReadingScore.Part.PAUSES }))
        assertEquals(80, r.total)
        assertEquals(SpeechReadingScore.Part.PAUSES, r.focus)
        assertEquals(listOf(SpeechReadingScore.Part.SPEED, SpeechReadingScore.Part.RHYTHM, SpeechReadingScore.Part.PAUSES,
            SpeechReadingScore.Part.ACCURACY, SpeechReadingScore.Part.PRONUNCIATION), r.deductions.map { it.part })
    }

    @Test fun foundersAreas() {
        val r = score(4, 6, 35, 0.82, 0.79)
        assertEquals(listOf(70, 80, 80, 70, 30), r.deductions.map { r.areaScore(it) })
        assertEquals(66, r.total)
    }

    @Test fun fasterThanTheNativeReadingCountsLikeSlower() {
        assertEquals(80, score(0, 0, 0, 0.93, 1.25).speedPoint)
    }

    @Test fun namesAreNeverSlips() {
        val names = SpeechAnalyzer.properNames("The police even questioned a young Pablo Picasso. And here, I said.")
        assertEquals(setOf("pablo", "picasso"), names)
    }

    /** `submit_speech_reading_take_v8` (20261113180000) recomputes the total
     *  from the counts the app sends; it refuses anything more than 1 away. */
    @Test fun theServerCheckGivesTheSameTotal() {
        fun server(stops: Int, words: Int, sounds: Int, rhythmPoint: Int, speedPoint: Int): Int {
            val lost = stops * 1.0 + words * 1.0 + sounds * 0.4 +
                max(0, 90 - rhythmPoint) * 0.5 + max(0, 85 - speedPoint) * 1.0
            if (lost == 0.0) return 100
            val left = max(0.0, 20 - max(0, 85 - speedPoint) * 1.0) + max(0.0, 20 - max(0, 90 - rhythmPoint) * 0.5) +
                max(0.0, 20 - stops * 1.0) + max(0.0, 20 - words * 1.0) + max(0.0, 20 - sounds * 0.4)
            // Postgres numeric round: halves away from zero.
            return min(99, max(0, Math.round(left).toInt()))
        }
        for (stops in listOf(0, 1, 4, 25)) for (slips in listOf(0, 3, 30)) for (sounds in listOf(0, 1, 11, 35, 60))
            for (rhythm in listOf(0.5, 0.77, 0.9, 0.95)) for (speed in listOf(0.6, 0.79, 0.85, 1.2)) {
                for (coverage in listOf(1.0, 0.8)) {
                    val r = score(stops, slips, sounds, rhythm, speed, coverage)
                    val counts = r.deductions.associate { it.part to it.count }
                    val expected = server(counts.getValue(SpeechReadingScore.Part.PAUSES),
                        counts.getValue(SpeechReadingScore.Part.ACCURACY), counts.getValue(SpeechReadingScore.Part.PRONUNCIATION),
                        r.rhythmPoint, r.speedPoint)
                    assertTrue("$stops $slips $sounds $rhythm $speed $coverage: ${r.total} vs $expected",
                        kotlin.math.abs(r.total - expected) <= 1)
                }
            }
    }
}

/** iOS `SpeechWeakSoundTests`: weak sounds are counted where they were said,
 *  once per script word (pieces overlap by two words). */
class SpeechWeakSoundTest {
    private fun word(w: String, sounds: List<Pair<String, Int>>) = PronunciationResult.Word(
        word = w, accuracy = 80, error = "None", offsetMs = 0, durationMs = 200,
        phonemes = sounds.map { PronunciationResult.Phoneme(it.first, it.second) })
    private fun piece(words: List<PronunciationResult.Word>) = PronunciationResult(
        score = 80, accuracy = 80, fluency = 80, completeness = 100, prosody = null, locale = "en-US",
        recognized = "", words = words)

    @Test fun overlapCountsOnce() {
        val script = "It was a quiet Monday morning."
        val a = piece(listOf(word("It", listOf("ɪ" to 90)), word("was", listOf("w" to 90, "z" to 0)), word("a", listOf("ə" to 90))))
        val b = piece(listOf(word("was", listOf("w" to 90, "z" to 10)), word("a", listOf("ə" to 90)), word("quiet", listOf("t" to 20)),
            word("Monday", listOf("m" to 95)), word("morning", listOf("ŋ" to 99))))
        val weak = SpeechReading.weakSounds(listOf(a, b), script)
        assertEquals(2, weak.values.sumOf { it.size })   // z in "was" once, t in "quiet"
        assertEquals(0, weak[1]?.first()?.score)           // the first reading of "was"
    }

    @Test fun aSoundTheFluentReadingAlsoMissesIsNotCounted() {
        val script = "Newspapers printed her face."
        val mine = piece(listOf(word("Newspapers", listOf("n" to 39, "u" to 35, "s" to 100, "z" to 22)),
            word("printed", listOf("t" to 20))))
        val news = SpeechReference.Word("newspapers", 0, 600, listOf(
            SpeechReference.Word.Sound("n", 46), SpeechReference.Word.Sound("u", 46),
            SpeechReference.Word.Sound("s", 100), SpeechReference.Word.Sound("z", 90)))
        val printed = SpeechReference.Word("printed", 600, 900, listOf(SpeechReference.Word.Sound("t", 95)))
        val weak = SpeechReading.weakSounds(listOf(mine), script, listOf(news, printed))
        assertEquals(listOf("z"), weak[0]?.map { it.phoneme })   // n and u spared, z still counted
        assertEquals(listOf("t"), weak[1]?.map { it.phoneme })
        assertEquals(4, SpeechReading.weakSounds(listOf(mine), script).values.sumOf { it.size })
    }
}
