package com.roro.futurevoice

import com.roro.futurevoice.audio.AudioOnset
import com.roro.futurevoice.audio.WavPcm
import com.roro.futurevoice.data.ShadowAttempt
import com.roro.futurevoice.talk.LocalAlignment
import com.roro.futurevoice.talk.ShadowScore
import com.roro.futurevoice.talk.TakeAligner
import com.roro.futurevoice.talk.TtsAlignment
import com.roro.futurevoice.talk.WordTiming
import com.roro.futurevoice.talk.WordTimings
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.PI
import kotlin.math.sin

/** Port of iOS `ShadowRhythmTests`: the grade may only judge a measured beat. */
class ShadowRhythmTest {
    private fun t(w: String, start: Int, measured: Boolean = true) = WordTiming(w, start, start + 200, measured)
    private fun steps(ws: List<String>) = ws.map { ShadowScore.DiffStep(ShadowScore.DiffOp.MATCH, it, it) }
    private val line = listOf("one", "two", "three", "four", "five")

    @Test fun measuredOnBothSidesIsGraded() {
        val r = ShadowScore.analyzeRhythm(steps(line),
            line.mapIndexed { i, w -> t(w, i * 500) }, line.mapIndexed { i, w -> t(w, 1_000 + i * 700) })
        assertEquals(100, r?.score)
        assertEquals(5, r?.words?.count { it.isMeasured })
    }

    @Test fun estimatedTargetYieldsNoRhythm() {
        val target = WordTimings.estimate(line.joinToString(" "), 2_500)
        assertTrue(target.all { !it.isMeasured })
        val r = ShadowScore.analyzeRhythm(steps(line), target, line.mapIndexed { i, w -> t(w, i * 500) })
        assertNull(r)
        assertEquals(80, ShadowScore.overallScore(80, r?.score))
    }

    @Test fun interpolatedLearnerWordIsPlacedButNotJudged() {
        val learner = line.mapIndexed { i, w -> t(w, i * 500) }.toMutableList()
        learner[2] = t("three", 1_400, measured = false)
        val r = ShadowScore.analyzeRhythm(steps(line), line.mapIndexed { i, w -> t(w, i * 500) }, learner)
        assertEquals(5, r?.words?.size)
        assertEquals(false, r?.words?.get(2)?.isMeasured)
        assertEquals(100, r?.score)
        assertEquals("all words on beat", ShadowScore.renderRhythmForPrompt(r))
    }

    @Test fun needsFourMeasuredPairs() {
        fun run(measured: Int) = ShadowScore.analyzeRhythm(steps(line),
            line.mapIndexed { i, w -> t(w, i * 500, i < measured) }, line.mapIndexed { i, w -> t(w, i * 500) })
        assertNull(run(3))
        assertNotNull(run(4))
    }

    @Test fun unmeasuredEndsDoNotPinTheNormalization() {
        val target = line.mapIndexed { i, w -> t(w, i * 500) }.toMutableList()
        target[0] = t("one", 0, measured = false)
        val learner = line.mapIndexed { i, w -> t(w, 2_000 + i * 500) }.toMutableList()
        learner[0] = t("one", 900, measured = false)
        val r = ShadowScore.analyzeRhythm(steps(line), target, learner)
        assertEquals(100, r?.score)
        assertEquals(0, r?.words?.get(1)?.targetOnsetMs)
        assertEquals(0, r?.words?.get(1)?.learnerOnsetMs)
    }

    @Test fun lateWordIsGradedAndRendered() {
        val learner = line.mapIndexed { i, w -> t(w, i * 500) }.toMutableList()
        learner[2] = t("three", 1_400)   // 400 ms late
        val r = ShadowScore.analyzeRhythm(steps(line), line.mapIndexed { i, w -> t(w, i * 500) }, learner)!!
        assertTrue(r.score < 100)
        assertEquals(0, ShadowScore.rhythmGrade(r.words[2].deviationMs))
        assertEquals("[three +400ms]", ShadowScore.renderRhythmForPrompt(r))
    }

