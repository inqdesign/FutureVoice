package com.roro.futurevoice

import com.roro.futurevoice.data.AccountStatus
import com.roro.futurevoice.data.ScriptStudy
import com.roro.futurevoice.data.ScriptVoiceover
import com.roro.futurevoice.data.ScriptVoiceoverAudio
import com.roro.futurevoice.talk.WordTiming
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Speech script Study mode + "Hear it in my voice" — iOS `ScriptStudyVoiceoverTests` (3ebadf10). */
class ScriptStudyVoiceoverTest {
    private val k = ScriptStudy.Kind.EXPRESSION
    private val paras = listOf(
        "Have you ever had the perfect sentence in your head, only to watch it fall apart the moment you said it?",
        "Speaking is a skill, not just knowledge. It tends to let you down when it matters.",
        "Saying things aloud also helps them stick.",
    )

    // MARK: Span verification

    @Test fun verbatimSpansAreLocated() {
        val found = ScriptStudy.locate(listOf(
            ScriptStudy.Candidate("fall apart", k),
            ScriptStudy.Candidate("only to", ScriptStudy.Kind.GRAMMAR),
            ScriptStudy.Candidate("stick", ScriptStudy.Kind.WORD, lemma = "stick"),
        ), paras, spaced = true)
        assertEquals(listOf("fall apart", "only to", "stick"), found.map { it.text })
        assertEquals(0, found[0].paragraph)
        assertEquals(2, found[2].paragraph)
        assertEquals("fall apart", paras[0].substring(found[0].offset, found[0].offset + found[0].length))
    }

    @Test fun spanNotInTheScriptIsDropped() {
        val found = ScriptStudy.locate(listOf(
            ScriptStudy.Candidate("falls apart", k), ScriptStudy.Candidate("let you down", k)), paras, spaced = true)
        assertEquals(listOf("let you down"), found.map { it.text })
    }

    @Test fun wordBoundaryInSpacedLanguage() {
        assertTrue(ScriptStudy.locate(listOf(ScriptStudy.Candidate("art", ScriptStudy.Kind.WORD)), paras, true).isEmpty())
    }

    @Test fun caseFallbackKeepsTheScriptsSpelling() {
        val found = ScriptStudy.locate(listOf(ScriptStudy.Candidate("saying things", k)), paras, true)
        assertEquals("Saying things", found.first().text)
    }

    @Test fun overlappingSpansKeepTheFirst() {
        val found = ScriptStudy.locate(listOf(
            ScriptStudy.Candidate("let you down", k), ScriptStudy.Candidate("you down when", k)), paras, true)
        assertEquals(listOf("let you down"), found.map { it.text })
    }

    @Test fun unspacedLanguageNeedsNoBoundary() {
        val found = ScriptStudy.locate(listOf(ScriptStudy.Candidate("練習", ScriptStudy.Kind.WORD)),
            listOf("声に出して練習しよう。"), spaced = false)
        assertEquals(5, found.first().offset)
    }

    @Test fun paragraphsSplitLikeThePrompter() {
        assertEquals(listOf("A b.", "C d.", "E"), ScriptStudy.paragraphs("A b.\n\n  C d. \nE"))
    }

    // MARK: Cache keys

    @Test fun studyCacheKeyFollowsEveryInput() {
        val base = ScriptStudy.cacheKey("Hello.", "en", "ko", "b1")
        assertEquals(base, ScriptStudy.cacheKey(" Hello.\n", "en-US", "ko", "B1"))
        assertNotEquals(base, ScriptStudy.cacheKey("Hello!", "en", "ko", "b1"))
        assertNotEquals(base, ScriptStudy.cacheKey("Hello.", "en", "ja", "b1"))
        assertNotEquals(base, ScriptStudy.cacheKey("Hello.", "en", "ko", "b2"))
        assertNotEquals(base, ScriptStudy.cacheKey("Hello.", "de", "ko", "b1"))
        assertEquals(64, base.length)
    }

    @Test fun voiceoverFileKeyFollowsScriptVoiceAndSpeed() {
        val h = ScriptVoiceover.scriptHash("Hello.")
        val key = ScriptVoiceover.fileKey(h, "v1", "")
        assertNotEquals(key, ScriptVoiceover.fileKey(h, "v2", ""))
        assertNotEquals(key, ScriptVoiceover.fileKey(h, "v1", "s0.80"))
        assertNotEquals(key, ScriptVoiceover.fileKey(ScriptVoiceover.scriptHash("Hi."), "v1", ""))
    }

    // MARK: Idempotency key

