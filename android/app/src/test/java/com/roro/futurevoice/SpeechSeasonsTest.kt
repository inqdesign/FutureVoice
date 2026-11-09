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

    @Test fun eachSeasonHasItsOwnBar() {
        assertEquals(80, SpeechChallenges.boardBar(null))
        assertEquals(80, SpeechChallenges.boardBar(1))
        assertEquals(60, SpeechChallenges.boardBar(2))
        assertEquals(Entry.BelowBar, keptOff(overall = 79))
        assertNull(keptOff(overall = 80))
        assertEquals(Entry.BelowBar, keptOff(season = 2, scoring = 6, hasReading = true, overall = 59))
        assertNull(keptOff(season = 2, scoring = 6, hasReading = true, overall = 60))
    }
}
