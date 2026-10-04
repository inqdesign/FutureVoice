package com.roro.futurevoice

import com.roro.futurevoice.net.WeekRecapCoach
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

/**
 * The coach's read is only shown as far as the learner's own lines bear it
 * out — these pin the checks in `WeekRecapCoach.verified` (iOS
 * `WeekRecapCoachTests`, `633418f`).
 */
class WeekRecapCoachTest {

    private val lines = listOf(
        "Yesterday I went to the new flat and the landlord says it's fine.",
        "Then she ask me if I want to sign the contract today.",
        "I end up carrying most boxes myself.",
        "I was very tired after the move, very very tired.",
        "It's good, I think it's good for me.",
    )

    private val json = Json { ignoreUnknownKeys = true }
    private fun payload(s: String) = json.decodeFromString(WeekRecapCoach.Payload.serializer(), s)

    @Test fun patternNeedsTwoExamplesTheLearnerActuallySaid() {
        val r = payload("""
        {"headline": "h", "grammar": [
          {"rule": "past tense", "tip": "t", "examples": [
            {"was": "the landlord says it's fine", "now": "the landlord said it was fine"},
            {"was": "she ask me", "now": "she asked me"},
            {"was": "he go home", "now": "he went home"}]},
          {"rule": "seen once", "tip": "t", "examples": [
            {"was": "I end up carrying", "now": "I ended up carrying"},
            {"was": "we was late", "now": "we were late"}]}
        ]}
        """)
        val coach = WeekRecapCoach.verified(r, lines)
        assertEquals("a point with one real sentence is not a pattern", 1, coach.grammar.size)
        assertEquals("an example the learner never said is dropped",
            listOf("the landlord says it's fine", "she ask me"), coach.grammar[0].examples.map { it.was })
    }

    @Test fun upgradeIsCountedHereAndItsLineMustBeTheirs() {
        val r = payload("""
        {"headline": "h", "upgrades": [
          {"instead": "very tired", "better": "exhausted",
           "original": "I was very tired after the move, very very tired.",
           "rewritten": "I was exhausted after the move.", "note": "n"},
          {"instead": "good", "better": "decent",
           "original": "The flat is good for the price.", "rewritten": "The flat is decent.", "note": "n"},
          {"instead": "contract", "better": "lease", "original": "", "rewritten": "", "note": "n"},
          {"instead": "tired", "better": "Tired", "original": "", "rewritten": "", "note": "n"}
        ]}
        """)
        val coach = WeekRecapCoach.verified(r, lines)
        assertEquals(listOf("very tired", "good"), coach.upgrades.map { it.instead })
        assertEquals(2, coach.upgrades[0].count)
        assertEquals(2, coach.upgrades[1].count)
        assertEquals("an invented example line is not shown", "", coach.upgrades[1].original)
    }

    @Test fun countingIsWholeWords() {
        assertEquals(2, WeekRecapCoach.occurrences("good", listOf("goodbye, good day", "Good.")))
    }

    @Test fun insightQuoteMustBeTheirs() {
        val invented = WeekRecapCoach.verified(
            payload("""{"headline": "h", "insight": "i", "insight_quote": "I never said this"}"""), lines)
        assertEquals("", invented.insightQuote)
        val real = WeekRecapCoach.verified(
            payload("""{"headline": "h", "insight": "i", "insight_quote": "It's good, I think it's good for me."}"""), lines)
        assertFalse(real.insightQuote.isEmpty())
    }

    @Test fun unspacedLanguageCountsSubstrings() {
        assertEquals(3, WeekRecapCoach.occurrences("すごい", listOf("すごいすごい", "それはすごいね"), "ja"))
    }
}
