package com.roro.futurevoice

import com.roro.futurevoice.data.CefrLevel
import com.roro.futurevoice.talk.ConversationEngine
import com.roro.futurevoice.talk.TutorLesson
import com.roro.futurevoice.talk.TutorLessonStore
import com.roro.futurevoice.talk.TutorPlanner
import com.roro.futurevoice.talk.TutorPrompts
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
                       fixes: List<String> = emptyList()) =
        ConversationEngine.conversationSystemPrompt(
            targetLanguage = lang, nativeLanguage = "ko", level = level, tutor = tutor,
            tutorLesson = lesson, tutorJustTicked = ticked, tutorLastFixes = fixes)

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
        val l = lesson(3)
        assertTrue(l.isFinished)
        assertEquals(3, l.record.done.size)
        assertTrue(prompt("en", tutor = true, lesson = l).contains("ALL DONE"))
    }

    /** iOS `TutorLessonStore.resumable`: unfinished, not dropped, under 21 days. */
    @Test fun onlyARecentUnfinishedLessonIsPickedUp() {
        val now = 100L * 86_400_000L
        val fresh = lesson(1).copy(createdAt = now - 86_400_000L)
        assertEquals(fresh, TutorLessonStore.resumable(listOf(fresh), now))
        assertNull(TutorLessonStore.resumable(listOf(fresh.copy(droppedAt = now)), now))
        assertNull(TutorLessonStore.resumable(listOf(lesson(3).copy(createdAt = now)), now))
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