    @Test fun chargeKeyShape() {
        val h = ScriptVoiceover.scriptHash("Hello.")
        val key = ScriptVoiceover.chargeKey(h, "v1")
        assertTrue(key.startsWith("sv1:"))
        assertEquals(36, key.length)
        assertTrue(key.drop(4).all { it in "0123456789abcdef" })
        assertEquals(key, ScriptVoiceover.chargeKey(ScriptVoiceover.scriptHash(" Hello.\n"), "v1"))
        assertNotEquals(key, ScriptVoiceover.chargeKey(h, "v2"))
        assertTrue(key.length in 8..200)
    }

    /** The same key iOS sends, so one voiceover is one purchase across platforms. */
    @Test fun chargeKeyIsIosByteForByte() {
        // sha256("185f8db32271fe25f561a6fc938b2e264306ec304eda518007d1764826381969|v1")
        val h = ScriptVoiceover.scriptHash("Hello")
        assertEquals("185f8db32271fe25f561a6fc938b2e264306ec304eda518007d1764826381969", h)
        assertEquals("sv1:" + ScriptVoiceover.sha("$h|v1").take(32), ScriptVoiceover.chargeKey(h, "v1"))
    }

    @Test fun shadowTurnIdIsAUuid() {
        val id = ScriptVoiceover.shadowTurnId("abc.m4a")
        assertTrue(Regex("[0-9A-F]{8}-[0-9A-F]{4}-4[0-9A-F]{3}-8[0-9A-F]{3}-[0-9A-F]{12}").matches(id))
    }

    // MARK: Price

    @Test fun chargeRounding() {
        assertEquals(2, ScriptVoiceover.chargeMinutes(40.0))
        assertEquals(3, ScriptVoiceover.chargeMinutes(41.0))
        assertEquals(3, ScriptVoiceover.chargeMinutes(60.0))
        assertEquals(4, ScriptVoiceover.chargeMinutes(80.0))
        assertEquals(5, ScriptVoiceover.chargeMinutes(80.5))
        assertEquals(0, ScriptVoiceover.chargeMinutes(0.0))
    }

    @Test fun composerQuotesThreeTimesTheLength() {
        assertEquals(3, ScriptVoiceover.quoteMinutes(60))
        assertEquals(9, ScriptVoiceover.quoteMinutes(180))
        assertEquals(15, ScriptVoiceover.quoteMinutes(300))
        assertEquals(2, ScriptVoiceover.quoteMinutes(30))
    }

    @Test fun chargeIsCappedAtTheQuote() {
        assertEquals(3, ScriptVoiceover.cappedChargeMinutes(75.0, 3))
        assertEquals(2, ScriptVoiceover.cappedChargeMinutes(30.0, 3))
        assertEquals(1, ScriptVoiceover.cappedChargeMinutes(0.1, 3))
    }

    @Test fun scriptQuoteUsesTheReadingEstimate() {
        val text = List(140) { "word" }.joinToString(" ")
        assertEquals(60, ScriptVoiceover.estimatedAudioSeconds(text, "en"))
        assertEquals(3, ScriptVoiceover.quoteMinutes(text, "en"))
    }

    @Test fun remainingMinutesCountsPoolPlusBonus() {
        val light = AccountStatus(planId = "light_monthly", subscriptionStatus = "active",
            monthlyCapSeconds = 9000, secondsUsedPeriod = 3300, bonusSeconds = 600)
        assertEquals(105, ScriptVoiceover.remainingMinutes(light))
        assertNull(ScriptVoiceover.remainingMinutes(light.copy(monthlyCapSeconds = null)))
        assertEquals(20, ScriptVoiceover.remainingMinutes(AccountStatus(secondsBalance = 1200)))
        assertNull(ScriptVoiceover.remainingMinutes(null))
    }

    // MARK: Lines

    @Test fun linesAreSentencesOrWholeParagraphs() {
        val body = "One. Two.\nThree."
        assertEquals(listOf(
            ScriptVoiceover.Line("One.", false), ScriptVoiceover.Line("Two.", true), ScriptVoiceover.Line("Three.", true)),
            ScriptVoiceover.lines(body, wholeParagraphs = false))
        assertEquals(listOf(ScriptVoiceover.Line("One. Two.", true), ScriptVoiceover.Line("Three.", true)),
            ScriptVoiceover.lines(body, wholeParagraphs = true))
    }

    // MARK: Assembly

    @Test fun joinShiftsTimingsOntoTheJoinedAudio() {
        val rate = 1000.0
        fun take(n: Int) = ShortArray(100) + ShortArray(n) { 16384 } + ShortArray(100)
        val a = take(300) to listOf(WordTiming("One.", 100, 400))
        val b = take(300) to listOf(WordTiming("Two.", 100, 400))
        val (_, timings) = ScriptVoiceoverAudio.join(listOf(a, b), rate, listOf(false, true))
        assertEquals(listOf("One.", "Two."), timings.map { it.word })
        assertEquals(100, timings[0].startMs)
        assertEquals(420.0, (timings[1].startMs - timings[0].endMs).toDouble(), 20.0)
    }
}
