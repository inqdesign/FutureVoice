package com.roro.futurevoice

import com.roro.futurevoice.talk.ShadowScore
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** iOS `ShadowLineEndTests` (`a4fa2dc6`). */
class ShadowLineEndTest {
    @Test fun englishEndIsHeard() {
        val line = "Soak it all in, right?"
        assertTrue(ShadowScore.heardLineEnd(line, "soak it all in right", "en"))
        assertFalse(ShadowScore.heardLineEnd(line, "soak it all", "en"))
        assertTrue(ShadowScore.heardLineEnd(line, "soak it all in right okay", "en"))
    }

    @Test fun digitsAreSpelledOut() {
        assertTrue(ShadowScore.heardLineEnd("Meet me at gate 12", "meet me at gate twelve", "en"))
    }

    @Test fun koreanByCharacters() {
        val line = "오늘은 날씨가 정말 좋네요."
        assertTrue(ShadowScore.heardLineEnd(line, "오늘은 날씨가 정말좋네요", "ko"))
        assertFalse(ShadowScore.heardLineEnd(line, "오늘은 날씨가", "ko"))
    }

    @Test fun tooShortToTell() {
        assertFalse(ShadowScore.heardLineEnd("Hi", "hi", "en"))
    }
}
