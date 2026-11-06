package com.roro.futurevoice

import com.roro.futurevoice.talk.PronunciationJudge
import com.roro.futurevoice.talk.PronunciationJudge.Verdict
import com.roro.futurevoice.talk.PronunciationResult
import com.roro.futurevoice.talk.PronunciationRound
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** The pronunciation call's verdict — the same cases as iOS
 *  `PronunciationJudgeTests` (5b9ee99d, cd5be2f3). */
class PronunciationJudgeTest {
    private val th = listOf("θ")

    private fun word(w: String, vararg ps: Pair<String, Int>, accuracy: Int? = null) =
        PronunciationResult.Word(
            word = w,
            accuracy = accuracy ?: ps.minOfOrNull { it.second } ?: 100,
            phonemes = ps.map { PronunciationResult.Phoneme(it.first, it.second) })

    private fun take(vararg words: PronunciationResult.Word) =
        PronunciationResult(score = 90, accuracy = 90, fluency = 100, completeness = 100, prosody = 89,
            locale = "en-US", words = words.toList())

    private fun line(text: String, watch: Set<String>? = null) =
        PronunciationRound.Line(text = text, focus = emptyList(), watch = watch)

    private fun verdict(r: PronunciationResult, l: PronunciationRound.Line) =
        PronunciationJudge.verdict(r, l, "", th, "en", only = l.watch)

    @Test fun aVowelOutsideTheLessonNeverStopsTheSentence() {
        val r = take(word("my", "m" to 95, "aɪ" to 90),
            word("decision", "d" to 92, "ə" to 31, "s" to 90, "ɪ" to 88, "ʒ" to 85, "ə" to 80, "n" to 95, accuracy = 80))
        assertEquals(Verdict.Pass(90), verdict(r, line("my decision")))
    }

    @Test fun theLessonSoundStillStopsIt() {
        val r = take(word("think", "θ" to 60, "ɪ" to 95, "ŋ" to 95, "k" to 95, accuracy = 85))
        val v = verdict(r, line("think")) as Verdict.NotYet
        assertEquals("think", v.word)
        assertEquals("θ", v.sound)
    }

    @Test fun aBrokenConsonantStillStopsIt() {
        val r = take(word("flight", "f" to 38, "l" to 80, "aɪ" to 90, "t" to 90, accuracy = 75))
        val v = verdict(r, line("flight")) as Verdict.NotYet
        assertEquals("f", v.sound)
    }

    @Test fun aMildConsonantDipDoesNot() {
        val r = take(word("before", "b" to 60, "ɪ" to 90, "f" to 58, "ɔɹ" to 90, accuracy = 82))
        assertEquals(Verdict.Pass(90), verdict(r, line("before")))
    }

    @Test fun missedWordsListsEveryMiss() {
        val r = take(word("think", "θ" to 55, accuracy = 80),
            word("three", "θ" to 62, "ɹ" to 90, "i" to 90, accuracy = 85),
            word("thank", "θ" to 92, accuracy = 92))
        assertEquals(listOf("think", "three"),
            PronunciationJudge.missedWords(r, line("think three thank"), "", th, "en"))
    }

    @Test fun aRetryIsJudgedOnlyOnWhatMissedBefore() {
        val r = take(word("think", "θ" to 90, accuracy = 90), word("thank", "θ" to 60, accuracy = 85))
        assertEquals(Verdict.Pass(90), verdict(r, line("think thank", watch = setOf("think"))))
        assertEquals("thank", (verdict(r, line("think thank")) as Verdict.NotYet).word)
    }

    @Test fun aWatchedWordThatStillMissesIsNamedAgain() {
        val r = take(word("think", "θ" to 50, accuracy = 80), word("thank", "θ" to 90, accuracy = 90))
        val v = verdict(r, line("think thank", watch = setOf("think")))
        assertTrue(v is Verdict.NotYet && v.word == "think")
    }

    @Test fun aWordRightAloneIsPracticedWithItsNeighbours() {
        assertEquals("I'd rather walk", PronunciationJudge.flowText("rather", "I'd rather walk than drive."))
        assertEquals("This is my", PronunciationJudge.flowText("This", "This is my mother."))
        assertEquals("is my mother", PronunciationJudge.flowText("mother", "This is my mother."))
        assertEquals("Not that", PronunciationJudge.flowText("that", "Not that."))
    }
}
