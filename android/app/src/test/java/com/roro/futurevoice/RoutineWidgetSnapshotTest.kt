package com.roro.futurevoice

import com.roro.futurevoice.widget.RoutineWidgetBlock
import com.roro.futurevoice.widget.RoutineWidgetSnapshot
import com.roro.futurevoice.widget.routineClock
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.util.Calendar

/** The routine widget's day rules (iOS `RoutineWidgetSnapshot` extension, a0836bbe). */
class RoutineWidgetSnapshotTest {
    private val day = RoutineWidgetSnapshot.startOfDay(System.currentTimeMillis())
    private fun at(h: Int, m: Int = 0) = Calendar.getInstance().apply {
        timeInMillis = day; set(Calendar.HOUR_OF_DAY, h); set(Calendar.MINUTE, m)
    }.timeInMillis
    private fun block(kind: String, h: Int, minutes: Int = 15, done: Boolean = false, anytime: Boolean = false) =
        RoutineWidgetBlock(id = "$kind$h", kind = kind, start = if (anytime) day else at(h),
            end = (if (anytime) day else at(h)) + minutes * 60_000L, anytime = anytime,
            title = kind, nowLine = "now $kind", done = done)

    private val snap = RoutineWidgetSnapshot(
        day = day,
        today = listOf(block("talk", 8, done = true), block("review", 12), block("speech", 21)),
        tomorrow = listOf(block("shadow", 9)),
    )

    @Test fun nowIsTheBlockWhoseTimeIsOn() {
        assertEquals("review", snap.now(at(12, 5))?.kind)
        assertNull(snap.now(at(12, 30)))
        // A done block is never "now".
        assertNull(snap.now(at(8, 5)))
    }

    @Test fun nextIsTheTimedBlockToComeThenOneLapsed() {
        assertEquals("review", snap.next(at(10))?.kind)
        assertEquals("speech", snap.next(at(13))?.kind)
        // Past the last block: the one whose time passed undone.
        assertEquals("review", snap.next(at(22))?.kind)
    }

    @Test fun anytimeComesBeforeLapsed() {
        val s = snap.copy(today = snap.today + block("listen", 0, anytime = true))
        assertEquals("listen", s.next(at(22))?.kind)
        assertNull(s.now(at(0, 5)))
    }

    @Test fun tomorrowBecomesTodayPastMidnight() {
        val next = RoutineWidgetSnapshot.addDay(day)
        assertEquals(listOf("shadow"), snap.blocks(next + 3_600_000L).map { it.kind })
        assertNull(snap.tomorrowFirst(next + 3_600_000L))
        assertEquals("shadow", snap.tomorrowFirst(at(10))?.kind)
    }

    @Test fun edgesAreStartsEndsAndMidnight() {
        val e = snap.edges(at(13))
        assertEquals(at(21), e.first())
        assert(RoutineWidgetSnapshot.addDay(day) in e)
    }

    @Test fun deepLinkNamesTheBlock() {
        assertEquals("futurevoice://routine?kind=review", snap.deepLink(at(12, 1)))
        assertEquals("futurevoice://routine", RoutineWidgetSnapshot().deepLink(at(12)))
        assertEquals("8:00", routineClock(at(8)))
    }
}
