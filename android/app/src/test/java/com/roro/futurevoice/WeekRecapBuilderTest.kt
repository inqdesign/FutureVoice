package com.roro.futurevoice

import com.roro.futurevoice.data.PracticeLog
import com.roro.futurevoice.data.ShadowAttempt
import com.roro.futurevoice.data.WeekRecapBuilder
import com.roro.futurevoice.talk.Carryover
import com.roro.futurevoice.talk.DrillCard
import com.roro.futurevoice.talk.Session
import com.roro.futurevoice.talk.SessionSummary
import com.roro.futurevoice.talk.Turn
import com.roro.futurevoice.talk.TurnFix
import com.roro.futurevoice.talk.TurnRole
import com.roro.futurevoice.talk.TurnSuggestion
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** The week's numbers are counted in code — each big number is the count of
 *  the list under it (iOS `WeekRecapBuilder.build`). */
class WeekRecapBuilderTest {
    private val day = 86_400_000L
    private val start = 1_000 * day
    private val end = start + 7 * day

    private fun fix(was: String, now: String) =
        TurnSuggestion(alternative = now, reason = "", fixes = listOf(TurnFix(was = was, now = now)))

    private fun session(at: Long, vararg turns: Turn, summary: SessionSummary? = null) =
        Session(userId = "u", targetLanguage = "en", startedAt = at, turns = turns.toList(), summary = summary)

    @Test fun countsFromTheWeekOnly() {
        val inWeek = session(start + day,
            Turn(role = TurnRole.FLUENT_SELF, transcript = "You can catch up on it later.", timestamp = start + day),
            Turn(role = TurnRole.USER, transcript = "I end up carrying boxes.", timestamp = start + day + 1,
                suggestion = fix("I end up", "I ended up")),
            Turn(role = TurnRole.USER, transcript = "I end up tired.", timestamp = start + day + 2,
                suggestion = fix("I end up", "I ended up")),
            summary = SessionSummary(expressionsOffered = listOf("catch up on"), carryovers = listOf(
                Carryover(sessionId = "s", source = Carryover.Source.SUGGESTION, item = "chore", quote = "q1",
                    turnId = "t", detectedAt = start + day),
                Carryover(sessionId = "s", source = Carryover.Source.DRILL_CARD, item = "Chore", quote = "q2",
                    turnId = "t", detectedAt = start + day)),
            ))
        val before = session(start - day,
            Turn(role = TurnRole.USER, transcript = "old", timestamp = start - day))
        val recap = WeekRecapBuilder.assemble(
            start = start, end = end, activeDays = List(7) { it < 2 }, streak = 2,
            talkSeconds = 600, previousTalkSeconds = 0,
            sessions = listOf(before, inWeek),
            firstSeen = mapOf("deposit" to start + 2 * day, "landlord" to start - day),
            cards = listOf(DrillCard(sourcePhrase = "a", targetPhrase = "Got this one.", reason = "",
                createdAt = start - 3 * day, lastReviewedAt = start + day, nextReviewAt = Long.MAX_VALUE, box = 5)),
            attempts = listOf(ShadowAttempt(turnId = "x", targetText = "line", matchScore = 40, createdAt = start + day)),
            log = listOf(PracticeLog.Day(drillDone = 3)),
            testScore = null, testTotal = null,
        )
        assertEquals(1, recap.talks.size)
        assertEquals("one item, strongest source kept", 1, recap.usedCount)
        assertEquals("q2", recap.used[0].quote)
        assertEquals(listOf("deposit"), recap.nowYours)
        assertEquals(listOf("Got this one."), recap.sentencesGot)
        assertEquals(1, recap.newExpressionCount)
        assertEquals("You can catch up on it later.", recap.newExpressions[0].quote)
        assertEquals(1, recap.stumbles.size)
        assertEquals(2, recap.stumbles[0].count)
        assertEquals(1, recap.shakyLines.size)
        assertEquals(3, recap.cardsCleared)
        assertTrue(recap.hasActivity)
    }
}
