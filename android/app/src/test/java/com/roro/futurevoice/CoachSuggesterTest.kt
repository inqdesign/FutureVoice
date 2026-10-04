package com.roro.futurevoice

import com.roro.futurevoice.data.CefrLevel
import com.roro.futurevoice.data.SpeechSpeed
import com.roro.futurevoice.data.StoreJson
import com.roro.futurevoice.talk.AxisScore
import com.roro.futurevoice.talk.CoachReply
import com.roro.futurevoice.talk.CoachSuggester
import com.roro.futurevoice.talk.ConversationEngine
import com.roro.futurevoice.talk.Session
import com.roro.futurevoice.talk.SessionScorecard
import com.roro.futurevoice.talk.SessionSummary
import com.roro.futurevoice.talk.Turn
import com.roro.futurevoice.talk.TurnRole
import com.roro.futurevoice.ui.FirstCallCheck
import com.roro.futurevoice.ui.ProgressMath
import com.roro.futurevoice.ui.TalkGoalItem
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** iOS `6e9eb92`: the "try saying" guards, apart from the network. */
class CoachSuggesterTest {
    private fun item(w: String) = TalkGoalItem(key = w, text = w, isWord = true)
    private fun payload(say: String?, meaning: String? = "뜻", word: String? = null) =
        CoachSuggester.Payload(say = say, meaning = meaning, word = word)

    @Test fun aSuggestionOutsideTheTargetScriptIsDropped() {
        // A Hangul name in the line once turned the whole suggestion Korean.
        assertNull(CoachSuggester.accept(payload("나는 [커피]가 좋아"), emptyList(), "en", "ko", "t"))
        assertEquals("I like [coffee].",
            CoachSuggester.accept(payload("I like [coffee]."), emptyList(), "en", "ko", "t")?.first?.say)
    }

    @Test fun emptyOrMissingSayIsNothing() {
        assertNull(CoachSuggester.accept(payload("  "), emptyList(), "en", "ko", "t"))
        assertNull(CoachSuggester.accept(null, emptyList(), "en", "ko", "t"))
    }

    @Test fun meaningHiddenWhenNativeIsTheTarget() {
        assertEquals("", CoachSuggester.accept(payload("Sure!", "Sure!"), emptyList(), "en", "en", "t")?.first?.meaning)
        assertEquals("뜻", CoachSuggester.accept(payload("Sure!"), emptyList(), "en", "ko", "t")?.first?.meaning)
    }

    @Test fun theNamedWordMustBeACandidate() {
        val cands = listOf(item("profound"), item("rest"))
        assertEquals("rest", CoachSuggester.accept(payload("I need some rest.", word = "Rest"), cands, "en", "ko", "t")
            ?.second?.key)
        assertNull(CoachSuggester.accept(payload("I need sleep.", word = "sleep"), cands, "en", "ko", "t")?.second)
    }

    @Test fun contentCarriesTheSituationAndItems() {
        val c = CoachSuggester.content("What can I get you?", null, null, "a café — talking with a barista",
            listOf(item("latte")))
        assertTrue(c.startsWith("Situation: a café — talking with a barista\n"))
        assertTrue(c.contains("Now the other speaker says: \"What can I get you?\""))
        assertTrue(c.endsWith("Studied items:\n- latte"))
    }

    @Test fun bracketsAreTheFadedExample() {
        assertEquals(listOf("I get up at " to false, "7" to true, "." to false),
            CoachReply.segments("I get up at [7]."))
        assertEquals(listOf("no [close" to false), CoachReply.segments("no [close"))
        assertEquals(listOf("a" to true), CoachReply.segments("[a]"))
    }
}

/** iOS `BeginnerQuestionTests` (`eaaf3af`): the rules ride only on A1/A2. */
class BeginnerQuestionTest {
    private fun prompt(level: CefrLevel) = ConversationEngine.conversationSystemPrompt(
        targetLanguage = "en", nativeLanguage = "ko", level = level)

