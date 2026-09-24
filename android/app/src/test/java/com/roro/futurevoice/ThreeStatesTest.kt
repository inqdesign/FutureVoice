package com.roro.futurevoice

import com.roro.futurevoice.talk.CarryoverDetector
import com.roro.futurevoice.talk.Carryover
import com.roro.futurevoice.talk.Turn
import com.roro.futurevoice.talk.TurnRole
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Studying → known → used in a talk, and USED outranks KNOWN (iOS
 * `4fc0068`). A claim is what a call is there to check, so a claimed item
 * said out loud is a carryover of its own kind — the wrap-up can then say
 * "you proved what you claimed" rather than filing it as a notebook word.
 */
class ThreeStatesTest {

    private fun said(vararg lines: String) = lines.mapIndexed { i, text ->
        Turn(id = "turn-$i", role = TurnRole.USER, transcript = text, timestamp = 1_000L + i)
    }

    @Test fun aClaimSaidOutLoudIsConfirmed() {
        val out = CarryoverDetector.detect(
            turns = said("I had to commute an hour each way."),
            cards = emptyList(),
            knownWords = listOf("commute"),
            sessionId = "S", sessionStartedAt = 0L)
        assertEquals(1, out.size)
        assertEquals(Carryover.Source.KNOWN_WORD, out[0].source)
        assertEquals("commute", out[0].item)
    }

    @Test fun aClaimedPhraseIsItsOwnSource() {
        val out = CarryoverDetector.detect(
            turns = said("Honestly, it slipped my mind completely."),
            cards = emptyList(),
            knownExpressions = listOf("slipped my mind"),
            sessionId = "S", sessionStartedAt = 0L)
        assertEquals(listOf(Carryover.Source.KNOWN_EXPRESSION), out.map { it.source })
    }

    /** One item, one credit: a word that is both in the notebook and claimed
     *  must not be counted twice. */
    @Test fun theSameWordIsCreditedOnce() {
        val out = CarryoverDetector.detect(
            turns = said("The commute is long."),
            cards = emptyList(),
            studyingWords = listOf("commute"),
            knownWords = listOf("commute"),
            sessionId = "S", sessionStartedAt = 0L)
        assertEquals(1, out.size)
    }

    /** A claim nobody said stays a claim — nothing is credited for holding an
     *  opinion. */
    @Test fun anUnsaidClaimIsNotCredited() {
        val out = CarryoverDetector.detect(
            turns = said("We talked about the weather."),
            cards = emptyList(),
            knownWords = listOf("commute"),
            knownExpressions = listOf("slipped my mind"),
            sessionId = "S", sessionStartedAt = 0L)
        assertTrue(out.isEmpty())
    }
}
