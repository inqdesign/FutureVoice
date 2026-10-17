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

    // Reported on iOS 2026-10-17: was "Seit drei Jahre" was found inside
    // "Seit drei Jahren" — said right — and the weekly test's splice of the
    // card made the answer "Seit drei Jahrenn".
    private val jahren = "Seit drei Jahren wohne ich hier in Deutschland und habe ich"

    @Test fun aFixInsideALongerWordIsNotTheLearners() {
        assertFalse(com.roro.futurevoice.talk.SpokenWords.quotes("Seit drei Jahre", jahren, "de"))
        assertTrue(com.roro.futurevoice.talk.SpokenWords.quotes("Seit drei Jahren", jahren, "de"))
        val s = payload(jahren, "drei Jahre" to "drei Jahren").turnSuggestion(jahren, "de")
        assertNull(s)
    }

    @Test fun everySpliceSiteRespectsWordBoundariesOutsideKoreanAndJapanese() {
        assertNull(com.roro.futurevoice.talk.SpokenWords.wholeWordRange(jahren, "drei Jahre", "de"))
        assertFalse(DrillIngest.cardPair(TurnFix(was = "drei Jahre", now = "drei Jahren"), jahren, "de")
            .second.contains("Jahrenn"))
        val run = com.roro.futurevoice.data.SayItAgainScript.applyPhraseFixes(jahren,
            listOf(com.roro.futurevoice.talk.PhraseFeedback(userSaid = "drei Jahre",
                fluentAlternative = "drei Jahren", reason = "")), "de")
        assertEquals(jahren, run.text)
        assertNull(com.roro.futurevoice.data.WeeklyTestEngine.blank("Jahre", jahren, "de"))
        assertEquals("Seit drei ______ wohne ich hier in Deutschland und habe ich",
            com.roro.futurevoice.data.WeeklyTestEngine.blank("Jahren", jahren, "de"))
        // A Korean stem fix inside an eojeol is right and still lands.
        val ko = DrillIngest.cardPair(TurnFix(was = "춥어", now = "추워"), "오늘 너무 춥어서 집에 있었어. 너는?", "ko")
        assertTrue(ko.second.contains("추워서") || ko.second == "추워")
    }

    @Test fun theRepairDropsAMidWordFixAndItsCardButKeepsARealOne() {
        val bogus = TurnFix(was = "Seit drei Jahre", now = "Seit drei Jahren", why = "Plural")
        val real = TurnFix(was = "und habe ich", now = "und ich habe", why = "Wortstellung")
        val turn = com.roro.futurevoice.talk.Turn(role = com.roro.futurevoice.talk.TurnRole.USER, transcript = jahren,
            suggestion = com.roro.futurevoice.talk.TurnSuggestion(
                "Seit drei Jahren wohne ich hier und habe gelernt", "", listOf(bogus, real)))
        val session = com.roro.futurevoice.talk.Session(userId = "U", targetLanguage = "de",
            startedAt = 0, endedAt = 1, turns = listOf(turn))
        val (repaired, doomed) = DrillIngest.midWordRepair(session, "de")!!
        assertEquals(listOf("und habe ich"), repaired.turns[0].suggestion!!.fixes!!.map { it.was })
        fun card(target: String) = com.roro.futurevoice.talk.DrillCard(sourcePhrase = jahren,
            targetPhrase = target, reason = "", createdAt = 0, nextReviewAt = 0, box = 0, sourceTurnId = turn.id)
        val bogusCard = card("Seit drei Jahren")
        val good = card("und ich habe")
        assertEquals(listOf(good.id), DrillIngest.cardsWithout(listOf(bogusCard, good), doomed).map { it.id })
        assertNull(DrillIngest.midWordRepair(repaired, "de"))
        assertNull(DrillIngest.midWordRepair(session, "ko"))
        val item = com.roro.futurevoice.data.WeeklyTestEngine.rewriteItem(
            bogusCard.copy(sourcePhrase = bogus.was, sourceSessionId = session.id),
            mapOf(session.id to session), "de")
        assertFalse(item?.answer?.contains("Jahrenn") ?: false)
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
