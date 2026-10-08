package com.roro.futurevoice

import com.roro.futurevoice.talk.CoachMode
import com.roro.futurevoice.talk.CoachPlan
import com.roro.futurevoice.talk.GrammarFocus
import com.roro.futurevoice.talk.GrammarFocusRecord
import com.roro.futurevoice.talk.LearnerPattern
import com.roro.futurevoice.talk.LearnerProfile
import com.roro.futurevoice.talk.Session
import com.roro.futurevoice.talk.Turn
import com.roro.futurevoice.talk.TurnRole
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
        // A call where the slip came back has the learner saying it.
        val turns = if (repeats > 0) listOf(Turn(role = TurnRole.USER, transcript = p.mistake)) else emptyList()
        return Session(userId = "U", targetLanguage = "en", startedAt = start, endedAt = start + 600_000,
            turns = turns,
            grammarFocus = GrammarFocusRecord(LearnerProfile.patternKey(p), "L", p.mistake, p.correction, repeats))
    }

    /** A talk in which the learner said [line]. */
    private fun talk(line: String, daysAgo: Double): Session {
        val at = now - (daysAgo * day).toLong()
        return Session(userId = "U", targetLanguage = "en", startedAt = at, endedAt = at + 600_000,
            turns = listOf(Turn(role = TurnRole.USER, transcript = line)))
    }

    private fun picked(ps: List<LearnerPattern>, sessions: List<Session>): String? =
        GrammarFocus.candidates(profile(ps), sessions, now).firstOrNull()?.first?.mistake

    /** The evidence is the transcripts, not the stored frequency: a pattern
     *  at frequency 9 that no talk contains is never a focus (2026-10-08 —
     *  summaries had been copying the profile's patterns back, so the count
     *  rose with nothing said), and one said in two talks is. */
    @Test fun focusNeedsTheSlipInTwoTalks() {
        val inflated = pattern("I go to the office yesterday", 9, 1.0)
        val real = pattern("explain him the", 2, 3.0)
        val talks = listOf(talk("so I will explain him the situation tomorrow", 5.0),
            talk("I had to explain him the plan", 2.0),
            talk("nothing related here", 1.0))
        assertEquals("explain him the", picked(listOf(inflated, real), talks))
        assertEquals(2, GrammarFocus.evidence(real, talks, now))
        assertEquals(0, GrammarFocus.evidence(inflated, talks, now))
        // One talk is not a pattern.
        assertNull(picked(listOf(real), talks.takeLast(2)))
        // A talk older than FRESH_DAYS doesn't count.
        val old = listOf(talk("explain him the plan", 50.0), talks[1])
        assertNull(picked(listOf(real), old))
    }

    @Test fun mostTalksFirst() {
        val a = pattern("a slip", 9, 1.0)
        val b = pattern("b slip", 2, 1.0)
        val talks = listOf(talk("a slip one", 1.0), talk("a slip two", 2.0),
            talk("b slip one", 1.0), talk("b slip two", 2.0), talk("b slip three", 3.0))
        assertEquals("b slip", picked(listOf(a, b), talks))
    }

    @Test fun twoCleanCallsRetireAndARedetectionBringsItBack() {
        val often = pattern("often slip", 5, 10.0)
        val some = pattern("some slip", 2, 1.0)
        val said = listOf(talk("often slip", 20.0), talk("often slip", 15.0),
            talk("some slip", 12.0), talk("some slip", 11.0))
        val clean = said + listOf(focused(often, 0, 5.0), focused(often, 0, 2.0))
        assertEquals("some slip", picked(listOf(often, some), clean))
        // One of the two still had the slip — not retired.
        val mixed = said + listOf(focused(often, 0, 5.0), focused(often, 2, 2.0))
        assertEquals("often slip", picked(listOf(often, some), mixed))
        // Said again after those clean calls (a summary re-detects it) → back in focus.
        val back = pattern("often slip", 6, 1.0)
        assertEquals("often slip", picked(listOf(back, some), clean + talk("often slip", 1.0)))
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
