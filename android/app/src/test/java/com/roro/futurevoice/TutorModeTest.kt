package com.roro.futurevoice

import com.roro.futurevoice.data.CefrLevel
import com.roro.futurevoice.talk.ConversationEngine
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** iOS `TutorModeTests` (b3a6d30f): tutor mode rides only on a call that
 *  turned it on; every other prompt is unchanged. */
class TutorModeTest {
    private fun prompt(lang: String, tutor: Boolean, level: CefrLevel = CefrLevel.B1) =
        ConversationEngine.conversationSystemPrompt(
            targetLanguage = lang, nativeLanguage = "ko", level = level, tutor = tutor)

    @Test fun offLeavesThePromptAlone() {
        val off = prompt("en", tutor = false)
        assertFalse(off.contains("TUTOR MODE"))
        assertTrue(off.contains("Never correct the user mid-conversation."))
        assertTrue(off.endsWith("(1) is only about not monologuing."))
    }

    @Test fun onReplacesTheNoCorrectionRuleAndComesLast() {
        for (level in listOf(CefrLevel.A2, CefrLevel.B1)) {
            val on = prompt("en", tutor = true, level = level)
            assertFalse(on.contains("Never correct the user mid-conversation."))
            assertTrue(on.contains("- Correct the user only as TUTOR MODE below says."))
            assertTrue(on.contains("TUTOR MODE"))
            // Last, after the beginner rules it outranks.
            assertTrue(on.endsWith("All of it in English only, like everything else."))
        }
    }

    @Test fun carriesTheLanguageGuards() {
        assertTrue(prompt("ko", tutor = true).contains("ASR SPACING GUARD"))
        assertTrue(prompt("ko", tutor = true).contains("SPEECH LEVEL is the learner's choice"))
        assertTrue(prompt("ko", tutor = true).contains("Never mention 띄어쓰기"))
        assertFalse(prompt("en", tutor = true).contains("띄어쓰기"))
    }
}
