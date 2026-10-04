package com.roro.futurevoice

import com.roro.futurevoice.data.VocabStore
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * iOS `VocabStore.pickupCandidates` (plan 5.7): off-list words the fluent self
 * came back to across turns lead, then graded words at or above the level
 * (easiest first), then off-list words said once. Nothing capped; the
 * learner's own words never appear.
 */
class PickupOrderTest {
    private val ranks = mapOf("ask" to 0, "usually" to 1, "commute" to 3, "negotiate" to 3)
    private fun order(lemmas: Set<String>, offList: Map<String, Int>, minRank: Int?,
                      excluded: Set<String> = emptySet()) =
        VocabStore.orderPickups(lemmas, offList, minRank, excluded) { ranks[it] }

    @Test fun recurringThenGradedThenSaidOnce() {
        val got = order(
            lemmas = setOf("ask", "usually", "commute", "negotiate", "chore", "boiler", "sublet"),
            offList = mapOf("chore" to 3, "boiler" to 1, "sublet" to 1),
            minRank = 1)
        // "ask" is under the level; "sublet" is not dropped for its spelling.
        assertEquals(listOf("chore", "usually", "commute", "negotiate", "boiler", "sublet"), got)
    }

    @Test fun recurringOrderIsTurnsThenAlphabet() {
        assertEquals(listOf("chore", "dishes", "mop"),
            order(emptySet(), mapOf("mop" to 2, "dishes" to 3, "chore" to 3), null))
    }

    @Test fun theLearnersOwnWordsNeverAppear() {
        val got = order(setOf("usually", "commute"), mapOf("laundry" to 2, "boiler" to 1),
            minRank = null, excluded = setOf("laundry", "commute"))
        assertEquals(listOf("usually", "boiler"), got)
    }

    @Test fun noLevelKeepsEveryGradedWord() {
        assertEquals(listOf("ask", "usually", "commute"),
            order(setOf("commute", "ask", "usually"), emptyMap(), null))
    }
}
