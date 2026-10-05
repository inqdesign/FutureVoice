package com.roro.futurevoice

import com.roro.futurevoice.data.SpeechGenre
import com.roro.futurevoice.data.SpeechLibrary
import com.roro.futurevoice.talk.PrompterMotion
import com.roro.futurevoice.talk.SpeechAnalyzer
import com.roro.futurevoice.talk.SpeechPrompterTrack
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.floor
import kotlin.random.Random

/** iOS `SpeechTests.swift` (HEAD `8f135c24`), test for test. */
class SpeechAnalyzerTest {
    @Test fun paceInsideBandIsFullMarks() {
        assertEquals(100, SpeechAnalyzer.paceScore(140, 120..160))
        assertEquals(0, SpeechAnalyzer.paceScore(0, 120..160))
        assertEquals(80, SpeechAnalyzer.paceScore(176, 120..160))
    }

    @Test fun sentenceBreaksExcludeTheLastSentence() {
        assertEquals(2, SpeechAnalyzer.sentenceBreaks("One. Two! Three?"))
        assertEquals(1, SpeechAnalyzer.sentenceBreaks("Wait... what?"))
        assertEquals(1, SpeechAnalyzer.sentenceBreaks("音は波です。耳に届きます。"))
    }

    @Test fun fillersAreCountedAndRemoved() {
        val said = "So um sound is uh a wave"
        assertEquals(2, SpeechAnalyzer.countFillers(said, "So sound is a wave.", "en"))
        assertEquals("So sound is a wave", SpeechAnalyzer.removingFillers(said, "en"))
        assertEquals(2, SpeechAnalyzer.countFillers("えっと音はえー波です", "音は波です", "ja"))
    }

    @Test fun fillerInTheScriptIsNotTheReadersFault() {
        assertEquals(0, SpeechAnalyzer.countFillers("Er hat hm gesagt", "Er hat hm gesagt.", "de"))
    }

    @Test fun perfectReadScoresHigh() {
        val env = SpeechAnalyzer.Envelope(0.0, 4.0, listOf(0.4),
            listOf(SpeechAnalyzer.Phrase(-20f, -21f), SpeechAnalyzer.Phrase(-20f, -22f)))
        val m = SpeechAnalyzer.analyze("Sound is a wave. It travels through the air.",
            "Sound is a wave it travels through the air", "en", env)
        assertEquals(100, m.accuracy)
        assertEquals(1, m.breaks)
        assertEquals(1, m.pausesAtBreaks)
        assertEquals(0, m.fillers)
        assertTrue(m.missed.isEmpty())
        assertEquals(135, m.rate)
        assertTrue(m.overall >= 95)
    }

    @Test fun skippedWordsAreListedInScriptOrder() {
        val m = SpeechAnalyzer.analyze("Sound is a wave of tiny changes in pressure.",
            "Sound is a wave in pressure", "en", null)
        assertEquals(listOf("of tiny changes"), m.missed)
        assertTrue(m.accuracy < 100)
    }

    @Test fun stallsCostThePauseScore() {
        val calm = SpeechAnalyzer.Envelope(0.0, 3.0, listOf(0.5, 0.5), emptyList())
        val stalled = SpeechAnalyzer.Envelope(0.0, 6.0, listOf(0.5, 2.5), emptyList())
        val a = SpeechAnalyzer.analyze("One. Two. Three.", "one two three", "en", calm)
        val b = SpeechAnalyzer.analyze("One. Two. Three.", "one two three", "en", stalled)
        assertEquals(100, a.pauseScore)
        assertEquals(1, b.hesitations)
        assertTrue(b.pauseScore < a.pauseScore)
    }

    @Test fun fadingAtSentenceEndsCostsSteadiness() {
        assertEquals(100, SpeechAnalyzer.steadinessScore(listOf(
            SpeechAnalyzer.Phrase(-20f, -21f), SpeechAnalyzer.Phrase(-21f, -22f))))
        assertTrue(SpeechAnalyzer.steadinessScore(listOf(
            SpeechAnalyzer.Phrase(-20f, -32f), SpeechAnalyzer.Phrase(-21f, -33f))) < 50)
    }

