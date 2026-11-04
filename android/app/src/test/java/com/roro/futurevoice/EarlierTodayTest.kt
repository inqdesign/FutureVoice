package com.roro.futurevoice

import com.roro.futurevoice.data.CefrLevel
import com.roro.futurevoice.data.PronunciationEntry
import com.roro.futurevoice.talk.ConversationEngine
import com.roro.futurevoice.talk.EarlierToday
import com.roro.futurevoice.talk.FreeTalkOpeners
import com.roro.futurevoice.talk.Session
import com.roro.futurevoice.talk.TutorLessonRecord
import com.roro.futurevoice.talk.Turn
import com.roro.futurevoice.talk.TurnRole
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZonedDateTime

/** iOS `EarlierTodayTests` (98d7ff2a), case for case. */
class EarlierTodayTest {
    private val zone = ZoneId.of("Asia/Seoul")
    private fun at(day: Int, hour: Int, minute: Int = 0) =
        ZonedDateTime.of(2026, 11, day, hour, minute, 0, 0, zone).toInstant().toEpochMilli()

    private fun talk(end: Long, said: String = "I have a meeting at ten",
                     counterpart: String? = null, lesson: TutorLessonRecord? = null) = Session(
        id = "s$end", userId = "u", targetLanguage = "en", startedAt = end - 300_000, endedAt = end,
        turns = listOf(
            Turn(role = TurnRole.USER, transcript = said, timestamp = end - 60_000),
            Turn(role = TurnRole.FLUENT_SELF, transcript = "Good luck!", timestamp = end),
        ),
        counterpartId = counterpart, tutorLesson = lesson)

    private fun take(at: Long, words: List<Pair<String, Int>>, surface: String = "pron_call") =
        PronunciationEntry(id = "t$at$surface", date = at, surface = surface, locale = "en-US",
            accuracy = 70, score = 70, words = words.map { PronunciationEntry.WordScore(it.first, it.second) })

    private fun latest(now: Long, sessions: List<Session>, pron: List<PronunciationEntry> = emptyList()) =
        EarlierToday.latest(now, sessions, pron, zone = zone)

    @Test fun nothingEarlierTodayIsNull() {
        assertNull(latest(at(4, 9), listOf(talk(at(3, 22)))))
    }

    @Test fun talkEarlierTodayCarriesTheLearnersOwnWords() {
        val e = latest(at(4, 11), listOf(talk(at(4, 8))))!!
        assertEquals(EarlierToday.Kind.TALK, e.kind)
        assertTrue(e.record.contains("I have a meeting at ten"))
        assertTrue(e.record.contains("about 3 hours ago"))
    }

    @Test fun aTalkWithSomeoneElseIsNotTheFluentSelfsToPickUp() {
        assertNull(latest(at(4, 11), listOf(talk(at(4, 8), counterpart = "p"))))
    }

    @Test fun aLessonSaysWhatWasPractised() {
        val lesson = TutorLessonRecord("l", "Ordering coffee",
            listOf(TutorLessonRecord.Done("ask for a size", "Can I get a large one?")), total = 3, finished = false)
        val e = latest(at(4, 11), listOf(talk(at(4, 8), lesson = lesson)))!!
        assertEquals(EarlierToday.Kind.LESSON, e.kind)
        assertTrue(e.record.contains("Ordering coffee"))
        assertTrue(e.record.contains("1 of 3"))
        assertTrue(e.record.contains("Can I get a large one?"))
    }

    @Test fun aPronunciationDrillAfterTheTalkWinsAndNamesTheHardWords() {
        val takes = listOf(
            take(at(4, 9, 0), listOf("think" to 40, "is" to 95)),
            take(at(4, 9, 5), listOf("three" to 55, "Think" to 50)),
            take(at(4, 9, 6), listOf("hello" to 90), surface = "shadow"),
        )
        val e = latest(at(4, 12), listOf(talk(at(4, 8))), takes)!!
        assertEquals(EarlierToday.Kind.PRONUNCIATION, e.kind)
        assertTrue(e.record.contains("2 sentences"))
        assertTrue(e.record.contains("\"think\", \"three\""))
        assertFalse(e.record.contains("\"is\""))
    }

    @Test fun aTalkAfterTheDrillWins() {
        val e = latest(at(4, 12), listOf(talk(at(4, 8))), listOf(take(at(4, 7), listOf("think" to 40))))
        assertEquals(EarlierToday.Kind.TALK, e?.kind)
    }

    private fun eightToday(): Long =
        LocalDate.now().atTime(8, 0).atZone(ZoneId.systemDefault()).toInstant().toEpochMilli()

    private fun opener(language: String, earlier: EarlierToday?, talked: Boolean, at: Long) =
        FreeTalkOpeners.callOpener(language, earlier, talked, at, stored = { null }, used = { emptyList() })

    @Test fun firstTalkOfTheDayIsTheHelloForTheTimeOfDay() {
        val pick = opener("en", null, false, eightToday())
        assertEquals("Hi, did you sleep well?", pick.first)
        assertNull(pick.second)
    }

    @Test fun aSecondCallNeverAsksAboutSleepAgain() {
        val now = eightToday()
        val earlier = EarlierToday(EarlierToday.Kind.TALK, "k", now - 3_600_000, "A talk.")
        assertNotEquals("Hi, did you sleep well?", opener("en", earlier, true, now).first)
        // Only a talk with someone else earlier: still not the first hello.
        assertEquals(FreeTalkOpeners.againLine("en"), opener("en", null, true, now).first)
    }

    @Test fun aWrittenLineIsUsedOnceForItsActivity() {
        val now = eightToday()
        val earlier = EarlierToday(EarlierToday.Kind.LESSON, "k", now - 3_600_000, "A lesson.")
        val stored = FreeTalkOpeners.Companion.SameDayOpener("k", "en", "Hi again! Did you order like that yet?")
        val fresh = FreeTalkOpeners.callOpener("en", earlier, true, now, stored = { stored }, used = { emptyList() })
        assertEquals(stored.line to "k", fresh)
        val used = FreeTalkOpeners.callOpener("en", earlier, true, now, stored = { stored }, used = { listOf("k") })
        assertEquals(FreeTalkOpeners.againLine("en"), used.first)
    }

    @Test fun aTalkCutOffMinutesAgoIsCarriedOn() {
        val now = System.currentTimeMillis()
        val earlier = EarlierToday(EarlierToday.Kind.TALK, "k", now - 120_000, "A talk.")
        assertEquals(FreeTalkOpeners.resumeLine("ko"), opener("ko", earlier, true, now).first)
    }

    @Test fun freeTalkPromptCarriesEarlierTodayOnlyWhenThereIsOne() {
        fun prompt(e: EarlierToday?) = ConversationEngine.conversationSystemPrompt(
            targetLanguage = "en", nativeLanguage = "ko", level = CefrLevel.B1, topPatterns = emptyList(),
            weakVocabAreas = emptyList(), topic = "", earlierToday = e)
        val earlier = EarlierToday(EarlierToday.Kind.TALK, "k", System.currentTimeMillis(),
            "A talk that ended about 2 hours ago.")
        assertFalse(prompt(null).contains("EARLIER TODAY"))
        assertTrue(prompt(null).contains("only a friend's hello for the time of day"))
        val withIt = prompt(earlier)
        assertNotNull(withIt)
        assertTrue(withIt.contains("EARLIER TODAY"))
        assertTrue(withIt.contains("A talk that ended about 2 hours ago."))
        assertTrue(withIt.contains("second call the same day"))
    }
}
