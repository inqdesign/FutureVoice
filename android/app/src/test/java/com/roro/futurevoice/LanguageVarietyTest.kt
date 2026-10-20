package com.roro.futurevoice

import com.roro.futurevoice.talk.LanguageVariety

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** iOS `LanguageVarietyTests`: only a non-default accent adds a line. */
class LanguageVarietyTest {

    @Test fun defaultAndMissingAccentAddNothing() {
        assertEquals("", LanguageVariety.guard("en", null))
        assertEquals("", LanguageVariety.guard("en", "en-US"))
        assertEquals("", LanguageVariety.guard("es", "es-MX"))
        assertEquals("", LanguageVariety.guard("de", "de-DE"))
    }

    @Test fun pickedVarietyIsNamed() {
        val british = LanguageVariety.guard("en", "en-GB")
        assertTrue(british.contains("British English"))
        assertTrue(british.contains("is NEVER a mistake"))
        assertTrue(LanguageVariety.guard("en", "en-AU").contains("Australian English"))
        assertTrue(LanguageVariety.guard("es", "es-ES").contains("Castilian"))
    }

    @Test fun accentOfAnotherLanguageIsIgnored() {
        assertEquals("", LanguageVariety.guard("de", "en-GB"))
        assertEquals("", LanguageVariety.guard("es", "en-AU"))
    }
}
