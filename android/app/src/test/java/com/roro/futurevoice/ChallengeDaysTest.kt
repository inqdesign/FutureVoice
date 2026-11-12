package com.roro.futurevoice

import com.roro.futurevoice.data.ChallengeDay
import com.roro.futurevoice.data.ChallengeDayPlan
import com.roro.futurevoice.data.ChallengeDayPlan.Step
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDateTime
import java.time.ZoneId

/** iOS `ChallengeDaysTests`: which local days are sent, and when. */
class ChallengeDaysTest {
    private val seoul = ZoneId.of("Asia/Seoul")

    private fun at(y: Int, m: Int, d: Int, h: Int = 12, min: Int = 0): Long =
        LocalDateTime.of(y, m, d, h, min).atZone(seoul).toInstant().toEpochMilli()

    @Test fun onlyDaysWithANumberAreSentOldestFirstByLocalDate() {
        val now = at(2026, 12, 3, 9)
        // 00:30 on Dec 2 in Seoul is still Dec 1 in UTC: it is Dec 2's take.
        val days = ChallengeDayPlan.days(now, seoul, mapOf("2026-12-01" to 250, "2026-12-03" to 300),
            listOf(at(2026, 12, 2, 0, 30), at(2026, 12, 3, 8), at(2026, 12, 3, 8, 30)))
        assertEquals(listOf(
            ChallengeDay("2026-12-01", 250, 0),
            ChallengeDay("2026-12-02", 0, 1),
            ChallengeDay("2026-12-03", 300, 2),
        ), days)
    }

    @Test fun onlyTheLastFourteenDaysGo() {
        val talk = (1..20).associate { "2026-12-%02d".format(it) to 60 }
        val days = ChallengeDayPlan.days(at(2026, 12, 20), seoul, talk, listOf(at(2026, 12, 1)))
        assertEquals(ChallengeDayPlan.WINDOW_DAYS, days.size)
        assertEquals("2026-12-07", days.first().day)
        assertEquals("2026-12-20", days.last().day)
        assertTrue(days.all { it.speechTakes == 0 })
    }

    @Test fun theFingerprintMovesWithANumberOrTheTimeZone() {
        val a = listOf(ChallengeDay("2026-12-01", 240, 1))
        val print = ChallengeDayPlan.fingerprint(a, "Asia/Seoul")
        assertEquals(print, ChallengeDayPlan.fingerprint(a, "Asia/Seoul"))
        assertNotEquals(print, ChallengeDayPlan.fingerprint(a, "Europe/Berlin"))
        assertNotEquals(print, ChallengeDayPlan.fingerprint(listOf(a[0].copy(speechTakes = 2)), "Asia/Seoul"))
    }

    @Test fun aParticipantSendsOnlyWhatChanged() {
        val now = at(2026, 12, 3)
        fun step(failed: Long? = null, sent: String?) =
            ChallengeDayPlan.step(true, null, failed, sent, "new", now)
        assertEquals(Step.WAIT, step(sent = "new"))
        assertEquals(Step.SEND, step(sent = "old"))
        assertEquals(Step.WAIT, step(failed = now - 60_000, sent = "old"))
        assertEquals(Step.SEND, step(failed = now - 3_600_000, sent = "old"))
    }

    @Test fun someoneOutsideTheProgramIsAskedOnceADay() {
        val now = at(2026, 12, 3)
        fun step(participant: Boolean?, asked: Long? = null, failed: Long? = null) =
            ChallengeDayPlan.step(participant, asked, failed, null, "new", now)
        assertEquals(Step.ASK, step(null))
        assertEquals(Step.WAIT, step(false, asked = now - 3_600_000))
        assertEquals(Step.ASK, step(false, asked = now - 25 * 3_600_000L))
        // The RPC is not there yet: no storm.
        assertEquals(Step.WAIT, step(null, failed = now - 3_600_000))
        assertEquals(Step.ASK, step(null, failed = now - 7 * 3_600_000L))
        // A clock set back does not silence it.
        assertEquals(Step.ASK, step(false, asked = now + 3_600_000))
    }
}
