package com.roro.futurevoice

import com.roro.futurevoice.data.SpeechChallenges
import com.roro.futurevoice.data.SpeechChallenges.Entry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** The gates of iOS `SpeechChallenges.enter`, in their order. */
class SpeechSeasonsTest {
    private fun keptOff(past: Boolean = false, season: Int? = 1, scoring: Int? = 3, hasReading: Boolean = false,
                        onCamera: Boolean = true, overall: Int = 90) =
        SpeechChallenges.keptOff(past, season, scoring, hasReading, onCamera, overall)

    @Test fun anEndedChallengeIsPracticeWhateverTheTake() {
        assertEquals(Entry.Practice, keptOff(past = true))
        assertEquals(Entry.Practice, keptOff(past = true, season = 2, scoring = 6, hasReading = true, onCamera = false, overall = 10))
    }

    @Test fun aReadingScoreStaysOffASeasonOneBoard() {
        assertEquals(Entry.NewScoring, keptOff(scoring = 6, hasReading = true))
        assertEquals(Entry.NewScoring, keptOff(season = null, scoring = 6, hasReading = true))
    }

    @Test fun aSeasonTwoBoardNeedsAReadingScore() {
        assertEquals(Entry.Failed, keptOff(season = 2, scoring = 3))
        assertEquals(Entry.Failed, keptOff(season = 2, scoring = 6, hasReading = false))
        assertNull(keptOff(season = 2, scoring = 6, hasReading = true))
    }

    @Test fun theCameraComesBeforeTheBar() {
        assertEquals(Entry.CameraOff, keptOff(onCamera = false, overall = 10))
    }

    /** iOS picks by `take.uuid.15`, the id's last byte, so a take keeps its line. */
    @Test fun aTakeKeepsItsVerdictLine() {
        val index = com.roro.futurevoice.ui.speech.SpeechVerdict::index
        assertEquals(0, index("5BEEC000-0000-4000-8000-0000000000FF", 5))   // 255 % 5
        assertEquals(1, index("5BEEC000-0000-4000-8000-0000000000FB", 5))   // 251 % 5
        assertEquals(2, index("5beec000-0000-4000-8000-000000000007", 5))
    }

    @Test fun findingsLandOnTheScriptWordThatOwnsTheirToken() {
        val op = com.roro.futurevoice.talk.ShadowScore.DiffOp.MATCH
        fun mark(w: String) = com.roro.futurevoice.talk.SpeechAnalyzer.ScriptMark(w, op, null)
        val marks = listOf(listOf(mark("A"), mark("well-known")), listOf(mark("—"), mark("word")))
        val score = com.roro.futurevoice.talk.SpeechReadingScore(
            version = 6, gender = "male",
            parts = com.roro.futurevoice.talk.SpeechReadingScore.Parts(50, 50, 50, 50, 50), coverage = 1.0,
            speed = 1.0, rhythm = 1.0, pausesPer100 = 0.0, slipsPer100 = 0.0, slips = 0,
            // Tokens: a(0) well(1) known(2) word(3).
            extraPauses = listOf(com.roro.futurevoice.talk.SpeechReadingScore.Pause("known", 0.4, 2)),
            held = listOf(com.roro.futurevoice.talk.SpeechReadingScore.Held("word", 3.0, 0.9, 0.2, 3)),
            missed = emptyList(), weakest = emptyList(),
        )
        val (held, pauses) = com.roro.futurevoice.ui.speech.readingTiming(score, marks)
        assertEquals(mapOf(3 to 0.9), held)
        assertEquals(mapOf(1 to 0.4), pauses)
    }

    @Test fun eachSeasonHasItsOwnBar() {
        assertEquals(80, SpeechChallenges.boardBar(null))
        assertEquals(80, SpeechChallenges.boardBar(1))
        assertEquals(83, SpeechChallenges.boardBar(2))
        assertEquals(Entry.BelowBar, keptOff(overall = 79))
        assertNull(keptOff(overall = 80))
        assertEquals(Entry.BelowBar, keptOff(season = 2, scoring = 6, hasReading = true, overall = 82))
        assertNull(keptOff(season = 2, scoring = 6, hasReading = true, overall = 83))
    }
}
