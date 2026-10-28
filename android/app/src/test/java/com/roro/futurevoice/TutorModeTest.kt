package com.roro.futurevoice

import com.roro.futurevoice.data.CefrLevel
import com.roro.futurevoice.data.StoreJson
import com.roro.futurevoice.talk.ConversationEngine
import com.roro.futurevoice.talk.ScorecardMetrics
import com.roro.futurevoice.talk.Session
import com.roro.futurevoice.talk.SessionSummarizer
import com.roro.futurevoice.talk.Turn
import com.roro.futurevoice.talk.TurnRole
import com.roro.futurevoice.talk.TutorCurriculum
import com.roro.futurevoice.talk.TutorFinalCheck
import com.roro.futurevoice.talk.TutorLesson
import com.roro.futurevoice.talk.TutorLessonStore
import com.roro.futurevoice.talk.TutorPlanner
import com.roro.futurevoice.talk.TutorPrompts
import com.roro.futurevoice.talk.TutorTopicProgress
import com.roro.futurevoice.talk.TutorTurnRole
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** iOS `TutorModeTests` (b3a6d30f, rebuilt af3c7ffe): tutor mode rides only
 *  on a call that turned it on; every other prompt is unchanged. */
class TutorModeTest {
    private fun prompt(lang: String, tutor: Boolean, level: CefrLevel = CefrLevel.B1,
                       lesson: TutorLesson? = null, ticked: Boolean = false,
                       fixes: List<String> = emptyList(), planning: Boolean = false) =
        ConversationEngine.conversationSystemPrompt(
            targetLanguage = lang, nativeLanguage = "ko", level = level, tutor = tutor,
            tutorLesson = lesson, tutorJustTicked = ticked, tutorLastFixes = fixes,
            tutorPlanning = planning)

    private fun lesson(done: Int, total: Int = 3) = TutorLesson(
        title = "자기소개", titleTarget = "Introducing yourself", language = "en",
        challenges = (0 until total).map { i ->
            TutorLesson.Challenge(goal = "goal $i", task = "Task $i", example = "Example $i.",
                doneAt = if (i < done) 1L else null, line = if (i < done) "line $i" else null)
        },
        createdAt = System.currentTimeMillis())

    @Test fun offLeavesThePromptAlone() {
        val off = prompt("en", tutor = false)
        assertFalse(off.contains("TUTOR MODE"))
        assertTrue(off.contains("Never correct the user mid-conversation."))
        assertTrue(off.endsWith("(1) is only about not monologuing."))
    }

    @Test fun onReplacesTheNoCorrectionRuleAndComesLast() {
        for (level in listOf(CefrLevel.A2, CefrLevel.B1)) {
            val on = prompt("en", tutor = true, level = level)
            assertFalse(on.contains("Never correct the user mid-conversation."))
            assertTrue(on.contains("TUTOR MODE"))
            // Last, after the beginner rules it outranks.
            assertTrue(on.endsWith("All of it in English only, like everything else."))
        }
    }

    @Test fun carriesTheLanguageGuards() {
        assertTrue(prompt("ko", tutor = true).contains("ASR SPACING GUARD"))
        assertTrue(prompt("ko", tutor = true).contains("SPEECH LEVEL is the learner's choice"))
    }

    @Test fun noLessonAsksForATopicAndDropsTheFreeTalkBlocks() {
        val on = prompt("en", tutor = true)
        assertTrue(on.contains("NO TOPIC YET"))
        assertFalse(on.contains("THEY CALLED YOU"))
    }

    @Test fun lessonMarksTheCurrentChallengeAndTheTick() {
        val mid = prompt("en", tutor = true, lesson = lesson(1), ticked = true,
            fixes = listOf("\"I am live\" → \"I live\""))
        assertTrue(mid.contains("[DONE] 1. Task 0"))
        assertTrue(mid.contains("[NOW ] 2. Task 1"))
        assertTrue(mid.contains("You are on challenge 2"))
        assertTrue(mid.contains("just checked off challenge 1"))
        assertTrue(mid.contains("I am live"))
        val quiet = prompt("en", tutor = true, lesson = lesson(1))
        assertFalse(quiet.contains("just checked off"))
    }

    @Test fun finishedLessonSaysGoodbye() {
        val l = lesson(3).copy(finishedAt = 2L)
        assertTrue(l.isFinished)
        assertEquals(3, l.record.done.size)
        val p = prompt("en", tutor = true, lesson = l)
        assertTrue(p.contains("ALL DONE"))
        assertTrue(p.contains("never call it great, perfect or flawless"))
    }

