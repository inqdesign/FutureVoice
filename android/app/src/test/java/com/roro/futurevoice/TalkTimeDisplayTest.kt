package com.roro.futurevoice

import com.roro.futurevoice.data.TalkTime
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** iOS `PracticeStats.talkClock` / `talkSpan` (plan 5.9): a day is mm:ss, a
 *  span is minutes — except under a minute, which names the seconds. */
class TalkTimeDisplayTest {
    @Test fun aDayIsAClock() {
        assertEquals("00:00", TalkTime.clock(0))
        assertEquals("00:40", TalkTime.clock(40))
        assertEquals("12:34", TalkTime.clock(754))
        assertEquals("60:00", TalkTime.clock(3600))
        assertEquals("00:00", TalkTime.clock(-5))
    }

    @Test fun aSpanIsMinutesUnlessUnderOne() {
        assertFalse(TalkTime.spanIsSeconds(0))     // "0 min"
        assertTrue(TalkTime.spanIsSeconds(1))
        assertTrue(TalkTime.spanIsSeconds(59))
        assertFalse(TalkTime.spanIsSeconds(60))    // "1 min"
        assertFalse(TalkTime.spanIsSeconds(9000))
    }
}