    @Test fun beginnersGetTheQuestionRules() {
        assertTrue(prompt(CefrLevel.A1).contains("THIS LEARNER IS A BEGINNER (A1)"))
        assertTrue(prompt(CefrLevel.A2).contains("THIS LEARNER IS A BEGINNER (A2)"))
    }

    @Test fun otherLevelsAreUntouched() {
        for (level in listOf(CefrLevel.B1, CefrLevel.B2, CefrLevel.C1, CefrLevel.C2)) {
            assertFalse(prompt(level).contains("BEGINNER"))
            assertTrue(prompt(level).endsWith("Never two levels up."))
        }
    }

    /** The block sits AFTER trimIndent: the rest of the prompt keeps its trimming. */
    @Test fun beginnerPromptStaysTrimmed() {
        val p = prompt(CefrLevel.A2)
        assertTrue(p.startsWith("You're in a real-feeling SPOKEN"))
        assertTrue(p.contains("Never two levels up.\n\nHOW TO ASK"))
    }
}

/** iOS `Session.coached`: a practice call measures nothing. */
class PracticeCallTest {
    private val axis = AxisScore(80)
    private fun talk(coached: Boolean?) = Session(userId = "U", targetLanguage = "en", startedAt = 1, endedAt = 2,
        summary = SessionSummary(scorecard = SessionScorecard(axis, axis, axis, axis)), coached = coached)

    @Test fun coachedIsPractice() {
        assertTrue(talk(true).isPractice)
        assertFalse(talk(null).isPractice)
    }

    @Test fun practiceIsOutOfTheMeasurements() =
        assertEquals(1, ProgressMath.scoredSessions(listOf(talk(true), talk(null))).size)

    @Test fun rowsRoundTripUnderIosKey() {
        val json = StoreJson.json.encodeToString(Session.serializer(), talk(true))
        assertTrue(Regex("\"coached\"\\s*:\\s*true").containsMatchIn(json))
        assertFalse(StoreJson.json.encodeToString(Session.serializer(), talk(null)).contains("coached"))
        assertTrue(StoreJson.json.decodeFromString(Session.serializer(), json).isPractice)
    }
}

/** iOS `FirstCallCheckSheet` pick rules. */
class FirstCallCheckTest {
    @Test fun hardStepsDownSlowsAndCoaches() = assertEquals(
        FirstCallCheck.Preset(CefrLevel.A1, SpeechSpeed.SLOWER, true),
        FirstCallCheck.preset(FirstCallCheck.Feeling.HARD, CefrLevel.A2, SpeechSpeed.SLOW, false))

    @Test fun easyStepsUpAndDropsCoach() = assertEquals(
        FirstCallCheck.Preset(CefrLevel.B2, SpeechSpeed.NORMAL, false),
        FirstCallCheck.preset(FirstCallCheck.Feeling.EASY, CefrLevel.B1, SpeechSpeed.NORMAL, true))

    @Test fun edgesHold() {
        assertEquals(CefrLevel.A1, FirstCallCheck.preset(FirstCallCheck.Feeling.HARD, CefrLevel.A1, SpeechSpeed.SLOW, true).level)
        assertEquals(CefrLevel.C2, FirstCallCheck.preset(FirstCallCheck.Feeling.EASY, CefrLevel.C2, SpeechSpeed.SLOW, true).level)
    }

    @Test fun justRightKeepsEverything() = assertEquals(
        FirstCallCheck.Preset(CefrLevel.B1, SpeechSpeed.SLOW, true),
        FirstCallCheck.preset(FirstCallCheck.Feeling.RIGHT, CefrLevel.B1, SpeechSpeed.SLOW, true))

    @Test fun onlyTheFirstSpokenTalk() {
        fun s(spoke: Boolean) = Session(userId = "U", targetLanguage = "en", startedAt = 1, endedAt = 2,
            turns = listOf(Turn(role = if (spoke) TurnRole.USER else TurnRole.FLUENT_SELF, transcript = "hi")))
        assertTrue(FirstCallCheck.isFirst(listOf(s(true), s(false))))
        assertFalse(FirstCallCheck.isFirst(listOf(s(true), s(true))))
    }
}
