package com.roro.futurevoice.data

import kotlin.math.roundToInt

/**
 * How the routine's Review block splits its count between the four kinds of
 * review (iOS `RoutineReviewMix`, 2026-10-09). Pure, so the shares can be
 * tested and retuned in one place.
 *
 * Shares: words 30% · sentence cards 30% · expressions 25% · shadow 15%.
 * Shadow is the smallest because a line is said out loud and graded — one
 * line is several cards' worth of time — and it is capped at [MAX_SHADOW]
 * whatever the count. A kind with less on hand than its share passes the rest
 * on to the CARD kinds (shadow never absorbs extra: a 20-item block turning
 * into 10 lines to record would be a different sitting from the one planned).
 */
object RoutineReviewMix {
    data class Counts(
        val words: Int = 0,
        val expressions: Int = 0,
        val sentences: Int = 0,
        val shadow: Int = 0,
    ) {
        val total: Int get() = words + expressions + sentences + shadow
    }

    const val MAX_SHADOW = 3

    fun quotas(goal: Int, available: Counts): Counts {
        if (goal <= 0) return Counts()
        // At least one line once the block is big enough to hold a mix.
        val shadowShare = if (goal >= 5) maxOf(1, (goal * 0.15).roundToInt()) else 0
        val shadow = minOf(available.shadow, MAX_SHADOW, shadowShare)
        val cards = goal - shadow
        var words = minOf(available.words, (cards * 0.35).roundToInt())
        var sentences = minOf(available.sentences, (cards * 0.35).roundToInt())
        var expressions = minOf(available.expressions, maxOf(0, cards - words - sentences))

        // Spill what's left, one at a time, to whichever card kind still has
        // something — round-robin so no single kind swallows the remainder.
        var left = goal - (words + sentences + expressions + shadow)
        while (left > 0) {
            var moved = false
            if (left > 0 && words < available.words) { words += 1; left -= 1; moved = true }
            if (left > 0 && sentences < available.sentences) { sentences += 1; left -= 1; moved = true }
            if (left > 0 && expressions < available.expressions) { expressions += 1; left -= 1; moved = true }
            if (!moved) break
        }
        return Counts(words = words, expressions = expressions, sentences = sentences, shadow = shadow)
    }
}
