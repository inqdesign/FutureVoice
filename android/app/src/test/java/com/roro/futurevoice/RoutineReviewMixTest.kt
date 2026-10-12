package com.roro.futurevoice

import com.roro.futurevoice.data.RoutineReviewMix
import com.roro.futurevoice.data.RoutineReviewMix.Counts as C
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** iOS `RoutineReviewMixTests`. */
class RoutineReviewMixTest {
    @Test fun plentyOfEverythingSplitsByShare() {
        val q = RoutineReviewMix.quotas(20, C(words = 50, expressions = 50, sentences = 50, shadow = 10))
        assertEquals(C(words = 6, expressions = 5, sentences = 6, shadow = 3), q)
    }

    /** The reported case: a big sentence backlog no longer takes every slot. */
    @Test fun sentenceBacklogDoesNotCrowdOutWords() {
        val q = RoutineReviewMix.quotas(20, C(words = 10, expressions = 4, sentences = 80, shadow = 3))
        assertEquals(20, q.total)
        assertTrue(q.words >= 6)
        assertEquals(4, q.expressions)
        assertEquals(3, q.shadow)
    }

    @Test fun missingKindSpillsToCardsNotShadow() {
        val q = RoutineReviewMix.quotas(20, C(words = 30, expressions = 0, sentences = 30, shadow = 10))
        assertEquals(C(words = 9, expressions = 0, sentences = 8, shadow = 3), q)
    }

    @Test fun shortSupplyGivesWhatThereIs() {
        val q = RoutineReviewMix.quotas(20, C(words = 2, expressions = 1, sentences = 0, shadow = 0))
        assertEquals(C(words = 2, expressions = 1, sentences = 0, shadow = 0), q)
    }

    @Test fun smallBlockHasNoShadow() {
        val q = RoutineReviewMix.quotas(4, C(words = 9, expressions = 9, sentences = 9, shadow = 9))
        assertEquals(0, q.shadow)
        assertEquals(4, q.total)
    }
}
