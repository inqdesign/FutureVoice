package com.roro.futurevoice

import com.roro.futurevoice.data.CefrLevel
import com.roro.futurevoice.data.TalkCurriculum
import com.roro.futurevoice.talk.Session
import com.roro.futurevoice.talk.SessionSummary
import com.roro.futurevoice.talk.Turn
import com.roro.futurevoice.talk.TurnRole
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

/**
 * iOS `TalkCurriculumShadowPicksTests` (plan 5.8): the book's Shadow chapter
 * kept suggesting the call's opening and closing greetings — ritual lines of
 * easy words — instead of the reusable middle of the conversation.
 * (Chapters and mastery are `TalkCurriculumTest`.)
 */
class TalkCurriculumShadowPicksTest {
    private fun turn(text: String) = Turn(role = TurnRole.FLUENT_SELF, transcript = text)
    private fun session(turns: List<Turn>, offered: List<String> = emptyList()) = Session(
        userId = "u", targetLanguage = "en", topic = "Coffee chat",
        startedAt = 1_000L, endedAt = 2_000L, turns = turns,
        summary = if (offered.isEmpty()) null else SessionSummary(expressionsOffered = offered))

    @Test fun openerAndFarewellLoseToTheMiddleOfTheCall() {
        val opener = turn("Hey it is so good to talk to you today my friend!")
        val middle = turn("You could push back on the deadline and end up saving the launch.")
        val farewell = turn("It was so nice to talk have a good day my friend!")
        val picks = TalkCurriculum.shadowPicks(
            session(listOf(opener, middle, farewell), offered = listOf("push back on")), CefrLevel.B1, "en")
        assertFalse(picks.isEmpty())
        assertFalse(picks.any { it.id == opener.id })
        assertFalse(picks.any { it.id == farewell.id })
    }

    @Test fun offeredExpressionOutranksPlainLines() {
        val plain = turn("I think you can just ask them about it again tomorrow.")
        val carrier = turn("If you wait too long you might end up doing it all again.")
        val picks = TalkCurriculum.shadowPicks(session(listOf(
            turn("Hello there so good to see you!"), plain, carrier,
            turn("Bye for now have a lovely evening friend!")), offered = listOf("end up doing")),
            CefrLevel.C2, "en")
        assertEquals(listOf(carrier.id), picks.map { it.id })
    }

    @Test fun allRitualTalkStillOffersItsLines() {
        val picks = TalkCurriculum.shadowPicks(session(listOf(
            turn("Hey it is so good to talk to you today!"),
            turn("It was so nice to talk have a good day!"))), CefrLevel.A1, "en")
        assertFalse(picks.isEmpty())
    }

    @Test fun fallbackPrefersMiddleLinesOverTheFarewell() {
        val farewell = turn("It was so nice to talk have a good day my friend!")
        val picks = TalkCurriculum.shadowPicks(session(listOf(
            turn("Hey it is so good to talk to you today!"),
            turn("I think you can just ask them about it soon."),
            turn("Maybe they will say yes if you ask them nicely."),
            farewell)), CefrLevel.C2, "en")
        assertFalse(picks.isEmpty())
        assertFalse(picks.any { it.id == farewell.id })
    }
}