    @Test fun timingsFromDiskDefaultToMeasured() {
        val s = ListSerializer(WordTiming.serializer())
        val out = Json.decodeFromString(s, """[{"word":"hi","startMs":0,"endMs":300}]""")
        assertEquals(true, out.first().isMeasured)
        val round = Json.decodeFromString(s, Json.encodeToString(s, listOf(WordTiming("hi", 0, 300, false))))
        assertEquals(false, round.first().isMeasured)
    }

    // iOS ShadowTranscriberTests — the headline number
    @Test fun perfectWordsOffTheBeatNoLongerScoresPerfect() {
        assertEquals(100, ShadowScore.overallScore(100, 100))
        assertEquals(79, ShadowScore.overallScore(100, 40))
    }

    @Test fun unmeasurableRhythmLeavesTheWordScoreAlone() {
        assertEquals(89, ShadowScore.overallScore(89, null))
        assertNotEquals(ShadowScore.overallScore(89, null), ShadowScore.overallScore(89, 0))
    }

    @Test fun wordsOutweighRhythm() {
        assertTrue(ShadowScore.overallScore(40, 100) < ShadowScore.overallScore(100, 40))
    }

    @Test fun attemptsSavedBeforeRhythmKeepTheirScore() {
        val old = ShadowAttempt(turnId = "t", targetText = "Soak it all in, right?", matchScore = 92)
        assertEquals(92, old.overallScore)
    }
}

/** Port of iOS `LocalAlignmentTests` (the pure half) and the `fits` guard. */
class LocalAlignmentTest {
    private fun spans(vararg p: Pair<Double, Double>) = p.map { LocalAlignment.Span(it.first, it.second) }

    @Test fun align() {
        assertEquals(listOf(0, 1, 2), LocalAlignment.align(listOf("i", "went", "there"), listOf("i", "went", "there")))
        assertEquals(listOf(0, null, 1, 2),
            LocalAlignment.align(listOf("i", "went", "there", "yesterday"), listOf("i", "there", "yesterday")))
        assertEquals(listOf(0, 2, 3), LocalAlignment.align(listOf("i", "went", "there"), listOf("i", "uh", "went", "there")))
        assertEquals(listOf(0, null, 2), LocalAlignment.align(listOf("i", "went", "there"), listOf("i", "want", "there")))
        assertEquals(listOf(null, null), LocalAlignment.align(listOf("i", "went"), emptyList()))
        assertEquals(LocalAlignment.normalized("sure"), LocalAlignment.normalized("Sure,"))
        assertEquals("좋아요", LocalAlignment.normalized("좋아요!"))
    }

    @Test fun fill() {
        val a = LocalAlignment.fill(listOf("one", "two"), listOf(0, 1), spans(0.0 to 0.5, 0.6 to 1.2), 1200)
        assertEquals(listOf(0, 600), a.map { it.startMs }); assertEquals(listOf(500, 1200), a.map { it.endMs })
        val b = LocalAlignment.fill(listOf("one", "two", "three"), listOf(0, null, 1), spans(0.0 to 0.5, 1.0 to 1.5), 1500)
        assertEquals(500, b[1].startMs); assertEquals(1000, b[1].endMs)
        assertEquals(listOf(true, false, true), b.map { it.isMeasured })
        assertEquals(2000, LocalAlignment.fill(listOf("one", "two"), listOf(0, null), spans(0.0 to 0.5), 2000).last().endMs)
        val c = LocalAlignment.fill(listOf("one", "two"), listOf(null, 0), spans(1.0 to 1.5), 1500)
        assertEquals(0, c.first().startMs); assertEquals(1000, c.first().endMs)
        val d = LocalAlignment.fill(listOf("a", "b", "c"), listOf(0, 1, 2), spans(0.5 to 1.0, 0.2 to 0.4, 1.1 to 1.4), 1400)
        d.forEachIndexed { i, w -> assertTrue(w.startMs < w.endMs); if (i > 0) assertTrue(w.startMs >= d[i - 1].endMs) }
    }

