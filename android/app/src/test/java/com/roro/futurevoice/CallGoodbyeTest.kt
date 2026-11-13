package com.roro.futurevoice

import com.roro.futurevoice.net.JsonFieldScanner
import com.roro.futurevoice.talk.CallGoodbye
import com.roro.futurevoice.talk.Turn
import com.roro.futurevoice.talk.TurnFix
import com.roro.futurevoice.talk.TurnRole
import com.roro.futurevoice.talk.TurnSuggestion
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** iOS `CallGoodbyeTests`: the goodbye's facts are decided in code so the model
 *  can't praise a line that carried a mistake or set a slip already fixed as
 *  homework. */
class CallGoodbyeTest {
    private fun turn(text: String, role: TurnRole = TurnRole.USER, fixes: List<TurnFix>? = emptyList()) =
        Turn(role = role, transcript = text, suggestion = fixes?.let { TurnSuggestion(text, "", it) })

    private fun fix(was: String, now: String) = TurnFix(was = was, now = now, why = "")

    @Test fun aSlipSaidRightLaterIsPraiseNotATip() {
        val turns = listOf(
            turn("I always look for ways to help before I even asked",
                fixes = listOf(fix("before I even asked", "before I'm even asked"))),
            turn("before I'm even asked, I always look for ways to help"),
            turn("If passenger get frustrated I will listen calmly",
                fixes = listOf(fix("I will listen calmly", "I'd listen calmly"))),
        )
        val facts = CallGoodbye.facts(turns, emptyList(), "en")
        assertEquals(listOf("before I'm even asked"), facts?.fixedSlips?.map { it.now })
        assertEquals(listOf("I'd listen calmly"), facts?.openSlips?.map { it.now })
    }

    @Test fun onlyCleanLinesCanBePraised() {
        val turns = listOf(
            turn("We actually do with the language tech",
                fixes = listOf(fix("do with the language tech", "use language tech"))),
            turn("I'm a solo founder based in Munich"),
            turn("Yes okay"),
        )
        assertEquals(listOf("I'm a solo founder based in Munich"), CallGoodbye.facts(turns, emptyList(), "en")?.cleanLines)
    }

    @Test fun anUncheckedTurnIsNeitherCleanNorASlip() {
        val turns = listOf(
            turn("I went to the market yesterday morning", fixes = null),
            turn("and I bought some fresh bread there", fixes = null),
            turn("it was really good and cheap too", fixes = null),
        )
        assertNull(CallGoodbye.facts(turns, emptyList(), "en"))
        val withWord = CallGoodbye.facts(turns, listOf("fresh"), "en")
        assertEquals(listOf("fresh"), withWord?.wordsUsed)
        assertEquals(emptyList<String>(), withWord?.cleanLines)
    }

    @Test fun tooShortACallGetsNoGoodbye() {
        val turns = listOf(turn("I'm a solo founder based in Munich"),
            turn("hello there friend how are you", role = TurnRole.FLUENT_SELF))
        assertNull(CallGoodbye.facts(turns, emptyList(), "en"))
    }

    @Test fun questionsAreCut() {
        assertEquals("You got it right. Bye!", CallGoodbye.withoutQuestions("You got it right. Want to try again next time? Bye!"))
        assertEquals("よくできたね。じゃあね。", CallGoodbye.withoutQuestions("よくできたね。また練習する？じゃあね。"))
        assertEquals("", CallGoodbye.withoutQuestions("Want to go again?"))
    }

    @Test fun theRestIsWhatFollowsTheFirstSentence() {
        assertEquals("One tip: say I'd. Bye!",
            CallGoodbye.remainder("You got it right. One tip: say I'd. Bye!", "You got it right."))
        assertEquals("", CallGoodbye.remainder("Something else entirely.", "You got it right."))
    }

    /** The first sentence goes to the voice while the field is still open. */
    @Test fun theFirstSentenceIsReadFromAnOpenField() {
        val partial = "{\"spoken\": \"You said every word of that one cleanly. One tip"
        val field = JsonFieldScanner.streamingStringField("spoken", partial)
        assertEquals(false, field?.second)
        assertEquals("You said every word of that one cleanly.", JsonFieldScanner.firstSpeakableSentence(field!!.first))
        assertNull(JsonFieldScanner.firstSpeakableSentence("Nice."))
    }
}
