package com.roro.futurevoice

import com.roro.futurevoice.talk.CoachMode
import com.roro.futurevoice.talk.CoachPlan
import com.roro.futurevoice.talk.GrammarFocus
import com.roro.futurevoice.talk.GrammarFocusRecord
import com.roro.futurevoice.talk.LearnerPattern
import com.roro.futurevoice.talk.LearnerProfile
import com.roro.futurevoice.talk.Session
import com.roro.futurevoice.ui.TalkGoalItem
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** iOS `CoachPlanTests` (7c12b9e): the ration, in code. */
class CoachPlanTest {
    private fun item(w: String) = TalkGoalItem(key = w, text = w, isWord = true)

    @Test fun mayHintFromTheFirstLine() = assertTrue(CoachPlan().mayHint)

    @Test fun plainLinesBetweenHints() {
        var plan = CoachPlan().replyFinished().hintShown(item("rest"))
        assertFalse(plan.mayHint)
        plan = plan.replyFinished()
        assertFalse(plan.mayHint)
        plan = plan.replyFinished()
        assertTrue(plan.mayHint)
    }

    @Test fun hintedItemsLeaveTheCandidates() {
        val plan = CoachPlan().hintShown(item("rest"))
        assertEquals(listOf("plug"), plan.candidates(listOf(item("rest"), item("plug"))).map { it.key })
    }

    @Test fun candidatesCapped() {
        val many = (0 until 20).map { item("w$it") }
        assertEquals(CoachMode.MAX_CANDIDATES, CoachPlan().candidates(many).size)
    }

    @Test fun cappedPerCall() {
        var plan = CoachPlan()
        var shown = 0
        for (i in 0 until 30) {
            if (plan.mayHint) { plan = plan.hintShown(item("w$i")); shown++ }
            plan = plan.replyFinished()
        }
        assertEquals(CoachPlan.MAX_HINTS, shown)
    }

    @Test fun questionDetectionAcrossScripts() {
        assertTrue(CoachPlan.endsInQuestion("それ、どうだった？"))
        assertTrue(CoachPlan.endsInQuestion("그래서 어땠어? "))
        assertTrue(CoachPlan.endsInQuestion("\"Why not?\""))
        assertFalse(CoachPlan.endsInQuestion("Why? I get it."))
    }

    /** iOS `CoachModeDefaultTests`: on for beginners until the learner flips it. */
    @Test fun levelDecidesUntilTheLearnerChooses() {
        assertTrue(CoachMode.resolve(null, "a1"))
        assertTrue(CoachMode.resolve(null, "a2"))
        assertFalse(CoachMode.resolve(null, "b1"))
        assertFalse(CoachMode.resolve(null, ""))
        assertFalse(CoachMode.resolve(false, "a1"))
        assertTrue(CoachMode.resolve(true, "c1"))
    }
}

/** iOS `GrammarFocusTests`: which recurring mistake a call focuses on, and when one retires. */
class GrammarFocusTest {
    private val now = 1_790_000_000_000L
    private val day = 86_400_000L

    private fun pattern(m: String, freq: Int, daysAgo: Double) = LearnerPattern(
        mistake = m, correction = "$m!", context = "ctx", frequency = freq,
        lastSeenAt = now - (daysAgo * day).toLong())

    private fun profile(ps: List<LearnerPattern>) =
        LearnerProfile(userId = "U", targetLanguage = "en", recurringMistakes = ps)

    private fun focused(p: LearnerPattern, repeats: Int, daysAgo: Double): Session {
        val start = now - (daysAgo * day).toLong()
        return Session(userId = "U", targetLanguage = "en", startedAt = start, endedAt = start + 600_000,
            grammarFocus = GrammarFocusRecord(LearnerProfile.patternKey(p), "L", p.mistake, p.correction, repeats))
    }

    @Test fun picksMostFrequentFreshPattern() {
        val picked = GrammarFocus.pick(profile(listOf(pattern("once", 1, 1.0), pattern("often", 5, 3.0),
            pattern("some", 2, 1.0), pattern("stale", 9, 60.0))), emptyList(), now)
        assertEquals("often", picked?.mistake)
    }

    @Test fun nothingWhenNoPatternRepeats() =
        assertNull(GrammarFocus.pick(profile(listOf(pattern("once", 1, 1.0))), emptyList(), now))

    @Test fun twoCleanCallsRetireAndARedetectionBringsItBack() {
        val often = pattern("often", 5, 10.0)
        val some = pattern("some", 2, 1.0)
        val clean = listOf(focused(often, 0, 5.0), focused(often, 0, 2.0))
        assertEquals("some", GrammarFocus.pick(profile(listOf(often, some)), clean, now)?.mistake)
        val mixed = listOf(focused(often, 0, 5.0), focused(often, 2, 2.0))
        assertEquals("often", GrammarFocus.pick(profile(listOf(often, some)), mixed, now)?.mistake)
        val back = pattern("often", 6, 1.0)
        assertEquals("often", GrammarFocus.pick(profile(listOf(back, some)), clean, now)?.mistake)
    }

    /** iOS `GrammarFocusPairTests`: the strip shows only what changed, with a word of context. */
    @Test fun compactKeepsTheChangeAndOneWord() {
        assertEquals("…I go to…" to "…I went to…",
            GrammarFocus.compact("Yesterday I go to the office", "Yesterday I went to the office"))
        assertEquals("…meeting in Monday." to "…meeting on Monday.",
            GrammarFocus.compact("I have a meeting in Monday.", "I have a meeting on Monday."))
    }

    @Test fun unspacedComparesCharacters() =
        assertEquals("…に行く。" to "…に行った。", GrammarFocus.compact("昨日学校に行く。", "昨日学校に行った。"))

    @Test fun nothingSharedKeepsBoth() = assertEquals("goed" to "went", GrammarFocus.compact("goed", "went"))
}