    @Test fun fits() {
        assertFalse(WordTimings.fits(listOf(WordTiming("hi", 0, 3400)), 2000))
        assertTrue(WordTimings.fits(listOf(WordTiming("hi", 0, 1950)), 2000))
        assertFalse(WordTimings.fits(emptyList(), 2000))
        assertTrue(WordTimings.fits(listOf(WordTiming("hi", 0, 1950)), 0))
        for (tail in listOf(0, 150, 400, 800)) {
            val t = LocalAlignment.fill(listOf("i", "went", "there"), listOf(0, 1, 2),
                spans(0.0 to 0.9, 1.0 to 2.0, 2.2 to 3.2), 3200 + tail)
            assertTrue(WordTimings.fits(t, 3200 + tail))
        }
        assertFalse(WordTimings.fits(listOf(WordTiming("i", 0, 900)), 4_000))
    }
}

/** Port of iOS `AudioOnsetTests` — the duet's onsets, on synthetic WAVs. */
class AudioOnsetTest {
    private fun wav(silence: Double, tone: Double, amp: Double = 0.5): WavPcm {
        val rate = 16_000
        val s = ShortArray((silence * rate).toInt()) + ShortArray((tone * rate).toInt()) { i ->
            (amp * sin(2 * PI * 220 * i / rate) * 32_000).toInt().toShort()
        }
        // Round-trip through the file format the take is stored in.
        return WavPcm.parse(WavPcm.wav(s, rate))!!
    }

    @Test fun findsOnsetAfterLeadingSilence() {
        val w = wav(0.8, 0.6)
        val onset = AudioOnset.firstVoiceOnset(w.samples, w.sampleRate)!!
        assertEquals(0.8, onset, 0.05); assertTrue(onset >= 0)
    }

    @Test fun quietTakeIsMeasuredTheSameAsALoudOne() {
        val a = wav(0.5, 0.5, 0.9); val b = wav(0.5, 0.5, 0.05)
        assertEquals(AudioOnset.firstVoiceOnset(a.samples, a.sampleRate)!!,
            AudioOnset.firstVoiceOnset(b.samples, b.sampleRate)!!, 0.02)
    }

    @Test fun speechFromTheFirstSampleReportsZero() {
        val w = wav(0.0, 0.5)
        assertEquals(0.0, AudioOnset.firstVoiceOnset(w.samples, w.sampleRate)!!, 0.01)
    }

    @Test fun silentFileHasNoOnset() {
        val w = wav(1.0, 0.0)
        assertNull(AudioOnset.firstVoiceOnset(w.samples, w.sampleRate))
    }

    @Test fun lastVoiceIsWhereTheToneStops() {
        val rate = 16_000
        val w = WavPcm(rate, wav(0.3, 0.6).samples + ShortArray(rate))
        assertEquals(0.9, AudioOnset.lastVoiceOffset(w.samples, rate)!!, 0.03)
    }

    @Test fun aStopClickAfterThePauseIsNotTheEnd() {
        val rate = 16_000
        // Speech 0.3–0.9 s, 1.4 s of silence, a 0.15 s click, silence.
        val w = WavPcm(rate, wav(0.3, 0.6).samples + ShortArray(rate * 14 / 10) +
            wav(0.0, 0.15).samples + ShortArray(rate / 5))
        assertEquals(0.9, AudioOnset.lastVoiceOffset(w.samples, rate)!!, 0.03)
    }

