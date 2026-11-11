package com.roro.futurevoice

import com.roro.futurevoice.talk.ShadowScore
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** iOS `ShadowEngineTests` number readings: a year read as written is not a slip. */
class ShadowNumberReadingTest {
    private fun clean(target: String, learner: String) =
        ShadowScore.analyze(target, learner).steps.all { it.op == ShadowScore.DiffOp.MATCH }

    @Test fun yearHeardAsDigitsMatchesItsSpokenForm() {
        assertTrue(clean("in August of nineteen eleven, while the museum was closed",
            "in August of 1911 while the museum was closed"))
    }

    @Test fun numbersMeetWhicheverSideWroteDigits() {
        assertTrue(clean("back in 1911 it was gone", "back in nineteen eleven it was gone"))
        assertTrue(clean("it was nineteen oh five then", "it was 1905 then"))
        assertTrue(clean("we sold one hundred and five tickets", "we sold 105 tickets"))
        assertTrue(clean("we sold 105 tickets", "we sold one hundred and five tickets"))
        assertTrue(clean("room one oh one is free", "room 101 is free"))
        assertTrue(clean("twenty twenty-four was long", "2024 was long"))
        assertTrue(clean("about 1911 people came", "about one thousand nine hundred eleven people came"))
    }

    @Test fun wrongYearIsStillWrong() {
        assertFalse(clean("in nineteen eleven", "in 1912"))
    }
}