    @Test fun envelopeFindsPausesBetweenPhrases() {
        val levels = List(100) { 0.5f } + List(50) { 0.001f } + List(100) { 0.5f }
        val env = SpeechAnalyzer.envelope(levels, 0.01)
        assertNotNull(env)
        assertEquals(1, env!!.silences.size)
        assertEquals(0.5, env.silences.first(), 0.01)
        assertEquals(2.5, env.speakingSeconds, 0.01)
        assertEquals(2, env.phrases.size)
    }

    @Test fun plannedLengthFollowsTheLanguagesPace() {
        assertEquals(140, SpeechLibrary.plannedUnits(60, "en"))
        assertEquals(570, SpeechLibrary.plannedUnits(120, "ko"))
        assertEquals(9, SpeechLibrary.units("음, 소리는 파동입니다.", "ko"))
    }

    @Test fun everyTargetHasABundledScript() {
        for (code in listOf("en", "ko", "ja", "de")) {
            val script = SpeechLibrary.builtIn(code)
            assertNotNull(code, script)
            val seconds = SpeechLibrary.estimatedSeconds(script!!.body, code)
            assertTrue("$code: ${seconds}s", seconds in 45..95)
        }
    }
}

class SpeechPrompterTrackTest {
    @Test fun followsTheVoiceForward() {
        val track = SpeechPrompterTrack("Sound is a wave. It travels through the air as tiny changes in pressure.", "en")
        var cursor = track.advance(0, "sound is a")
        assertEquals(3, cursor)
        cursor = track.advance(cursor, "sound is a wave it travels through")
        assertEquals(7, cursor)
    }

    @Test fun nothingNewMeansNoMove() {
        val track = SpeechPrompterTrack("Sound is a wave. It travels through the air.", "en")
        assertEquals(4, track.advance(4, "hello there"))
        assertEquals(0, track.advance(0, ""))
    }

    @Test fun doesNotJumpPastTheWindow() {
        val filler = List(40) { "and then" }.joinToString(" ")
        val track = SpeechPrompterTrack("Start here. $filler the very distant ending words", "en")
        assertEquals(0, track.advance(0, "the very distant ending words"))
    }

    @Test fun koreanFollowsBySyllable() {
        val track = SpeechPrompterTrack("소리는 파동입니다. 공기의 압력이 높아졌다 낮아집니다.", "ko")
        val cursor = track.advance(0, "소리는파동 입니다 공기 의")
        assertEquals("공기의", track.words[cursor - 1].text)
    }

    @Test fun japaneseCutsIntoPieces() {
        val track = SpeechPrompterTrack("音は波です。空気の圧力が上がったり下がったりします。", "ja")
        assertTrue(track.words.size > 3)
        assertEquals("音は波です。空気の圧力が上がったり下がったりします。", track.words.joinToString("") { it.text })
    }

    @Test fun paragraphsSurvive() {
        assertEquals(2, SpeechPrompterTrack("First paragraph.\n\nSecond one.", "en").paragraphs.size)
    }
}

class SpeechKoreanFollowTest {
    private val passage = """
여러분, 오늘 하품 몇 번 하셨나요? 이 이야기를 듣다 보면 아마 한 번 더 하시게 될 겁니다.

하품은 옮습니다. 옆 사람이 하품하는 걸 보면 나도 모르게 따라 하게 되죠. 실제로 한 실험에서는 참가자의 절반 가까이가 하품을 따라 했습니다.
""".trim()
    private val track = SpeechPrompterTrack(passage, "ko")
    private fun word(cursor: Int) = track.words[maxOf(0, cursor - 1)].text

    @Test fun followsKoreanWithRecognizerSpacing() {
        var c = track.advance(0, "여러분 오늘 하품 몇번 하셨나요")
        assertEquals("하셨나요?", word(c))
        c = track.advance(c, "여러분 오늘 하품 몇번 하셨나요 이 이야기를 듣다보면 아마")
        assertEquals("아마", word(c))
    }

