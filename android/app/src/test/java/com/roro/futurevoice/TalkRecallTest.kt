package com.roro.futurevoice

import com.roro.futurevoice.data.CefrLevel
import com.roro.futurevoice.talk.ConversationEngine
import com.roro.futurevoice.talk.FreeTalkOpeners
import com.roro.futurevoice.talk.PromptClock
import com.roro.futurevoice.talk.Session
import com.roro.futurevoice.talk.TalkRecall
import com.roro.futurevoice.talk.Turn
import com.roro.futurevoice.talk.TurnRole
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.ZoneId
import java.time.ZonedDateTime

/** iOS `TalkRecallTests` (27a08569) and the free-talk prompt that carries it. */
class TalkRecallTest {
    private val zone = ZoneId.of("Asia/Seoul")
    private fun at(day: Int, hour: Int) =
        ZonedDateTime.of(2026, 11, day, hour, 0, 0, 0, zone).toInstant().toEpochMilli()

    private fun line(role: TurnRole, text: String, at: Long, misheard: Boolean = false) =
        Turn(role = role, transcript = text, timestamp = at, excludedFromScoring = misheard)

    private fun talk(title: String?, end: Long, lines: List<Pair<TurnRole, String>>,
                     counterpart: String? = null) = Session(
        id = "s$end${title.orEmpty()}", userId = "u", targetLanguage = "en", topic = title,
        startedAt = end - 600_000, endedAt = end,
        turns = lines.mapIndexed { i, l -> line(l.first, l.second, end + (i - lines.size) * 20_000L) },
        counterpartId = counterpart)

    private val interview = talk("Interview at the bank on Friday", at(10, 9), listOf(
        TurnRole.FLUENT_SELF to "Hey, how are you?",
        TurnRole.USER to "I have an interview at the bank on Friday and I am nervous.",
        TurnRole.FLUENT_SELF to "Which part worries you?",
        TurnRole.USER to "The salary question, I never know what number to say."))
    private val trip = talk("Weekend trip to Busan", at(14, 20), listOf(
        TurnRole.USER to "We went to Busan and ate raw fish at the market.",
        TurnRole.FLUENT_SELF to "Nice. Was it crowded?"))

    @Test fun theIndexIsTalksWithTheFluentSelfNewestFirst() {
        val withFriend = talk("Coffee with Sarah", at(15, 9), listOf(TurnRole.USER to "hi"), counterpart = "p")
        val silent = talk("Nothing said", at(15, 10), listOf(TurnRole.FLUENT_SELF to "Hello?"))
        val index = TalkRecall.index(listOf(interview, trip, withFriend, silent), at(17, 9), emptySet())
        assertEquals(listOf("Weekend trip to Busan", "Interview at the bank on Friday"), index.map { it.title })
        assertEquals(listOf("Interview at the bank on Friday"),
            TalkRecall.index(listOf(interview, trip), at(17, 9), setOf(trip.id)).map { it.title })
        val lines = TalkRecall.indexLines(index, at(17, 9), zone)
        assertTrue(lines[0], lines[0].contains("Weekend trip to Busan"))
        assertTrue(lines[0], lines[0].startsWith("3 days ago"))
    }

    @Test fun onlyALineThatPointsBackIsAskedAbout() {
        val index = TalkRecall.index(listOf(interview, trip), at(17, 9), emptySet())
        assertTrue(TalkRecall.mayRecall("Remember what I told you last week?", index, "en"))
        assertTrue(TalkRecall.mayRecall("So the interview went well", index, "en"))
        assertFalse(TalkRecall.mayRecall("I am cooking pasta now", index, "en"))
        assertFalse(TalkRecall.mayRecall("Remember what I told you?", emptyList(), "en"))
    }

    @Test fun theRecordCentresOnWhatIsBeingTalkedAbout() {
        val long = mutableListOf<Pair<TurnRole, String>>()
        for (i in 0 until 30) {
            long += TurnRole.USER to "filler number $i about nothing much at all today"
            long += TurnRole.FLUENT_SELF to "reply number $i"
        }
        long.add(40, TurnRole.USER to "My landlord wants to raise the rent by ten percent.")
        val entry = TalkRecall.index(listOf(talk("A long one", at(12, 9), long)), at(17, 9), emptySet())[0]
        val record = TalkRecall.record(entry, "the landlord thing got worse", at(17, 9), "en", zone)
        assertTrue(record.contains("landlord wants to raise the rent"))
        assertTrue(record.contains("Part of it, oldest first:"))
        assertFalse(record.contains("filler number 0 "))
        assertTrue(record.length < 2700)
    }

    @Test fun aMisheardLineAndItsReplyStayOut() {
        val s = interview.copy(turns = interview.turns + listOf(
            line(TurnRole.USER, "She is here for six month.", at(10, 9), misheard = true),
            line(TurnRole.FLUENT_SELF, "Oh, your friend is staying six months?", at(10, 9))))
        val entry = TalkRecall.index(listOf(s), at(17, 9), emptySet())[0]
        val record = TalkRecall.record(entry, "", at(17, 9), "en", zone)
        assertTrue(record.contains("All of it, oldest first:"))
        assertTrue(record.contains("salary question"))
        assertFalse(record.contains("six month"))
    }

    private fun prompt(past: List<String> = emptyList(), recalled: List<String> = emptyList(),
                       clock: PromptClock? = null) = ConversationEngine.freeTalkPrompt(
        targetLanguage = "en", nativeLanguage = "ko", level = CefrLevel.B2, topPatterns = emptyList(),
        weakVocabAreas = emptyList(), topic = "", persona = null, newsFacts = emptyList(), clock = clock,
        earlierToday = null, learnerPicksTopic = false, pastTalks = past, recalledTalks = recalled,
        gender = null)

    @Test fun theFreeTalkPromptIsFactsAndCarriesTheTalksOnlyWhenGiven() {
        val bare = prompt()
        assertTrue(bare.startsWith("You are the user's future self: them, a few years from now, speaking English fluently"))
        assertTrue(bare.contains("\nAbout them:\n- Native language: Korean\n- Their English level: B2 (CEFR)\n\nThis call:\n\n\nHow the call works:"))
        assertFalse(bare.contains("other talks you two had"))
        val full = prompt(listOf("3 days ago: \"Weekend trip to Busan\""),
            listOf("A talk you two had 3 days ago, \"Weekend trip to Busan\".\nAll of it, oldest first:\nthem: \"We went to Busan\""))
        assertTrue(full.contains("- A few of the other talks you two had, newest first. There were more than these, and each covered more than its title says:\n  · 3 days ago: \"Weekend trip to Busan\""))
        assertTrue(full.contains("- More of a talk from that list, which they have just brought up:\n  · A talk you two had 3 days ago, \"Weekend trip to Busan\". It went like this: them: \"We went to Busan\""))
    }

    @Test fun theHelloIsWrittenWithoutTheClock() {
        val clock = PromptClock(now = at(17, 9), zone = zone, talksEarlierToday = 0,
            lastTalkToday = null, lastTalkBeforeToday = at(15, 9))
        assertFalse(prompt().contains("- Now:"))
        val with = prompt(clock = clock)
        assertTrue(with, with.contains("- Now: Tuesday, 17 November 2026, 09:00 where they are.\n- This is their first talk with you today.\n- Before today, your last talk was 2 days ago (Sunday)."))
        assertEquals("They just called you. You have not heard them say anything yet. Say hello.",
            FreeTalkOpeners.SAY_HELLO_NOTE)
    }
}
