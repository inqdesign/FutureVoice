package com.roro.futurevoice

import com.roro.futurevoice.data.DrillIngest
import com.roro.futurevoice.talk.DrillCard
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * "Got it" RETIRES a sentence card (iOS `1ab175d`). The top rung used to
 * carry a 30-day interval, so a card marked known came back, was marked
 * known again, and came back again — nothing ever left the store.
 */
class DrillRetireTest {

    private val now = 1_700_000_000_000L

    private fun card(box: Int, nextReviewAt: Long) = DrillCard(
        sourcePhrase = "I go yesterday", targetPhrase = "I went yesterday",
        reason = "", createdAt = now, nextReviewAt = nextReviewAt, box = box)

    @Test fun theTopRungHasNoReturn() {
        assertEquals(DrillIngest.RETIRED_REVIEW_AT, DrillIngest.nextReviewAt(DrillIngest.MAX_BOX, now))
        // Still gone a year later.
        assertTrue(DrillIngest.nextReviewAt(DrillIngest.MAX_BOX, now) > now + 365L * 86_400_000)
    }

    @Test fun everyOtherRungStillClimbsTheTable() {
        for (box in 0 until DrillIngest.MAX_BOX) {
            assertEquals(now + DrillIngest.intervalMs(box), DrillIngest.nextReviewAt(box, now))
        }
    }

    @Test fun aDelayCanNeverLandOnTheTopRung() {
        assertEquals(DrillIngest.MAX_BOX - 1, DrillIngest.delayBox(DrillIngest.MAX_BOX))
        assertEquals(DrillIngest.MAX_BOX - 1, DrillIngest.delayBox(99))
        assertEquals(0, DrillIngest.delayBox(-1))
        assertEquals(2, DrillIngest.delayBox(2))
    }

    @Test fun cardsRetiredUnderTheOldRuleStopComingBack() {
        val old = card(DrillIngest.MAX_BOX, now + 30L * 86_400_000)
        assertEquals(DrillIngest.RETIRED_REVIEW_AT, DrillIngest.retired(old).nextReviewAt)
        // Nothing below the top rung is touched.
        val waiting = card(3, now + 86_400_000)
        assertEquals(waiting, DrillIngest.retired(waiting))
        assertFalse(DrillIngest.isRetired(waiting))
    }
}
