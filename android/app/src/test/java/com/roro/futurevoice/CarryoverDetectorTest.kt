package com.roro.futurevoice

import com.roro.futurevoice.talk.Carryover
import com.roro.futurevoice.talk.CarryoverDetector
import com.roro.futurevoice.talk.DrillCard
import com.roro.futurevoice.talk.Turn
import com.roro.futurevoice.talk.TurnRole
import com.roro.futurevoice.talk.TurnSuggestion
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * iOS `CarryoverDetectorTests` (1.1.1), case for case — plan 5.6. The feature
 * rests on never claiming a learner said something they didn't, so the
 * false-positive cases matter more than the positive ones.
 */
class CarryoverDetectorTest {
    private val start = 1_790_000_000_000L
    private val day = 86_400_000L

    private fun user(text: String, suggestion: TurnSuggestion? = null) =
        Turn(role = TurnRole.USER, transcript = text, timestamp = start, suggestion = suggestion)
    private fun fluent(text: String) = Turn(role = TurnRole.FLUENT_SELF, transcript = text, timestamp = start)
    private fun card(target: String) = DrillCard(sourcePhrase = "old version", targetPhrase = target,
        reason = "more natural", createdAt = start - day, nextReviewAt = start, box = 1, sourceSessionId = "earlier")
    private fun correction(source: String, target: String) = DrillCard(sourcePhrase = source, targetPhrase = target,
        reason = "", createdAt = start - day, nextReviewAt = start, box = 1, sourceSessionId = "earlier")

    private fun detect(turns: List<Turn>, cards: List<DrillCard>, words: List<String> = emptyList(),
                       knownWords: List<String> = emptyList(), knownExpressions: List<String> = emptyList()) =
        CarryoverDetector.detect(turns, cards, studyingWords = words, knownWords = knownWords,
            knownExpressions = knownExpressions, sessionId = "s", sessionStartedAt = start, language = "en", now = start)

    // A correction card is credited only when the mistake is gone
    @Test fun repeatingTheMistakeIsNotUsingTheCorrection() =
        assertTrue(detect(listOf(user("Thankful that the user is trying to give me a feedback that helps.")),
            listOf(correction("give me a feedback", "give me feedback"))).isEmpty())

    @Test fun theCorrectedLineIsCredited() =
        assertEquals(listOf(Carryover.Source.DRILL_CARD), detect(listOf(user("Could you give me feedback on this later?")),
            listOf(correction("give me a feedback", "give me feedback"))).map { it.source })

    @Test fun theFixIsJudgedOnTheMatchedSpanOnly() {
        val c = correction("I go to store yesterday", "I went to the store yesterday")
        assertEquals(1, detect(listOf(user("So a friend called and I went to the store yesterday, a long walk.")), listOf(c)).size)
        assertTrue(detect(listOf(user("So I go to the store yesterday, a long walk.")), listOf(c)).isEmpty())
    }

    // Known is a claim; the talk confirms it
    @Test fun knownExpressionIsConfirmedWhenSaid() =
        assertEquals(listOf(Carryover.Source.KNOWN_EXPRESSION), detect(listOf(user("Just so we're on the same page, it's Friday.")),
            emptyList(), knownExpressions = listOf("on the same page")).map { it.source })

    @Test fun knownWordIsConfirmedWhenSaid() =
        assertEquals(listOf(Carryover.Source.KNOWN_WORD), detect(listOf(user("This week has been pretty hectic at work.")),
            emptyList(), knownWords = listOf("hectic")).map { it.source })

    @Test fun knownItemsNotSaidAreNotCredited() =
        assertTrue(detect(listOf(user("It was a quiet week, honestly.")), emptyList(),
            knownWords = listOf("hectic"), knownExpressions = listOf("on the same page")).isEmpty())

    @Test fun aWordInBothNotebookAndKnownIsCreditedOnce() {
        val hits = detect(listOf(user("This week has been pretty hectic.")), emptyList(),
            words = listOf("hectic"), knownWords = listOf("hectic"))
        assertEquals(1, hits.size)
        assertEquals(Carryover.Source.STUDYING_WORD, hits.first().source)
    }

    // Cards produced live
    @Test fun paddingAndCasingDriftStillCount() {
        assertEquals(1, detect(listOf(user("Honestly I'd rather just stay in tonight, if that's okay.")), listOf(card("I'd rather stay in tonight."))).size)
        assertEquals(1, detect(listOf(user("id rather stay in tonight")), listOf(card("I'd rather stay in tonight."))).size)
    }

    // False-positive guards
    @Test fun scatteredWordsAcrossALongRambleAreNotAPhrase() =
        assertTrue(detect(listOf(user("I would rather not talk about work. Anyway we had to stay at my parents' " +
            "place because of the trains, and I only got home very late, so I didn't do anything else that night. " +
            "It was a long day honestly, and tonight I just want to sleep.")), listOf(card("I'd rather stay in tonight."))).isEmpty())

    @Test fun reorderedWordsDoNotMatch() =
        assertTrue(detect(listOf(user("Tonight I will stay, rather at home actually no.")), listOf(card("I'd rather stay in tonight."))).isEmpty())

    @Test fun tooGenericAnItemIsNeverCredited() =
        assertTrue(detect(listOf(user("Hey, how are you doing today?")), listOf(card("How are you?"))).isEmpty())

    @Test fun idiomsMadeOfFunctionWordsSurvive() =
        assertEquals(1, detect(listOf(user("Sorry, it totally slipped my mind.")), listOf(card("It slipped my mind."))).size)

    @Test fun missingTheOneDistinguishingWordIsNotAMatch() =
        assertTrue(detect(listOf(user("I'm in a really good mood today.")), listOf(card("I'm in a sweet mood today."))).isEmpty())

    @Test fun oneSentenceEarnsAtMostOneCredit() =
        assertEquals(1, detect(listOf(user("I'm in a really good mood today.")),
            listOf(card("I'm in a really good mood today."), card("I am in a really good mood today."))).size)

    @Test fun repeatingYourOwnPhraseIsNotAdoptingASuggestion() {
        val s = TurnSuggestion(alternative = "I'm in a really good mood today.", reason = "more natural")
        assertTrue(detect(listOf(user("I'm in a really good mood today.", s), user("Yeah, I'm in a really good mood today.")), emptyList()).isEmpty())
    }

    @Test fun leaningOnOnePhraseAllTalkEarnsOneCredit() {
        val s = TurnSuggestion(alternative = "I'm just in a really good mood today.", reason = "sounds more natural")
        val hits = detect(listOf(user("I'm in a really good mood today.", s), fluent("Oh nice! Did something good happen?"),
            user("I'm in a really good mood today, yeah."), fluent("Anything in particular?"),
            user("Not really, I'm in a really good mood today.")),
            listOf(card("I'm in a sweet mood today."), card("I'm in a really good mood today.")))
        assertEquals(1, hits.size)
        assertEquals("I'm in a really good mood today.", hits.first().item)
        assertFalse(hits.any { it.item.lowercase().contains("sweet") })
    }
}
