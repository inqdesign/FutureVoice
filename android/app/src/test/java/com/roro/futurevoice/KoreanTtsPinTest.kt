package com.roro.futurevoice

import com.roro.futurevoice.net.VoiceClient
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * Port of iOS `KoreanTTSPinTests` (`73f0faac`): `language_code` is pinned only
 * for a Korean learner's Hangul line. Everything else keeps sending what it
 * sent before.
 */
class KoreanTtsPinTest {
    @Test fun koreanLineForKoreanLearnerIsPinned() {
        assertEquals("ko", VoiceClient.pinnedLanguage("안녕, 몇 년 뒤의 너야. 요즘 어떻게 지내?", "ko"))
        assertEquals("ko", VoiceClient.pinnedLanguage("nawana 앱을 만들고 있어요", "ko"))
    }

    @Test fun englishLineForKoreanLearnerIsNotPinned() {
        assertNull(VoiceClient.pinnedLanguage("Hi, it's you from a few years on.", "ko"))
    }

    @Test fun otherTargetsAreUntouched() {
        assertNull(VoiceClient.pinnedLanguage("안녕, 반가워. 오늘 뭐 했어?", "en"))
        assertNull(VoiceClient.pinnedLanguage("こんにちは、元気？", "ja"))
        assertNull(VoiceClient.pinnedLanguage("안녕, 반가워.", null))
    }
}