    @Test fun oneWrongSyllableInsideDoesNotStopIt() {
        val start = track.advance(0, "아마 한 번 더 하시게 될 겁니다")
        val next = track.advance(start, "아마 한 번 더 하시게 될 겁니다 하품은 옴습니다 옆 사람이 하품하는")
        assertEquals("하품하는", word(next))
    }

    @Test fun unsureLastSyllableIsTolerated() {
        val start = track.advance(0, "아마 한 번 더 하시게 될 겁니다")
        val next = track.advance(start, "아마 한 번 더 하시게 될 겁니다 하품은 옮습니다 옆 사람이 하ㅍ")
        assertEquals("하품하는", word(next))
    }

    @Test fun doesNotJumpFarOnACommonShortRun() {
        assertTrue(track.advance(0, "하품이") < 12)
    }
}

class PrompterMotionTest {
    @Test fun followingIsContinuousUnderBurstyReports() {
        val m = PrompterMotion()
        val line = 44f; val wordsPerLine = 6.0; val wps = 3.5
        m.plannedPace = line * (wps / wordsPerLine).toFloat()
        fun spot(words: Double): Pair<Float, Float> {
            val l = floor(words / wordsPerLine)
            val across = (words - l * wordsPerLine) / wordsPerLine
            return (l * line + across * line).toFloat() to (l * line).toFloat()
        }
        m.setTarget(0f, 0f, line)
        m.snap()
        val rng = Random(7)
        var nextReport = 0.6
        val dt = 1.0 / 60
        var minSpeed = Float.MAX_VALUE; var maxLag = 0f; var maxLead = -1000f
        var t = 0.0
        while (t < 20) {
            t += dt
            if (t >= nextReport) {
                val (y, top) = spot(maxOf(0.0, (t - 0.6) * wps))
                m.setTarget(y, top, line)
                nextReport = t + 0.5 + rng.nextDouble() * 0.6
            }
            m.step(dt.toFloat(), PrompterMotion.Input(true, true, 1f, true, false))
            if (t > 3) {
                minSpeed = minOf(minSpeed, m.velocity)
                val (truth, top) = spot(t * wps)
                maxLag = maxOf(maxLag, (truth - m.position) / line)
                maxLead = maxOf(maxLead, (m.position - top) / line)
            }
        }
        assertTrue("the text stalled", minSpeed > m.plannedPace * 0.25f)
        assertTrue("fell too far behind", maxLag < 1.6f)
        assertTrue("the line being read went above the top", maxLead <= 1.0001f)
    }

    @Test fun stopsWhenTheReaderStops() {
        val m = PrompterMotion()
        m.plannedPace = 25f
        m.setTarget(0f, 0f, 44f); m.snap()
        repeat(120) { m.step(1f / 60, PrompterMotion.Input(true, true, 1f, true, false)) }
        repeat(90) { m.step(1f / 60, PrompterMotion.Input(true, true, 1f, false, false)) }
        assertTrue(m.velocity < 1)
    }

    @Test fun holdStopsTheSteadyScroll() {
        val m = PrompterMotion()
        m.plannedPace = 30f
        repeat(60) { m.step(1f / 60, PrompterMotion.Input(true, false, 1f, false, false)) }
        assertTrue(m.velocity > 20)
        repeat(90) { m.step(1f / 60, PrompterMotion.Input(true, false, 1f, false, true)) }
        assertTrue(m.velocity < 1)
    }
}

class SpeechOwnScriptTest {
    @Test fun defaultTitleIsTheFirstSentence() {
        assertEquals("Good evening everyone",
            SpeechLibrary.defaultTitle("Good evening everyone. Tonight I want to talk."))
        assertEquals("안녕하세요", SpeechLibrary.defaultTitle("안녕하세요. 오늘은"))
        assertTrue(SpeechLibrary.defaultTitle("word ".repeat(30)).endsWith("…"))
    }

    @Test fun ownIsNotOfferedToTheWriter() {
        assertFalse(SpeechGenre.writable.contains(SpeechGenre.OWN))
        assertEquals(5, SpeechGenre.writable.size)
    }
}
