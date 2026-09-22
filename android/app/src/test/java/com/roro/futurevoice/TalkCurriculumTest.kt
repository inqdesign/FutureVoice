package com.roro.futurevoice

import com.roro.futurevoice.data.CefrLevel
import com.roro.futurevoice.data.ShadowAttempt
import com.roro.futurevoice.data.TalkCurriculum
import com.roro.futurevoice.talk.Carryover
import com.roro.futurevoice.talk.DrillCard
import com.roro.futurevoice.talk.PhraseFeedback
import com.roro.futurevoice.talk.Session
import com.roro.futurevoice.talk.SessionSummary
import com.roro.futurevoice.talk.Turn
import com.roro.futurevoice.talk.TurnRole
import com.roro.futurevoice.talk.TurnSuggestion
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * A talk book is finished when its CHAPTERS are (iOS 54, `29c8fe5`): words,
 * expressions, shadow lines and corrections all count, and a book whose
 * words are ticked but whose other chapters are untouched is NOT finished.
 */
class TalkCurriculumTest {

    private val userTurn = Turn(id = "11111111-0000-0000-0000-000000000001", role = TurnRole.USER,
        transcript = "I go to office yesterday",
        suggestion = TurnSuggestion("I went to the office yesterday.", "past tense"))
    private val fluentTurns = listOf(
        Turn(role = TurnRole.FLUENT_SELF, transcript = "Hey, good to hear you again today."),
        Turn(role = TurnRole.FLUENT_SELF,
            transcript = "Mornings are hard when the commute runs long. I usually end up reading on the train."),
        Turn(role = TurnRole.FLUENT_SELF, transcript = "Talk to you tomorrow, take care now."),
    )
    private val session = Session(
        id = "S1", userId = "u", targetLanguage = "en", startedAt = 1_000L, endedAt = 2_000L,
        turns = listOf(fluentTurns[0], userTurn, fluentTurns[1], fluentTurns[2]),
        summary = SessionSummary(
            phrasesUsed = listOf(
                PhraseFeedback(userSaid = "I go to office yesterday",
                    fluentAlternative = "I went to the office yesterday.", reason = "dup of the turn"),
                PhraseFeedback(userSaid = "it make me tired",
                    fluentAlternative = "It makes me tired.", reason = "agreement")),
            expressionsUsed = listOf("to be honest"),
            expressionsOffered = listOf("end up", "to be honest", "catch up"),
            carryovers = listOf(Carryover(sessionId = "S1",
                source = Carryover.Source.STUDYING_EXPRESSION, item = "catch up",
                quote = "", turnId = userTurn.id, detectedAt = 1_500L)),
        ),
    )

    private fun build(
        wordsKnown: Set<String> = emptySet(),
        expressionsKnown: Set<String> = emptySet(),
        attempts: List<ShadowAttempt> = emptyList(),
        cards: List<DrillCard> = emptyList(),
    ) = runBlocking {
        TalkCurriculum.build(session, CefrLevel.B1, "en",
            pickups = listOf("commute", "usually"),
            wordLastAt = { if (it in wordsKnown) 5_000L else null },
            expressionMasteredAt = { if (it in expressionsKnown) 6_000L else null },
            attempts = attempts, drillCards = cards)
    }

    @Test fun allFourChaptersArePresent() {
        val snap = build()
        assertEquals(listOf("commute", "usually"), snap.words.map { it.text })
        // Used first, then offered; duplicates collapse; a carried-over
        // phrase was already credited and is not asked for again.
        assertEquals(listOf("to be honest", "end up"), snap.expressions.map { it.text })
        assertTrue(snap.shadowLines.isNotEmpty())
        // The turn's correction and the summary's own; the summary copy of the
        // SAME sentence is not a second item.
        assertEquals(listOf("I went to the office yesterday.", "It makes me tired."),
            snap.corrections.map { it.text })
        assertEquals(TalkCurriculum.correctionId(userTurn.id), snap.corrections[0].id)
    }

    @Test fun wordsAloneDoNotFinishTheBook() {
        val snap = build(wordsKnown = setOf("commute", "usually"))
        assertEquals(2, snap.words.count { it.masteredAt != null })
        assertFalse(snap.isMastered)
    }

    @Test fun everyChapterDoneFinishesTheBook() {
        val first = build()
        val takes = first.shadowLines.map {
            ShadowAttempt(turnId = it.id, targetText = it.text, matchScore = 90, createdAt = 7_000L)
        }
        val cards = listOf(
            card("I went to the office yesterday.", turnId = userTurn.id),
            card("It makes me tired.", turnId = null))
        val snap = build(setOf("commute", "usually"), setOf("to be honest", "end up"), takes, cards)
        assertTrue(snap.isMastered)
        assertEquals(snap.totalCount, snap.masteredCount)
        assertEquals(8_000L, snap.lastStudiedAt)
    }

    @Test fun aLowTakeDoesNotMasterAShadowLine() {
        val line = build().shadowLines.first()
        val snap = build(attempts = listOf(
            ShadowAttempt(turnId = line.id, targetText = line.text, matchScore = 60)))
        assertNull(snap.shadowLines.first().masteredAt)
    }

    @Test fun aCorrectionIsMasteredByItsCardAtTheTopBox() {
        val low = build(cards = listOf(card("It makes me tired.", turnId = null, box = 3)))
        assertNull(low.corrections[1].masteredAt)
        val top = build(cards = listOf(card("It makes me tired.", turnId = null)))
        assertNotNull(top.corrections[1].masteredAt)
    }

    @Test fun correctionIdRoundTrips() {
        val id = TalkCurriculum.correctionId(userTurn.id)
        assertEquals(userTurn.id, TalkCurriculum.turnIdOfCorrection(id))
    }

    @Test fun japaneseSentenceEndsSplit() {
        assertEquals(listOf("今日は暑いね。", "水を飲んだ？"), TalkCurriculum.sentences("今日は暑いね。水を飲んだ？"))
    }

    private fun card(target: String, turnId: String?, box: Int = 5) = DrillCard(
        sourcePhrase = "", targetPhrase = target, reason = "", createdAt = 1_000L,
        lastReviewedAt = 8_000L, nextReviewAt = Long.MAX_VALUE, box = box,
        sourceSessionId = "S1", sourceTurnId = turnId)
}
