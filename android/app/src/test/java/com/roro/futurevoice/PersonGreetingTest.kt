package com.roro.futurevoice

import com.roro.futurevoice.data.Counterpart
import com.roro.futurevoice.talk.GreetingEngine
import com.roro.futurevoice.talk.ProfileVoice
import com.roro.futurevoice.talk.VoicePreset
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** iOS `Counterpart.greetingNeedsWriting` (ce007a48), `VoicePreset.isLibraryVoice`
 *  and `ProfileVoice.options` (fa7fca3b). */
class PersonGreetingTest {
    private val v = GreetingEngine.PROMPT_VERSION

    @Test fun emptyGreetingNeedsWriting() {
        assertTrue(Counterpart(name = "A").greetingNeedsWriting("en", v))
    }

    @Test fun olderPromptIsRewrittenButLearnersLineNever() {
        val old = Counterpart(name = "A").withGreeting("Hi Eunggyu!", "en")
        assertTrue(old.greetingNeedsWriting("en", v))           // no version = earlier prompt
        val mine = old.copy(greetingVersionByLanguage = mapOf("en" to -1))
        assertFalse(mine.greetingNeedsWriting("en", v))
        val current = old.copy(greetingVersionByLanguage = mapOf("en" to v))
        assertFalse(current.greetingNeedsWriting("en", v))
    }

    @Test fun withGreetingTrimsAndClears() {
        val c = Counterpart(name = "A").withGreeting("  hey  ", "de")
        assertEquals("hey", c.greeting("de"))
        assertTrue(c.withGreeting("   ", "de").greetingByLanguage.isEmpty())
    }

    @Test fun libraryVoiceIsAUuid() {
        assertTrue(VoicePreset.isLibraryVoice("cd6c48a9-774b-4397-98b4-9948c0a790f0"))
        assertFalse(VoicePreset.isLibraryVoice("NDTYOmYEjbDIVCKB35i3"))
        assertFalse(VoicePreset.isLibraryVoice(null))
    }

    @Test fun profileVoicesByNativeLanguageFallBackToEnglish() {
        assertEquals("Soojin", ProfileVoice.options("ko").first().name)
        assertEquals(ProfileVoice.options("en"), ProfileVoice.options("xx"))
        assertTrue(ProfileVoice.options("ko").all { VoicePreset.isLibraryVoice(it.id) })
    }
}
