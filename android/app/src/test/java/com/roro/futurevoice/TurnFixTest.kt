package com.roro.futurevoice

import com.roro.futurevoice.data.DrillIngest
import com.roro.futurevoice.data.TalkCurriculum
import com.roro.futurevoice.talk.CarryoverDetector
import com.roro.futurevoice.talk.ConversationTurnPayload
import com.roro.futurevoice.talk.ConversationTurnPayload.FixDto
import com.roro.futurevoice.talk.ConversationTurnPayload.SuggestionDto
import com.roro.futurevoice.talk.TurnFix
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** The two-answer correction contract (iOS `TurnFixTests`, 2026-09-27). */
class TurnFixTest {
    private fun payload(alt: String, vararg fixes: Pair<String, String>) = ConversationTurnPayload(
        suggestion = SuggestionDto(alternative = alt, reason = "why",
            fixes = fixes.map { FixDto(it.first, it.second, "grammar") }))

    @Test fun wholeTurnRewriteKeepsItsFixes() {
        val said = "Yesterday I have worked until ten and my boss don't agree with me"
        val s = payload("I worked until ten yesterday, and my boss doesn't agree with me.",
            "Yesterday I have worked" to "Yesterday I worked",
            "my boss don't agree" to "my boss doesn't agree").turnSuggestion(said, "en")
        assertNotNull(s)
        assertEquals(2, s!!.fixes!!.size)
    }

    @Test fun aFixTheLearnerNeverSaidIsDropped() {
        val said = "I go to the gym three times in a week"
        val s = payload("I go to the gym three times a week.",
            "three times in a week" to "three times a week",
            "she go there" to "she goes there").turnSuggestion(said, "en")
        assertEquals(listOf("three times in a week"), s!!.fixes!!.map { it.was })
    }

    @Test fun aNoOpRewriteStillCarriesItsFixesSplicedIntoTheirTurn() {
        // The rewrite only contracts what dictation expanded — but a real
        // fix rides with it. The line becomes THEIR turn with the fix put
        // back, never the fix alone.
        val said = "I am tired because I didn't went to bed early"
        val s = payload("I'm tired because I didn't went to bed early",
            "I didn't went to bed" to "I didn't go to bed").turnSuggestion(said, "en")
        assertEquals("I am tired because I didn't go to bed early", s!!.alternative)
    }

    @Test fun aCleanTurnWithANoOpRewriteIsNothing() {
        val said = "I am really happy today"
        assertNull(payload("I'm really happy today").turnSuggestion(said, "en"))
    }

    @Test fun fixesAreNeverNullOnANewRecord() {
        // null dates a record as older than the contract — the gate must
        // always write an array, empty included.
        val s = payload("I felt really good after the gym.").turnSuggestion(
            "I feel really good after gym", "en")
        assertNotNull(s!!.fixes)
    }

    @Test fun cardPairWidensAFixTooShortToCredit() {
        val fix = TurnFix(was = "학교에 갔어", now = "학교에 갔어요", why = "")
        val (_, target) = DrillIngest.cardPair(fix, "어제 나는 학교에 갔어. 그리고 집에 왔어.")
        if (!CarryoverDetector.isCreditable(fix.now)) {
            assertTrue(target.length > fix.now.length)
        }
    }

    @Test fun cardPairKeepsACreditableFixAsWritten() {
        val fix = TurnFix(was = "my boss don't agree with me", now = "my boss doesn't agree with me")
        assertEquals(fix.was to fix.now, DrillIngest.cardPair(fix, "I think my boss don't agree with me."))
    }

    @Test fun correctionIdIndexZeroIsTheOldId() {
        val turn = "3F2504E0-4F89-11D3-9A0C-0305E82C3301"
        assertEquals(TalkCurriculum.correctionId(turn), TalkCurriculum.correctionId(turn, 0))
        assertNotEquals(TalkCurriculum.correctionId(turn, 0), TalkCurriculum.correctionId(turn, 1))
        assertNotEquals(TalkCurriculum.correctionId(turn, 1), TalkCurriculum.correctionId(turn, 2))
    }

    @Test fun repeatingTheMistakeIsNotShowingTheFix() {
        val span = CarryoverDetector.normalized("can you give me a feedback please").split(' ')
        assertFalse(CarryoverDetector.showsTheFix("give me a feedback", "give me feedback", span))
        val fixed = CarryoverDetector.normalized("can you give me feedback please").split(' ')
        assertTrue(CarryoverDetector.showsTheFix("give me a feedback", "give me feedback", fixed))
    }
}
