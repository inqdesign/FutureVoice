package com.roro.futurevoice

import com.roro.futurevoice.data.TalkModeSplit
import com.roro.futurevoice.data.TalkModeSplit.Row
import org.junit.Assert.assertEquals
import org.junit.Test

/** Usage's split of the talk pool (iOS `UsageBreakdown.aggregate`,
 *  cb50cc3e · 15d3d851 · c380df8b). */
class TalkModeSplitTest {
    private fun row(key: String, action: String, seconds: Int, mode: String? = null, call: Int? = null,
                    at: String = "2026-11-05T10:00:00Z") =
        Row(created_at = at, idempotency_key = key, action = action,
            metadata = Row.Meta(seconds = seconds, mode = mode, call_seconds = call))

    @Test fun pronunciationCountsPracticedTimeBesideCharged() {
        val parts = TalkModeSplit.aggregate(listOf(
            row("a", "talk_time", 300, mode = "pron", call = 600),
            // A call from before the discount: charged whole, ran as long.
            row("b", "talk_time", 120, mode = "pron"),
        ), periodKey = "2026-11-01")
        val pron = parts.single()
        assertEquals("pron", pron.key)
        assertEquals(420, pron.seconds)
        assertEquals(720, pron.callSeconds)
    }

    @Test fun everythingPaidFromThePoolIsAPart() {
        val parts = TalkModeSplit.aggregate(listOf(
            row("a", "talk_time", 60, mode = "free"),
            row("b", "script_voiceover", 120),
            row("c", "scene_play", 300),
            row("d", "talk_time", 30),
            row("e", "talk_time", 90, mode = "tutor"),
            // Before the period, and a repeat of a row: neither counts.
            row("f", "talk_time", 999, mode = "free", at = "2026-10-20T10:00:00Z"),
            row("a", "talk_time", 60, mode = "free"),
        ), periodKey = "2026-11-01")
        assertEquals(listOf("free", "tutor", "scene", "voiceover", "earlier"), parts.map { it.key })
        assertEquals(listOf(60, 90, 300, 120, 30), parts.map { it.seconds })
    }
}