    @Test fun aShortLastWordRightAfterSpeechStillCounts() {
        val rate = 16_000
        // A short word 0.2 s after the speech is speech, not a click.
        val w = WavPcm(rate, wav(0.3, 0.6).samples + ShortArray(rate / 5) +
            wav(0.0, 0.15).samples + ShortArray(rate / 2))
        assertEquals(1.25, AudioOnset.lastVoiceOffset(w.samples, rate)!!, 0.03)
    }
}

/** ElevenLabs alignment → words (iOS `JapaneseShadowTimingTests`' first half). */
class TtsAlignmentTest {
    @Test fun spacedCharactersGroupOnSpaces() {
        val text = "I'm here now"
        val chars = text.map { it.toString() }
        val starts = chars.indices.map { it * 0.1 }
        val t = TtsAlignment.wordTimings(chars, starts, starts.map { it + 0.1 }, "en")
        assertEquals(listOf("I'm", "here", "now"), t.map { it.word })
        assertEquals(0, t[0].startMs); assertEquals(400, t[1].startMs)
        assertTrue(t.all { it.isMeasured })
        assertTrue(TtsAlignment.alignmentMatches(text, t))
        // A romanized alignment must never be shown as the line.
        assertFalse(TtsAlignment.alignmentMatches("그러면", listOf(WordTiming("geureomyeon", 0, 500))))
    }

    @Test fun characterAlignmentAcrossDifferentCuts() {
        val words = listOf("昨日", "は", "友達", "と", "映画", "を", "見", "に", "行き", "まし", "た")
        val heard = listOf(Triple("昨日は", 0.0, 0.6), Triple("友達と", 0.7, 1.3),
            Triple("映画を", 1.4, 2.0), Triple("見に行きました", 2.1, 3.5))
        val t = LocalAlignment.alignByCharacters(words, heard, 3600)
        assertEquals(words, t.map { it.word })
        assertEquals(0, t[0].startMs); assertEquals(700, t[2].startMs)
        assertTrue(t[2].isMeasured); assertFalse(t[1].isMeasured)
        assertTrue(t.zipWithNext().all { (a, b) -> a.endMs <= b.startMs })
        assertTrue(LocalAlignment.alignByCharacters(words, listOf(Triple("全然違う話", 0.0, 1.0)), 1000).isEmpty())
    }
}

/** The learner timeline built from the alignment, end to end on a fixture. */
class TakeTimelineTest {
    @Test fun aPerfectTakeIsTimedAndGraded() {
        val words = listOf("soak", "it", "all", "in", "right", "we", "could", "grab", "a", "coffee",
            "after", "the", "meeting")
        val truth = Json.parseToJsonElement(javaClass.getResourceAsStream("/take-align/truth.json")!!
            .bufferedReader().readText()) as kotlinx.serialization.json.JsonObject
        fun ints(k: String, f: String) = (truth[k] as kotlinx.serialization.json.JsonObject)[f]!!
            .let { it as kotlinx.serialization.json.JsonArray }.map { it.toString().toInt() }
        val on = ints("en-ref", "onsets"); val ends = ints("en-ref", "ends")
        val target = words.indices.map { WordTiming(words[it], on[it], ends[it]) }
        fun wav(n: String) = WavPcm.parse(javaClass.getResourceAsStream("/take-align/$n.wav")!!.readBytes())!!
        val take = wav("en-take0")
        val text = words.joinToString(" ")
        val steps = ShadowScore.analyze(text, text, "en").steps
        val mapped = TakeAligner.map(wav("en-ref"), target, take)!!
        val learner = TakeAligner.learnerTimings(words, target, steps, mapped,
            ((AudioOnset.lastVoiceOffset(take.samples, take.sampleRate) ?: 0.0) * 1000).toInt(), "en")
        assertEquals(words.size, learner.size)
        val r = ShadowScore.analyzeRhythm(steps, target, learner, "en")
        assertNotNull(r)
        // The take has real pauses dropped in, so it is NOT on the beat.
        assertTrue("score ${r!!.score}", r.score < 100)
    }
}