    /** iOS `testLastTickOpensTheFinalCheck` (23ce515f). */
    @Test fun lastTickOpensTheFinalCheck() {
        val l = lesson(3)
        assertFalse(l.isFinished)
        assertTrue(l.inFinalCheck)
        val p = prompt("en", tutor = true, lesson = l, ticked = true)
        assertTrue(p.contains("Now the FINAL CHECK"))
        assertTrue(p.contains("They can't skip it"))
        assertTrue(p.contains("start the FINAL CHECK above"))
        assertTrue(p.contains("  1. Task 0\n  2. Task 1"))
        assertFalse(p.contains("ALL DONE"))
    }

    /** iOS `testFinalCheckOutcome`. */
    @Test fun finalCheckOutcome() {
        fun o(v: TutorFinalCheck.Verdict, slips: Int = 0, used: Boolean = false) =
            TutorFinalCheck.outcome(v, slips, used)
        assertEquals(TutorFinalCheck.Outcome.NOT_AN_ATTEMPT, o(TutorFinalCheck.Verdict(attempt = false)))
        assertEquals(TutorFinalCheck.Outcome.NOT_YET, o(TutorFinalCheck.Verdict(attempt = true, missing = listOf(2), understood = true)))
        assertEquals(TutorFinalCheck.Outcome.NOT_YET, o(TutorFinalCheck.Verdict(attempt = true, missing = emptyList(), understood = false)))
        // A clean first try passes.
        assertEquals(TutorFinalCheck.Outcome.PASS, o(TutorFinalCheck.Verdict(attempt = true, missing = emptyList(), understood = true, shaky = false)))
        // Not perfect the first time (any slip, or shaky) asks once more, once.
        assertEquals(TutorFinalCheck.Outcome.ONCE_MORE, o(TutorFinalCheck.Verdict(attempt = true, understood = true, shaky = false), slips = 1))
        assertEquals(TutorFinalCheck.Outcome.ONCE_MORE, o(TutorFinalCheck.Verdict(attempt = true, understood = true, shaky = true)))
        // The second try passes with slips; they are named, not failed.
        assertEquals(TutorFinalCheck.Outcome.PASS, o(TutorFinalCheck.Verdict(attempt = true, understood = true, shaky = false), slips = 2, used = true))
        assertEquals(TutorFinalCheck.Outcome.PASS, o(TutorFinalCheck.Verdict(attempt = true, understood = true, shaky = true), used = true))
    }

    /** iOS `testNextRoundBeingPlannedHoldsTheTutor`. */
    @Test fun nextRoundBeingPlannedHoldsTheTutor() {
        val passed = lesson(3).copy(finishedAt = 2L)
        val p = prompt("en", tutor = true, lesson = passed, ticked = true, planning = true)
        assertTrue(p.contains("BEING SET UP"))
        assertTrue(p.contains("next round of \"Introducing yourself\""))
        assertFalse(p.contains("ALL DONE"))
        assertFalse(p.contains("has just checked off"))
    }

    private fun line(text: String, role: TutorTurnRole?) =
        Turn(role = TurnRole.USER, transcript = text, tutorRole = role)

    private fun session(turns: List<Turn>, coached: Boolean? = null) = Session(
        id = StoreJson.newId(), userId = "U", targetLanguage = "en",
        startedAt = 0L, endedAt = 1L, turns = turns, coached = coached)

    /** iOS `testOnlyTheFinalCheckIsEvidence` (6cc2ab2a). */
    /** iOS `testCurriculumNextPrefersAnOpenCheckThenLitTopics` (23ce515f). */
    @Test fun curriculumNextPrefersAnOpenCheckThenLitTopics() {
        assertEquals(10, TutorCurriculum.chapters.size)
        assertEquals(100, TutorCurriculum.chapters.flatMap { c -> c.topics.map { it.id } }.toSet().size)
        assertEquals("meet.intro", TutorCurriculum.next(emptyMap(), CefrLevel.A1)?.topic?.id)
        val now = System.currentTimeMillis()
        val p = mutableMapOf("meet.intro" to TutorTopicProgress(passedAt = now, rounds = 1, touchedAt = now))
        assertEquals("meet.work", TutorCurriculum.next(p, CefrLevel.A1)?.topic?.id)
        p["cafe.order"] = TutorTopicProgress(startedAt = now, lessonDoneAt = now, touchedAt = now)
        assertEquals("cafe.order", TutorCurriculum.next(p, CefrLevel.A1)?.topic?.id)
        val stepUp = TutorCurriculum.topic("cafe.wrong")!!.topic
        assertTrue(TutorCurriculum.isStepUp(stepUp, CefrLevel.A2))
        assertFalse(TutorCurriculum.isStepUp(stepUp, CefrLevel.B1))
        assertEquals("Café & food: Your order came out wrong", TutorCurriculum.request("cafe.wrong"))
    }

    @Test fun onlyTheFinalCheckIsEvidence() {
        assertFalse(line("My name is Min.", TutorTurnRole.DRILL).isEvidence)
        assertTrue(line("Hi, I'm Min, from Seoul, I work in design.", TutorTurnRole.CHECK).isEvidence)
        assertTrue(line("Just talking.", null).isEvidence)
    }

