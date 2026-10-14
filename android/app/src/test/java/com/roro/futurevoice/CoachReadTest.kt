package com.roro.futurevoice

import com.roro.futurevoice.data.StoreJson
import com.roro.futurevoice.talk.CoachRead
import com.roro.futurevoice.talk.SessionSummarizer
import com.roro.futurevoice.talk.Turn
import com.roro.futurevoice.talk.TurnRole
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Coach mode is judged per line: only a line READ off the "try saying" is
 * practice; an answer in the learner's own words, or one built around the
 * word hint, is evidence (iOS `CoachReadTests`, `CoachRead`, 2026-10-14).
 */
class CoachReadTest {
    private val line = "I usually get up at [7] on weekdays."

    @Test fun readingTheSuggestionIsRead() {
        assertTrue(CoachRead.isRead("I usually get up at 7 on weekdays.", line))
        // The faded example is theirs to swap.
        assertTrue(CoachRead.isRead("I usually get up at six thirty on weekdays", line))
    }

    @Test fun ownWordsAreNotRead() {
        assertFalse(CoachRead.isRead("Honestly I sleep in, my job starts at noon.", line))
        // Read the start, then carried on in their own words.
        assertFalse(CoachRead.isRead(
            "I usually get up at 7 on weekdays, but lately my daughter wakes me before that and I can't fall asleep again",
            line))
    }

    @Test fun aShortSuggestionNeverCountsAsRead() {
        assertFalse(CoachRead.isRead("Yes, I do.", "Yes, [I do]."))
    }

    @Test fun noSuggestionIsNeverRead() {
        assertFalse(CoachRead.isRead("I usually get up at 7 on weekdays.", null))
    }

    @Test fun readLineIsNotEvidence() {
        var turn = Turn(role = TurnRole.USER, transcript = "I usually get up at 7 on weekdays.")
        assertTrue(turn.isEvidence)
        turn = turn.copy(coachLine = line)
        assertTrue(turn.readFromCoach)
        assertFalse(turn.isEvidence)
        // Survives a save.
        val back = StoreJson.json.decodeFromString(Turn.serializer(),
            StoreJson.json.encodeToString(Turn.serializer(), turn))
        assertEquals(line, back.coachLine)
        assertFalse(back.isEvidence)
    }

    // ── Android-only checks of the same contract

    @Test fun coachLineIsEncodedOnlyWhenSet() {
        val plain = StoreJson.json.encodeToString(Turn.serializer(),
            Turn(role = TurnRole.USER, transcript = "Hi"))
        assertFalse(plain.contains("coachLine"))
    }

    @Test fun aReadLineIsLabelledInTheSummaryTranscript() {
        val turns = listOf(
            Turn(role = TurnRole.FLUENT_SELF, transcript = "When do you get up?"),
            Turn(role = TurnRole.USER, transcript = "I usually get up at 7 on weekdays.", coachLine = line),
            Turn(role = TurnRole.USER, transcript = "Honestly I sleep in.", coachLine = line),
        )
        assertEquals(
            "[FLUENT_SELF] When do you get up?\n" +
                "[USER_READ] I usually get up at 7 on weekdays.\n" +
                "[USER] Honestly I sleep in.",
            SessionSummarizer.formatTranscript(turns))
    }
}
