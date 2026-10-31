package com.roro.futurevoice

import com.roro.futurevoice.data.StudyPlan
import com.roro.futurevoice.talk.SuggestedTopic
import com.roro.futurevoice.talk.TutorAction
import com.roro.futurevoice.talk.TutorAgentPrompts
import com.roro.futurevoice.talk.TutorBot
import com.roro.futurevoice.talk.TutorPick
import com.roro.futurevoice.talk.TutorToday
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** iOS `TutorAgentPromptDumpTests` (57ba9c6f): the buttons decode leniently,
 *  and today is ranked now → goal → routine → picks. */
class TutorAgentTest {

    /** A reply with a bad button still yields the good one, and an unknown
     *  type never becomes a dead button. */
    @Test fun actionsDecodeLeniently() {
        val json = """[{"type":"lesson","topic":"Why Lufthansa"},{"type":"teleport"},{"type":"review","label":"  "}]"""
        val decoded = (Json.parseToJsonElement(json) as JsonArray).mapNotNull { TutorAction.decode(it) }
        assertEquals(listOf(TutorAction.Kind.LESSON, TutorAction.Kind.REVIEW), decoded.map { it.type })
        assertNull(decoded[1].label)
    }

    @Test fun todayRanksNowThenGoalThenRoutine() {
        val day = StudyPlan.startOfDay(System.currentTimeMillis())
        val now = day + 10 * 3_600_000L
        fun item(id: String, kind: StudyPlan.Kind, h: Double, mins: Double = 10.0, progress: Double = 0.0): TutorBot.Item {
            val start = day + (h * 3_600_000).toLong()
            return TutorBot.Item(id, kind, id, start, anytime = false, progress = progress,
                end = start + (mins * 60_000).toLong())
        }
        val today = TutorBot.Today(day = day, items = listOf(
            item("talk8", StudyPlan.Kind.TALK, 8.0, progress = 1.0), item("review21", StudyPlan.Kind.REVIEW, 21.0)))
        val story = TutorPick.Action.ReadNews(SuggestedTopic(title = "t", blurb = "b"))
        val goal = TutorPick("goal-read-x", TutorPick.Kind.GOAL_READING, "Reading", "", story)
        val ep = TutorPick("ep-1", TutorPick.Kind.NEW_EPISODE, "Episode", "", story)
        assertEquals(listOf("p-goal-read-x", "r-review21", "p-ep-1", "r-talk8"),
            TutorToday.ranked(today, listOf(ep, goal), now).map { it.id })

        // Two routine blocks left: both come before a pick.
        val two = today.copy(items = listOf(item("talk8", StudyPlan.Kind.TALK, 8.0, progress = 0.5), today.items[1]))
        assertEquals(listOf("r-review21", "r-talk8", "p-ep-1"),
            TutorToday.ranked(two, listOf(ep), now).map { it.id }.take(3))

        // A block whose time is on comes before everything.
        val on = today.copy(items = today.items + item("shadow10", StudyPlan.Kind.SHADOW, 9.9, mins = 20.0))
        assertEquals("r-shadow10", TutorToday.ranked(on, listOf(ep, goal), now).first().id)
    }

    /** The lifted rules carry the protocol and the Korean line only for ko. */
    @Test fun rulesCarryTheProtocol() {
        val ko = TutorAgentPrompts.rules("Korean", "English", TutorAgentPrompts.korean("ko"))
        assertTrue(ko.contains("HOW THIS CHAT WORKS"))
        assertTrue(ko.contains("THE APP (what each part is for"))
        assertTrue(ko.contains("해요체"))
        assertTrue(!TutorAgentPrompts.rules("English", "German", TutorAgentPrompts.korean("en")).contains("해요체"))
    }
}
