package com.roro.futurevoice

import com.roro.futurevoice.data.MisheardExclusion
import com.roro.futurevoice.data.SayItAgainScript
import com.roro.futurevoice.data.WeeklyReport
import com.roro.futurevoice.talk.AxisScore
import com.roro.futurevoice.talk.GrammarIssue
import com.roro.futurevoice.talk.ScorecardMetrics
import com.roro.futurevoice.talk.Session
import com.roro.futurevoice.talk.SessionScorecard
import com.roro.futurevoice.talk.SessionSummary
import com.roro.futurevoice.talk.Turn
import com.roro.futurevoice.talk.TurnRole
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * "Misheard — exclude from scoring" (iOS `SessionStore.excludeTurnFromScoring`
 * / `excludeMishearing`): the flag, the slips quoted from the turn, the
 * grammar score's rescale, and which weekly report it voids.
 */
class MisheardExclusionTest {

    private val heard = Turn(id = "u1", role = TurnRole.USER, transcript = "I goed to the store yesterday")
    private val other = Turn(id = "u2", role = TurnRole.USER, transcript = "She don't like coffee")
    private val reply = Turn(id = "f1", role = TurnRole.FLUENT_SELF, transcript = "Oh, which store?")

    private fun axis(score: Int) = AxisScore(score, "")

    private fun session(grammar: Int = 70, issues: List<GrammarIssue>) = Session(
        id = "s", userId = "me", targetLanguage = "en", startedAt = 1_000L, endedAt = 2_000L,
        turns = listOf(heard, reply, other),
        summary = SessionSummary(
            grammarIssues = issues,
            scorecard = SessionScorecard(axis(80), axis(grammar), axis(80), axis(80))))

    private val slip1 = GrammarIssue(id = "g1", quote = "I goed", correction = "I went", note = "")
    private val slip2 = GrammarIssue(id = "g2", quote = "She don't", correction = "She doesn't", note = "")

    @Test fun flagsTheTurnAndDropsItsSlipsAndRescales() {
        val out = MisheardExclusion.excludeTurn(session(70, listOf(slip1, slip2)), "u1")!!
        assertTrue(out.turns.first { it.id == "u1" }.excludedFromScoring)
        assertFalse(out.turns.first { it.id == "u2" }.excludedFromScoring)
        assertEquals(listOf("g2"), out.summary!!.grammarIssues.map { it.id })
        // Deduction 30 × 1/2 surviving → 15 → 85.
        assertEquals(85, out.summary!!.scorecard!!.grammar.score)
        // Other axes untouched.
        assertEquals(80, out.summary!!.scorecard!!.vocabulary.score)
    }

    @Test fun removingTheOnlySlipReturnsTheScoreTo100() {
        val out = MisheardExclusion.excludeTurn(session(64, listOf(slip1)), "u1")!!
        assertEquals(100, out.summary!!.scorecard!!.grammar.score)
    }

    @Test fun aTurnWithNoSlipKeepsTheScore() {
        val out = MisheardExclusion.excludeTurn(session(70, listOf(slip2)), "u1")!!
        assertEquals(70, out.summary!!.scorecard!!.grammar.score)
        assertEquals(1, out.summary!!.grammarIssues.size)
    }

    @Test fun onlyTheLearnersUnflaggedLinesCanBeExcluded() {
        val s = session(issues = listOf(slip1))
        assertNull(MisheardExclusion.excludeTurn(s, "f1"))
        assertNull(MisheardExclusion.excludeTurn(s, "nope"))
        val once = MisheardExclusion.excludeTurn(s, "u1")!!
        assertNull(MisheardExclusion.excludeTurn(once, "u1"))
    }

    @Test fun aSlipIsTracedToItsTurnPunctuationAndCaseAside() {
        val loose = GrammarIssue(id = "g3", quote = "i GOED, to", correction = "I went to", note = "")
        val (out, turnId) = MisheardExclusion.excludeIssue(session(70, listOf(loose, slip2)), "g3")!!
        assertEquals("u1", turnId)
        assertTrue(out.turns.first { it.id == "u1" }.excludedFromScoring)
        assertEquals(listOf("g2"), out.summary!!.grammarIssues.map { it.id })
    }

    @Test fun anUntraceableSlipGoesAloneWithTheSameRescale() {
        val ghost = GrammarIssue(id = "g9", quote = "we was there", correction = "we were there", note = "")
        val (out, turnId) = MisheardExclusion.excludeIssue(session(60, listOf(ghost, slip2)), "g9")!!
        assertNull(turnId)
        assertTrue(out.turns.none { it.excludedFromScoring })
        assertEquals(listOf("g2"), out.summary!!.grammarIssues.map { it.id })
        assertEquals(80, out.summary!!.scorecard!!.grammar.score)
    }

    @Test fun normalizationMatchesIos() {
        assertEquals("don't stop me",
            MisheardExclusion.normalizedForMatch("Don't, STOP — me!"))
        assertEquals("", MisheardExclusion.normalizedForMatch(" ?! "))
        assertEquals("학교에 갔어", MisheardExclusion.normalizedForMatch("학교에 갔어."))
    }

    @Test fun theExcludedTurnLeavesTheReaders() {
        val out = MisheardExclusion.excludeTurn(session(issues = listOf(slip1)), "u1")!!
        // Scorecard metrics count only "She don't like coffee".
        assertEquals(ScorecardMetrics.compute(listOf(other)).userWordCount,
            ScorecardMetrics.compute(out.turns).userWordCount)
        // Say it again never asks them to read the misheard line.
        val lines = SayItAgainScript.build(out).map { it.text }
        assertTrue(lines.none { it.contains("goed") })
        assertTrue(lines.any { it.contains("coffee") })
    }

    @Test fun voidsTheLatestReportOnlyWhenTheTalkIsInItsWindow() {
        val older = WeeklyReport(id = "old", periodStart = 0L, periodEnd = 1_500L, generatedAt = 1L)
        val latest = WeeklyReport(id = "new", periodStart = 1_500L, periodEnd = 5_000L, generatedAt = 2L)
        val s = session(issues = emptyList())          // ended at 2_000
        assertEquals("new", MisheardExclusion.reportToVoid(listOf(latest, older), s)?.id)
        // A talk judged by the OLDER report (before its end) voids nothing.
        val early = s.copy(endedAt = 1_200L)
        assertNull(MisheardExclusion.reportToVoid(listOf(latest, older), early))
        // A talk after the latest report isn't in any report yet.
        assertNull(MisheardExclusion.reportToVoid(listOf(latest, older), s.copy(endedAt = 6_000L)))
        // Only one report: everything up to its end is its window.
        assertNotNull(MisheardExclusion.reportToVoid(listOf(older), early))
        assertNull(MisheardExclusion.reportToVoid(emptyList(), s))
    }
}
