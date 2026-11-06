package com.roro.futurevoice

import com.roro.futurevoice.data.CefrLevel
import com.roro.futurevoice.talk.CoachSuggester
import com.roro.futurevoice.talk.ConversationPrompt
import com.roro.futurevoice.talk.LanguageLines
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * iOS `LanguageLineTests` (5a462332): the per-language call lines reach their
 * own language only; every other language's prompt stays byte-identical.
 */
class LanguageLineTest {

    @Test fun otherLanguagesGetNothing() {
        for (lang in listOf("en", "fr", "zh-Hans")) {
            assertEquals(lang, "", LanguageLines.beginnerQuestion(lang))
            assertEquals(lang, "", LanguageLines.firstCall(lang))
            assertEquals(lang, "", LanguageLines.selfAddress(lang, asFutureSelf = true))
            assertEquals(lang, "", LanguageLines.spanishGuard(lang, asFutureSelf = true, accentId = null))
        }
        assertEquals(ConversationPrompt.beginnerQuestions(CefrLevel.A2),
            ConversationPrompt.beginnerQuestions(CefrLevel.A2, "en"))
        assertEquals("", ConversationPrompt.beginnerQuestions(CefrLevel.B1, "ko"))
    }

    @Test fun eachLanguageGetsItsLine() {
        assertTrue(ConversationPrompt.beginnerQuestions(CefrLevel.A1, "ko").contains("KOREAN, BEGINNER"))
        assertTrue(ConversationPrompt.beginnerQuestions(CefrLevel.A2, "ja").contains("JAPANESE, BEGINNER"))
        assertEquals("", LanguageLines.beginnerQuestion("de"))
        assertEquals("", LanguageLines.beginnerQuestion("es"))
        assertTrue(LanguageLines.firstCall("ko").contains("이렇게 얘기하니까 좋다"))
        assertTrue(LanguageLines.firstCall("ja").contains("話せてうれしい"))
        assertEquals("", LanguageLines.firstCall("de"))
    }

    @Test fun futureSelfOnlyLines() {
        assertTrue(LanguageLines.selfAddress("ja", asFutureSelf = true).contains("bare name"))
        assertEquals("", LanguageLines.selfAddress("ja", asFutureSelf = false))
        val cast = LanguageLines.spanishGuard("es", asFutureSelf = false, accentId = null)
        assertFalse(cast.contains("GENDER"))
        assertTrue(cast.contains("WHICH SPANISH"))
        assertTrue(LanguageLines.spanishGuard("es", asFutureSelf = true, accentId = null).contains("GENDER"))
    }

    @Test fun coachingLinesStayInTheirLanguage() {
        for (lang in listOf("en", "ko", "fr")) {
            assertEquals(lang, "", LanguageLines.spokenGrammarGuard(lang))
            assertEquals(lang, "", CoachSuggester.bracketAgreementLine(lang))
            assertEquals(lang, "", LanguageLines.notesLanguageGuard(lang, "ko"))
        }
        assertEquals("", LanguageLines.tutorRegisterLine("en"))
        assertEquals("", LanguageLines.tutorRegisterLine("de"))
        // A learner whose native language IS the target gets no notes line.
        assertEquals("", LanguageLines.notesLanguageGuard("de", "de"))
        assertTrue(LanguageLines.notesLanguageGuard("ja", "ko").contains("NOTES IN KOREAN"))
        assertTrue(LanguageLines.notesLanguageGuard("de", "ko").contains("NOTES IN KOREAN"))
        assertTrue(LanguageLines.notesLanguageGuard("ja", "en").contains("never in Japanese"))
        assertTrue(LanguageLines.spokenGrammarGuard("es").contains("REPORTED SPEECH"))
        assertTrue(LanguageLines.spokenGrammarGuard("de").contains("DEMONSTRATIVES"))
        assertTrue(LanguageLines.tutorRegisterLine("ko").contains("반말"))
        assertTrue(LanguageLines.tutorRegisterLine("ja").contains("plain form"))
        assertTrue(LanguageLines.tutorRegisterLine("es").contains("Dilo otra vez"))
        assertTrue(CoachSuggester.bracketAgreementLine("de").contains("seit [zwei Jahren]"))
        assertTrue(CoachSuggester.bracketAgreementLine("es").contains("tengo [un hermano]"))
    }
}
