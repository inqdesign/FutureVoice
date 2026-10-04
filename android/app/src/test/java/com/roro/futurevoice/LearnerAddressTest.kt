package com.roro.futurevoice

import com.roro.futurevoice.data.LearnerAddress
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** iOS `LearnerAddress.vocative` (plan 5.15): 아 after a final consonant, 야
 *  after a vowel — Hangul names only, Korean chrome only. */
class LearnerAddressTest {
    @Test fun koreanVocative() {
        assertEquals("보람아", LearnerAddress.vocative("보람", "ko"))
        assertEquals("지수야", LearnerAddress.vocative("지수", "ko"))
        assertEquals("지수야", LearnerAddress.vocative("  지수 ", "ko-KR"))
    }

    @Test fun nonHangulNamesStayBare() {
        assertEquals("Alex", LearnerAddress.vocative("Alex", "ko"))
        assertEquals("김Alex", LearnerAddress.vocative("김Alex", "ko"))
    }

    @Test fun otherAppLanguagesStayBare() {
        assertEquals("보람", LearnerAddress.vocative("보람", "en"))
        assertEquals("보람", LearnerAddress.vocative("보람", "ja"))
    }

    @Test fun noNameIsNull() {
        assertNull(LearnerAddress.vocative(null, "ko"))
        assertNull(LearnerAddress.vocative("   ", "ko"))
    }
}
