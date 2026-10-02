package com.roro.futurevoice

import com.roro.futurevoice.data.CefrLevel
import com.roro.futurevoice.talk.ConversationEngine
import com.roro.futurevoice.talk.PromptClock
import com.roro.futurevoice.talk.Session
import com.roro.futurevoice.talk.Turn
import com.roro.futurevoice.talk.TurnRole
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.ZoneId
import java.time.ZonedDateTime

/** iOS `PromptClockTests`, case for case. */
class PromptClockTest {
    private val zone = ZoneId.of("Asia/Seoul")
    private fun at(day: Int, hour: Int, minute: Int = 0) =
        ZonedDateTime.of(2026, 9, day, hour, minute, 0, 0, zone).toInstant().toEpochMilli()

    private fun talk(end: Long, learnerSpoke: Boolean = true, id: String = "s$end"): Session {
        val turns = (if (learnerSpoke) listOf(Turn(role = TurnRole.USER, transcript = "hi", timestamp = end - 60_000)) else emptyList()) +
            Turn(role = TurnRole.FLUENT_SELF, transcript = "hey", timestamp = end)
        return Session(id = id, userId = "u", targetLanguage = "en", startedAt = end - 300_000, endedAt = end, turns = turns)
    }

    @Test fun lastNightIsYesterdayThoughOnlyNineHoursPassed() {
        assertEquals(1, PromptClock.calendarDays(at(27, 23), at(28, 8), zone))
    }

    @Test fun partOfDay() {
        assertEquals("morning", PromptClock.partOfDay(8))
        assertEquals("afternoon", PromptClock.partOfDay(14))
        assertEquals("evening", PromptClock.partOfDay(19))
        assertEquals("night", PromptClock.partOfDay(2))
    }

    @Test fun countsOnlyTalksTheLearnerSpokeInAndNotThisOne() {
        val current = talk(at(28, 7), id = "current")
        val clock = PromptClock.make(now = at(28, 8), sessions = listOf(
            talk(at(28, 7, 20)), talk(at(28, 7, 40), learnerSpoke = false),
            talk(at(25, 21)), talk(at(28, 9)), current), excluding = "current", zone = zone)
        assertEquals(1, clock.talksEarlierToday)
        assertEquals(at(28, 7, 20), clock.lastTalkToday)
        assertEquals(at(25, 21), clock.lastTalkBeforeToday)
    }

    @Test fun firstTalkOfTheDaySaysSoAndNamesTheLastDay() {
        val block = PromptClock.make(now = at(28, 8, 14), sessions = listOf(talk(at(23, 20))), zone = zone)
            .promptBlock(includeHistory = true)
        assertTrue(block, block.contains("Monday, 28 September 2026, at 08:14 — morning"))
        assertTrue(block, block.contains("This is their FIRST talk today."))
        assertTrue(block, block.contains("5 days ago (Wednesday)"))
    }

    @Test fun secondTalkTodayIsRecentNotALongAbsence() {
        val block = PromptClock.make(now = at(28, 8), sessions = listOf(talk(at(28, 7, 20))), zone = zone)
            .promptBlock(includeHistory = true)
        assertTrue(block, block.contains("already had 1 talk earlier today, the latest ended about 40 minutes ago"))
        assertFalse(block.contains("FIRST talk"))
    }

    @Test fun historyCanBeLeftOutButTheTimeCannot() {
        val block = PromptClock.make(now = at(28, 20), sessions = listOf(talk(at(28, 7))), zone = zone)
            .promptBlock(includeHistory = false)
        assertTrue(block, block.contains("evening where the user is"))
        assertFalse(block.contains("already had"))
        assertFalse(block.contains("Before today"))
    }

    @Test fun conversationPromptCarriesTheClockAndItsGuard() {
        val clock = PromptClock.make(now = at(28, 8), sessions = listOf(talk(at(28, 7))), zone = zone)
        fun prompt(first: Boolean, c: PromptClock? = clock) = ConversationEngine.conversationSystemPrompt(
            targetLanguage = "ko", nativeLanguage = "en", level = CefrLevel.B1, firstMeeting = first, clock = c)
        assertTrue(prompt(false).contains("already had 1 talk earlier today"))
        assertTrue(prompt(true).contains("WHEN THIS IS"))
        assertFalse(prompt(true).contains("already had"))
        assertFalse(prompt(false, null).contains("WHEN THIS IS"))
    }
}
