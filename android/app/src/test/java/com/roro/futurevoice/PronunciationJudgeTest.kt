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

    // A miss is explained (iOS, 2026-11-10).

    private val thTopic = com.roro.futurevoice.talk.PronunciationCourse.Topic(
        "th", "th", "think, three", listOf("θ"), "tongue between the teeth")

    @Test fun everyMissNoteSaysWhatWasMeasured() {
        val notes = com.roro.futurevoice.talk.PronunciationNotes
        val first = notes.notYet("think", "θ", null, thTopic, "I think so.", PronunciationJudge.HeardAs.Sound("s"), 41)
        assertTrue(first.contains("came out like \"s\""))
        assertTrue(first.contains("today's sound"))
        val again = notes.wordAgain("think", "θ", thTopic, null, 58, previous = 41, tries = 2)
        assertTrue(again.contains("wasn't clear"))
        assertTrue(again.contains("41 → 58"))
        assertTrue(again.contains("NOT given"))
        val whole = notes.wordAgain("Brötchen", null, thTopic, score = 44, tries = 1)
        assertTrue(whole.contains("don't name one"))
        assertTrue(!whole.contains("today's sound"))
    }

    @Test fun theLongestStopIsNamed() {
        val a = word("I", "aɪ" to 95).copy(offsetMs = 0, durationMs = 200)
        val b = word("think", "θ" to 90).copy(offsetMs = 250, durationMs = 300)
        val c = word("so", "s" to 90).copy(offsetMs = 1400, durationMs = 300)
        assertEquals("so", PronunciationJudge.pauseBefore(take(a, b, c)))
        assertEquals(null, PronunciationJudge.pauseBefore(take(a, b, c.copy(offsetMs = 600))))
    }

    // A word on its own: a sound heard as another (iOS e272f61f)

    private class Heard(val phoneme: String, val accuracy: Int, vararg val list: Pair<String, Int>)

    private fun drillWord(w: String, accuracy: Int, vararg ps: Heard) = take(
        PronunciationResult.Word(word = w, accuracy = accuracy, error = "None", offsetMs = 0, durationMs = 400,
            phonemes = ps.map { p ->
                PronunciationResult.Phoneme(p.phoneme, p.accuracy,
                    p.list.map { PronunciationResult.Phoneme.Candidate(it.first, it.second) })
            }))

    private fun drill(r: PronunciationResult, text: String, lesson: List<String> = th) =
        PronunciationJudge.verdict(r, line(text), "", lesson, "en", wordDrill = true)

    @Test fun sinkReadAsThinkIsNotYet() {
        val r = drillWord("think", 86,
            Heard("θ", 73, "s" to 100, "z" to 54, "ɪ" to 45),
            Heard("ɪ", 68, "ɪ" to 100, "æ" to 100),
            Heard("ŋ", 100, "ŋ" to 100), Heard("k", 93, "k" to 100))
        val v = drill(r, "think")
        assertTrue("sink is not think", v is Verdict.NotYet)
        assertEquals("θ", (v as Verdict.NotYet).sound)
        // The same take inside a sentence keeps the sentence rules.
        assertEquals(Verdict.Pass(90), PronunciationJudge.verdict(r, line("think"), "", th, "en"))
    }

    @Test fun shipReadAsSheepIsNotYet() {
        val r = drillWord("sheep", 71,
            Heard("ʃ", 72, "ʃ" to 100), Heard("i", 50, "ɪ" to 99, "eɪ" to 92, "ɛ" to 60),
            Heard("p", 61, "t" to 100, "d" to 85, "p" to 85))
        val v = drill(r, "sheep", listOf("i"))
        assertTrue(v is Verdict.NotYet)
        assertEquals("i", (v as Verdict.NotYet).sound)
        assertEquals(PronunciationJudge.HeardAs.Sound("ɪ"), PronunciationJudge.heardAs(r, "sheep", "i"))
    }

    @Test fun aNativeWordStillPasses() {
        // Native "thank": s on top of θ, but θ itself at 94 in the list.
        val thank = drillWord("thank", 98,
            Heard("θ", 98, "s" to 100, "θ" to 94), Heard("æ", 100, "æ" to 100),
            Heard("ŋ", 100, "ŋ" to 100), Heard("k", 85, "k" to 100))
        assertEquals(Verdict.Pass(90), drill(thank, "thank"))
        // Native "bad": m on top of b at 78 — over the swap bar.
        val bad = drillWord("bad", 96,
            Heard("b", 78, "m" to 100, "b" to 46), Heard("æ", 99, "æ" to 100), Heard("d", 100, "d" to 100))
        assertEquals(Verdict.Pass(90), drill(bad, "bad", emptyList()))
        // Native "sheep": its final p heard as g — a final stop never counts.
        val sheep = drillWord("sheep", 94,
            Heard("ʃ", 100, "ʃ" to 100), Heard("i", 98, "i" to 100),
            Heard("p", 44, "g" to 100, "k" to 93, "i" to 42))
        assertEquals(Verdict.Pass(90), drill(sheep, "sheep", emptyList()))
    }

    @Test fun aSchwaSaidAnotherWayIsNotASwap() {
        val r = drillWord("decision", 85,
            Heard("d", 92, "d" to 100), Heard("ə", 40, "ɪ" to 100), Heard("s", 90, "s" to 100))
        assertEquals(Verdict.Pass(90), drill(r, "decision", emptyList()))
    }
}