    /** iOS `testATutorCallIsScoredOnlyOnceItReachedTheCheck`. */
    @Test fun aTutorCallIsScoredOnlyOnceItReachedTheCheck() {
        val drills = session(listOf(line("My name is Min.", TutorTurnRole.DRILL),
            line("I'm from Seoul.", TutorTurnRole.DRILL)))
        assertTrue(drills.isPractice)
        val checked = session(listOf(line("My name is Min.", TutorTurnRole.DRILL),
            line("Hi, I'm Min, I'm from Seoul.", TutorTurnRole.CHECK)))
        assertFalse(checked.isPractice)
        assertEquals(1, ScorecardMetrics.compute(checked.turns).userTurnCount)
        // A tutor call saved before the per-line rule stays practice.
        assertTrue(session(checked.turns, coached = true).isPractice)
    }

    /** iOS `testDrillLinesAreLabelledForTheSummary`. */
    @Test fun drillLinesAreLabelledForTheSummary() {
        val text = SessionSummarizer.formatTranscript(listOf(line("My name is Min.", TutorTurnRole.DRILL),
            line("Hi, I'm Min.", TutorTurnRole.CHECK)))
        assertEquals("[USER_DRILL] My name is Min.\n[USER] Hi, I'm Min.", text)
    }

    /** iOS `testTutorRoleRoundTrips`; an unknown role reads as none. */
    @Test fun tutorRoleRoundTrips() {
        val json = StoreJson.json.encodeToString(Turn.serializer(), line("Hi.", TutorTurnRole.CHECK))
        assertEquals(TutorTurnRole.CHECK, StoreJson.json.decodeFromString(Turn.serializer(), json).tutorRole)
        val plain = StoreJson.json.encodeToString(Turn.serializer(), line("Hi.", null))
        assertFalse(plain.contains("tutorRole"))
        val odd = json.replace("\"check\"", "\"chapter\"")
        assertNull(StoreJson.json.decodeFromString(Turn.serializer(), odd).tutorRole)
    }

    /** iOS `TutorLessonStore.resumable`: unfinished, not dropped, under 21 days. */
    @Test fun onlyARecentUnfinishedLessonIsPickedUp() {
        val now = 100L * 86_400_000L
        val fresh = lesson(1).copy(createdAt = now - 86_400_000L)
        assertEquals(fresh, TutorLessonStore.resumable(listOf(fresh), now))
        assertNull(TutorLessonStore.resumable(listOf(fresh.copy(droppedAt = now)), now))
        assertNull(TutorLessonStore.resumable(listOf(lesson(3).copy(createdAt = now, finishedAt = now)), now))
        // Every challenge done but the final check still open: picked up.
        val inCheck = lesson(3).copy(createdAt = now)
        assertEquals(inCheck, TutorLessonStore.resumable(listOf(inCheck), now))
        assertNull(TutorLessonStore.resumable(listOf(fresh.copy(createdAt = now - 22 * 86_400_000L)), now))
    }

    /** iOS `TutorPlanner.plan`'s checks: a topic, a title, at least two whole challenges, at most four. */
    @Test fun plannerKeepsOnlyAWholeLesson() {
        fun item(g: String, t: String) = TutorPlanner.Plan.Item(g, t, " ex ")
        assertNull(TutorPlanner.lesson(TutorPlanner.Plan(topic = false), "en"))
        assertNull(TutorPlanner.lesson(TutorPlanner.Plan(topic = true, title = " ",
            challenges = listOf(item("a", "b"), item("c", "d"))), "en"))
        assertNull(TutorPlanner.lesson(TutorPlanner.Plan(topic = true, title = "T",
            challenges = listOf(item("a", "b"), item("", "d"))), "en"))
        val l = TutorPlanner.lesson(TutorPlanner.Plan(topic = true, title = " T ",
            challenges = (1..6).map { item("g$it", "t$it") }), "en")
        assertNotNull(l)
        assertEquals("T", l!!.title)
        assertEquals("T", l.titleTarget)
        assertEquals(4, l.challenges.size)
        assertEquals("ex", l.challenges[0].example)
    }

    @Test fun plannerHearsAnAnswerAsAnAnswer() {
        assertEquals("They picked on screen: \"Ordering\"", TutorPlanner.content("Ordering", null))
        assertEquals("The tutor asked: \"What?\"\nThey answered: \"yes\"", TutorPlanner.content("yes", "What?"))
        assertTrue(TutorPrompts.levelLadder(CefrLevel.B1).contains("An everyday transaction"))
        assertFalse(TutorPrompts.levelLadder(CefrLevel.A2).contains("An everyday transaction"))
        assertTrue(TutorPrompts.levelLadder(CefrLevel.C2).contains(":\nC2 — managing"))
    }
}
