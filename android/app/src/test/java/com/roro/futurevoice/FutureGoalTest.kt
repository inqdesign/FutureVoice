package com.roro.futurevoice

import com.roro.futurevoice.data.FutureGoal
import com.roro.futurevoice.data.LearningPurpose
import com.roro.futurevoice.data.StoreJson
import com.roro.futurevoice.talk.ConversationPrompt
import com.roro.futurevoice.talk.UserPersona
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** "Imagine your future" (iOS 3d655c8b): the goal ids, their prompt lines,
 *  and a persona on disk from before the field. */
class FutureGoalTest {
    @Test fun idsAreIosAllCasesInOrder() {
        assertEquals(ConversationPrompt.FUTURE_GOAL_IDS, FutureGoal.entries.map { it.raw })
    }

    @Test fun everyGoalHasItsPromptLine() {
        for (g in FutureGoal.entries) assertTrue(g.raw, g.promptText("English").contains("English"))
    }

    @Test fun everyPurposeOffersTwoOrThree() {
        for (p in LearningPurpose.entries) assertTrue(p.raw, FutureGoal.options(p).size in 2..3)
    }

    @Test fun unknownIdsAreSkippedInOrder() {
        assertEquals(listOf(FutureGoal.WORK_MEETINGS, FutureGoal.EXAM_CALM),
            FutureGoal.decode(listOf("work.meetings", "someday.newer", "exam.calm")))
    }

    @Test fun aPersonaWithoutGoalsStillLoads() {
        val old = """{"displayName":"Mina","city":"Seoul","updatedAt":"2026-10-01T00:00:00Z"}"""
        val p = StoreJson.json.decodeFromString(UserPersona.serializer(), old)
        assertEquals("Mina", p.displayName)
        assertEquals(emptyList<String>(), p.goals)
        val odd = """{"displayName":"Mina","goals":"work.meetings","updatedAt":"2026-10-01T00:00:00Z"}"""
        assertEquals(emptyList<String>(), StoreJson.json.decodeFromString(UserPersona.serializer(), odd).goals)
    }

    @Test fun goalsRoundTrip() {
        val p = UserPersona(displayName = "Mina", goals = listOf("travel.alone", "hobby.noSubs"))
        val back = StoreJson.json.decodeFromString(UserPersona.serializer(),
            StoreJson.json.encodeToString(UserPersona.serializer(), p))
        assertEquals(listOf(FutureGoal.TRAVEL_ALONE, FutureGoal.HOBBY_NO_SUBS), back.futureGoals)
    }
}
