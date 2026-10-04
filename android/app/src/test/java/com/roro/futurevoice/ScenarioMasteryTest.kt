package com.roro.futurevoice

import com.roro.futurevoice.data.ScenarioMastery
import com.roro.futurevoice.data.ShadowAttempt
import com.roro.futurevoice.talk.Scenario
import com.roro.futurevoice.talk.ScenarioCurriculum
import com.roro.futurevoice.talk.Session
import com.roro.futurevoice.talk.Turn
import com.roro.futurevoice.talk.TurnRole
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** iOS `refreshScenarioMastery` (ebf848e), ported as [ScenarioMastery]. */
class ScenarioMasteryTest {

    private val line = ScenarioCurriculum.Item(id = "L1", text = "Could I get it without ice, please?")
    private val cur = ScenarioCurriculum(
        words = listOf(ScenarioCurriculum.Item(id = "W1", text = "receipt")),
        expressions = listOf(ScenarioCurriculum.Item(id = "E1", text = "for here")),
        shadowLines = listOf(line))

    private fun take(turnId: String, text: String, score: Int, partial: Boolean = false) = ShadowAttempt(
        turnId = turnId, targetText = text, matchScore = score,
        phraseFirst = if (partial) 0 else null, phraseLast = if (partial) 1 else null)

    @Test fun shadowLineMasteredByAWholeTakeAtTheBar() {
        assertEquals(85, ScenarioMastery.bestShadowScore(line, listOf(take("L1", line.text, 85))))
        val next = ScenarioMastery.refreshed(cur, "", { false }, { false },
            listOf(take("L1", line.text, 80)), now = 7L)
        assertNotNull(next)
        assertEquals(7L, next!!.shadowLines[0].masteredAt)
        assertFalse(next.isMastered)
    }

    @Test fun takeBelowTheBarOrPartialDoesNotCount() {
        assertNull(ScenarioMastery.refreshed(cur, "", { false }, { false },
            listOf(take("L1", line.text, 79), take("L1", line.text, 100, partial = true))))
    }

    @Test fun aTakeOpenedByTextMatchesTheLineByNormalizedText() {
        // The shadow screen ids a turn-less line by a UUID of its text.
        val t = take("SOME-UUID", "could I get it without ice please", 90)
        assertEquals(90, ScenarioMastery.bestShadowScore(line, listOf(t)))
    }

    @Test fun allThreeChaptersFinishTheBook() {
        val next = ScenarioMastery.refreshed(cur, "a receipt please, for here",
            { false }, { false }, listOf(take("L1", line.text, 95)))!!
        assertTrue(next.isMastered)
        assertEquals(3, next.masteredCount)
    }

    @Test fun wordsAndExpressionsFromTheStoresAndOnlyFlipOn() {
        val next = ScenarioMastery.refreshed(cur, "", { it == "receipt" }, { it == "for here" }, emptyList(), 5L)!!
        assertEquals(5L, next.words[0].masteredAt)
        assertEquals(5L, next.expressions[0].masteredAt)
        // Nothing new: nothing written, and stamps are never cleared.
        assertNull(ScenarioMastery.refreshed(next, "", { false }, { false }, emptyList()))
    }

    @Test fun spokenTextSkipsPracticeCallsAndOtherScenarios() {
        val sc = Scenario(id = "S1", environment = "cafe")
        fun session(scenarioId: String?, topic: String?, said: String, coached: Boolean? = null) = Session(
            userId = "u", targetLanguage = "en", startedAt = 0, topic = topic,
            originScenarioId = scenarioId, coached = coached,
            turns = listOf(Turn(role = TurnRole.USER, transcript = said)))
        val spoken = ScenarioMastery.spokenText(sc, listOf(
            session("S1", null, "Receipt"),
            session(null, "cafe", "for here"),
            session("S1", null, "tiramisu", coached = true),
            session("S2", null, "bagel")))
        assertTrue(ScenarioMastery.saidIn(spoken, "receipt"))
        assertTrue(ScenarioMastery.saidIn(spoken, "for here"))
        assertFalse(ScenarioMastery.saidIn(spoken, "tiramisu"))
        assertFalse(ScenarioMastery.saidIn(spoken, "bagel"))
        // Whole words only.
        assertFalse(ScenarioMastery.saidIn("receipts", "receipt"))
    }
}
