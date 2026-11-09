package com.roro.futurevoice

import com.roro.futurevoice.data.CefrLevel
import com.roro.futurevoice.data.LearnerState
import com.roro.futurevoice.data.LearnerStateStore
import com.roro.futurevoice.data.LevelMap
import com.roro.futurevoice.data.StoreJson
import com.roro.futurevoice.talk.LevelTagger
import com.roro.futurevoice.talk.Turn
import com.roro.futurevoice.talk.TurnRole
import com.roro.futurevoice.talk.TutorTurnRole
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.BeforeClass
import org.junit.Test
import java.io.File
import java.nio.file.Files

/**
 * The learner state (docs/personal-report-plan.md, step 3; iOS
 * `LearnerStateTests`, 465331f6): the status rule, the quote check every
 * tagged verdict passes, and idempotency per talk.
 */
class LearnerStateTest {

    companion object {
        @BeforeClass @JvmStatic fun maps() {
            LevelMap.opener = { name ->
                File("src/main/assets/level_map/$name").takeIf { it.exists() }?.inputStream()
            }
        }
    }

    private lateinit var dir: File
    private lateinit var store: LearnerStateStore

    @Before fun setUp() {
        dir = Files.createTempDirectory("learner-state-").toFile()
        val root = dir
        store = LearnerStateStore(directory = { code -> File(root, code).apply { mkdirs() } })
    }

    @After fun tearDown() {
        dir.deleteRecursively()
    }

    private val map: LevelMap
        get() = LevelMap.load("en") ?: error("level_map_en.json is not in the app's assets")

    // MARK: - Map

    @Test fun englishMapLoadsAndOtherLanguagesStandDown() {
        assertEquals(43, map.grammar.size)
        assertEquals(16, map.functions.size)
        assertNotNull(LevelMap.load("en-GB"))
        assertNull(LevelMap.load("ko"))
        assertNull(LevelMap.load("de"))
    }

    // MARK: - Status rule

    @Test fun statusRule() {
        assertEquals(LearnerState.Status.UNSEEN, LearnerState.status(right = 0, wrong = 0, rightTalks = 0))
        assertEquals(LearnerState.Status.TRIED, LearnerState.status(right = 1, wrong = 0, rightTalks = 1))
        // Plenty of right uses, but all in one talk: one lucky talk isn't command.
        assertEquals(LearnerState.Status.TRIED, LearnerState.status(right = 5, wrong = 0, rightTalks = 1))
        assertEquals(LearnerState.Status.SOLID, LearnerState.status(right = 3, wrong = 0, rightTalks = 2))
        assertEquals(LearnerState.Status.SHAKY, LearnerState.status(right = 0, wrong = 1, rightTalks = 0))
        // 75% right is under the bar; 80% is on it.
        assertEquals(LearnerState.Status.SHAKY, LearnerState.status(right = 3, wrong = 1, rightTalks = 2))
        assertEquals(LearnerState.Status.SOLID, LearnerState.status(right = 4, wrong = 1, rightTalks = 2))
    }

    // MARK: - Quote check

    @Test fun normalizationDropsFillersStuttersAndPunctuation() {
        assertEquals("i am working on a new app", LevelTagger.normalized("I am uh I am working on uh a new app."))
        assertEquals("i went to busan", LevelTagger.normalized("I I I went, um, to Busan!"))
        assertEquals("i'm fine", LevelTagger.normalized("I’m fine"))
    }

    @Test fun quoteMustBeTheLearners() {
        val lines = listOf("I am uh I am working on uh a new app.", "Yesterday I go to the office")
        assertTrue(LevelTagger.isTheirs("I am working on a new app", lines))
        assertTrue(LevelTagger.isTheirs("yesterday I go to the office", lines))
        assertFalse(LevelTagger.isTheirs("I have been working on a new app", lines))
        assertFalse(LevelTagger.isTheirs("", lines))
        assertFalse(LevelTagger.isTheirs("uh um", lines))
    }

    @Test fun verifyDropsUnverifiedAndUnknownItems() {
        val evidence = listOf("Yesterday I go to Busan with my friends.", "I'm going to start a new project.")
        val payload = LevelTagger.Payload(grammar = listOf(
            LevelTagger.GrammarHit("past_simple", right = 0, wrong = 1, wrongQuote = "Yesterday I go to Busan"),
            // The AI's sentence, not theirs.
            LevelTagger.GrammarHit("present_perfect_experience", right = 1, wrong = 0,
                rightQuote = "Have you ever been to Busan"),
            LevelTagger.GrammarHit("going_to", right = 1, wrong = 0, rightQuote = "I'm going to start a new project"),
            LevelTagger.GrammarHit("not_on_the_map", right = 2, wrong = 0, rightQuote = "Yesterday I go to Busan"),
            // A right count whose wrong quote is missing: both must be theirs.
            LevelTagger.GrammarHit("will", right = 1, wrong = 1, rightQuote = "I'm going to start", wrongQuote = ""),
        ), functions = listOf(
            LevelTagger.FunctionHit("past_event", quote = "I go to Busan with my friends"),
            LevelTagger.FunctionHit("plans", quote = "I will start a company"),
        ))
        val (items, dropped) = LevelTagger.verify(payload, map, evidence)
        assertEquals(setOf("past_simple", "going_to", "past_event"), items.map { it.id }.toSet())
        assertEquals(3, dropped)
        assertEquals(false, items.first { it.id == "past_simple" }.quotes.first().right)
    }

    @Test fun transcriptKeepsOnlyEvidenceLines() {
        val now = System.currentTimeMillis()
        val drill = Turn(role = TurnRole.USER, transcript = "I am a nurse.", timestamp = now,
            tutorRole = TutorTurnRole.DRILL)
        val misheard = Turn(role = TurnRole.USER, transcript = "banana phone", timestamp = now,
            excludedFromScoring = true)
        val turns = listOf(
            Turn(role = TurnRole.FLUENT_SELF, transcript = "What do you do?", timestamp = now),
            Turn(role = TurnRole.USER, transcript = "I work in hospital.", timestamp = now),
            drill, misheard,
        )
        assertEquals("AI: What do you do?\nUSER: I work in hospital.", LevelTagger.transcript(turns))
        assertEquals(listOf("I work in hospital."), LevelTagger.evidenceLines(turns))
    }

    // MARK: - Idempotency

    private fun tag(items: List<LearnerState.ItemTag>, fingerprint: String = "f1",
                    date: Long = System.currentTimeMillis()) =
        LearnerState.SessionTag(talkDate = date, taggedAt = System.currentTimeMillis(),
            fingerprint = fingerprint, mapVersion = map.version, items = items)

    private fun item(id: String, kind: LearnerState.Kind = LearnerState.Kind.GRAMMAR, right: Int,
                     wrong: Int, quotes: List<LearnerState.Quote> = emptyList()) =
        LearnerState.ItemTag(id = id, kind = kind, right = right, wrong = wrong, quotes = quotes)

    @Test fun taggingTheSameTalkTwiceDoesNotDoubleCount() {
        val id = StoreJson.newId()
        val t = tag(listOf(item("past_simple", right = 2, wrong = 1,
            quotes = listOf(LearnerState.Quote(text = "I go yesterday", right = false)))))
        store.record(t, sessionId = id, language = "en")
        store.record(t, sessionId = id, language = "en")
        val past = store.items("en").first { it.id == "past_simple" }
        assertEquals(2, past.right)
        assertEquals(1, past.wrong)
        assertEquals(1, past.talks)
        assertFalse(store.needsTagging(sessionId = id, fingerprint = "f1", mapVersion = map.version, language = "en"))
        // The talk grew: tagged again, and the new verdicts REPLACE the old.
        assertTrue(store.needsTagging(sessionId = id, fingerprint = "f2", mapVersion = map.version, language = "en"))
        store.record(tag(listOf(item("past_simple", right = 4, wrong = 0)), fingerprint = "f2"),
            sessionId = id, language = "en")
        assertEquals(4, store.items("en").first { it.id == "past_simple" }.right)
    }

    @Test fun statePersistsAndAggregatesAcrossTalks() {
        val old = System.currentTimeMillis() - 86_400_000L * 3
        store.record(tag(listOf(item("past_simple", right = 1, wrong = 1,
            quotes = listOf(LearnerState.Quote(text = "I go yesterday", right = false),
                LearnerState.Quote(text = "I went home", right = true)))), date = old),
            sessionId = StoreJson.newId(), language = "en")
        store.record(tag(listOf(item("past_simple", right = 3, wrong = 0,
            quotes = listOf(LearnerState.Quote(text = "we ate seafood", right = true))))),
            sessionId = StoreJson.newId(), language = "en")
        // A fresh store reads the same file.
        val root = dir
        val reread = LearnerStateStore(directory = { File(root, it) })
        val past = reread.items("en").first { it.id == "past_simple" }
        assertEquals(4, past.right)
        assertEquals(1, past.wrong)
        assertEquals(2, past.talks)
        assertEquals(LearnerState.Status.SOLID, past.status)
        assertEquals(listOf("we ate seafood", "I go yesterday", "I went home"), past.quotes.map { it.text })
        // The file stores dates as ISO 8601, to the second.
        assertEquals(old.toDouble(), (past.firstSeen ?: 0L).toDouble(), 1000.0)
    }

    @Test fun failuresStopAfterTheLimitAndDeletedTalksAreForgotten() {
        val id = StoreJson.newId()
        repeat(LearnerState.MAX_FAILURES) { store.recordFailure(sessionId = id, language = "en") }
        assertFalse(store.needsTagging(sessionId = id, fingerprint = "f", mapVersion = map.version, language = "en"))
        val kept = StoreJson.newId()
        store.record(tag(listOf(item("be", right = 1, wrong = 0))), sessionId = kept, language = "en")
        store.record(tag(listOf(item("can", right = 1, wrong = 0))), sessionId = StoreJson.newId(), language = "en")
        store.forgetSessions(notIn = setOf(kept), language = "en")
        assertEquals(listOf(kept), store.state("en").sessions.keys.sorted())
    }

    // MARK: - Prompt block

    @Test fun promptLinesOrderPrerequisitesFirstThenShakyBeforeUnseen() {
        assertEquals("nothing tagged yet", "", store.promptLines("en", CefrLevel.A2))
        assertEquals("no map", "", store.promptLines("ko", CefrLevel.A2))

        val id = StoreJson.newId()
        store.record(tag(listOf(
            item("be", right = 3, wrong = 0),
            item("past_simple", right = 1, wrong = 2,
                quotes = listOf(LearnerState.Quote(text = "I go yesterday", right = false))),
            item("going_to", right = 1, wrong = 0,
                quotes = listOf(LearnerState.Quote(text = "I'm going to start", right = true))),
            item("introduce", kind = LearnerState.Kind.FUNCTION, right = 1, wrong = 0),
        )), sessionId = id, language = "en")
        store.record(tag(listOf(item("be", right = 2, wrong = 0)), fingerprint = "g"),
            sessionId = StoreJson.newId(), language = "en")

        val text = store.promptLines("en", CefrLevel.A2)
        val lines = text.split("\n")
        assertTrue(lines.size <= LearnerStateStore.MAX_PROMPT_LINES)
        assertTrue(lines[0].contains("level A2, next B1"))
        assertTrue(lines[1].startsWith("Solid: be: am / is / are"))
        val order = lines.filter { it.startsWith("- ") }
        fun at(id: String) = order.indexOfFirst { it.contains("($id,") }
        // Shaky first, with the learner's error.
        assertTrue(order[0].contains("past_simple") && order[0].contains("\"I go yesterday\""))
        assertTrue("tried before unseen", at("going_to") < at("present_perfect_experience"))
        // present perfect needs past simple, which is a gap: never before it.
        assertTrue(at("past_simple") < at("present_perfect_experience"))
        assertTrue(at("present_perfect_experience") < at("present_perfect_since_for"))
        // An unseen A1 item, below the current level, is not named.
        assertEquals(-1, at("there_is"))
        assertTrue(text.contains("Can do: introduce yourself"))
    }

    @Test fun failuresFromBeforeTheFixAreForgivenOnce() {
        val old = LearnerState(failures = mapOf("talk" to 2))
        val cleared = old.clearingOldFailures()
        assertTrue(cleared.failures.isEmpty())
        assertEquals(LearnerState.FAILURES_EPOCH, cleared.failuresEpoch)
        val again = cleared.copy(failures = mapOf("talk" to 1)).clearingOldFailures()
        assertEquals(1, again.failures["talk"])
    }

    @Test fun everyTaggingRequestHasItsOwnKey() {
        val first = LevelTagger.requestKey("id", "f")
        assertTrue(first != LevelTagger.requestKey("id", "f"))
        assertTrue(first.startsWith("level-tag:id:f:"))
    }

    private fun event(key: String, source: String? = "talk", right: Int = 1) =
        com.roro.futurevoice.data.LearnerEvent(key, "en", 0L, source, "item", key,
            mapOf("right" to kotlinx.serialization.json.JsonPrimitive(right)))

    @Test fun onlyChangedFactsAreSentAgain() {
        val same = event("a")
        val sent = mapOf(
            "a" to com.roro.futurevoice.data.LearnerEventDiff.Sent(same.fingerprint, "talk"),
            "b" to com.roro.futurevoice.data.LearnerEventDiff.Sent(event("b").fingerprint, "talk"),
        )
        val plan = com.roro.futurevoice.data.LearnerEventDiff.plan(listOf(same, event("b", right = 2), event("new")), sent)
        assertTrue(plan.forget.isEmpty())
        assertEquals(listOf("b", "new"), plan.put.map { it.key })
    }

    @Test fun aVanishedFactClearsItsSourceAndResendsTheRest() {
        val kept = event("kept")
        val other = event("other", source = "talk2")
        val sent = mapOf(
            "kept" to com.roro.futurevoice.data.LearnerEventDiff.Sent(kept.fingerprint, "talk"),
            "gone" to com.roro.futurevoice.data.LearnerEventDiff.Sent("x", "talk"),
            "other" to com.roro.futurevoice.data.LearnerEventDiff.Sent(other.fingerprint, "talk2"),
        )
        val plan = com.roro.futurevoice.data.LearnerEventDiff.plan(listOf(kept, other), sent)
        assertEquals(listOf("talk"), plan.forget)
        assertEquals(listOf("kept"), plan.put.map { it.key })
        assertEquals(setOf("other"), com.roro.futurevoice.data.LearnerEventDiff.afterForgetting(plan.forget, sent).keys)
    }

    @Test fun noWeakPointsLeaveThePromptsAsTheyWere() {
        assertEquals("", com.roro.futurevoice.talk.LearnerWeakPoints.plannerBlock(emptyList()))
        assertEquals("", com.roro.futurevoice.talk.LearnerWeakPoints.goalPrepBlock(emptyList()))
    }

    @Test fun theCheckerOnlyAppliesARealCorrection() {
        val lines = listOf("I want a opportunity.", "Fine.")
        val check = com.roro.futurevoice.talk.MaterialCheck
        assertEquals(listOf("I want an opportunity.", "Fine."), check.apply(listOf(1 to "I want an opportunity."), lines))
        assertEquals(lines, check.apply(listOf(9 to "x", 2 to "  ", 2 to "much longer ".repeat(20)), lines))
    }

    @Test fun aGoalQuestionsTopicIdIsTheSameStringAsIos() {
        val goal = com.roro.futurevoice.data.UpcomingGoal(id = "aaaaaaaa-0000-0000-0000-000000000001",
            kind = com.roro.futurevoice.data.UpcomingGoal.Kind.INTERVIEW, title = "t", language = "en")
        assertEquals("goal:AAAAAAAA-0000-0000-0000-000000000001:b466f394",
            com.roro.futurevoice.talk.GoalPrep.topicId(goal, "Tell me about yourself"))
    }

    @Test fun aQuestionIsReadyOnlyWhenItsLessonPassed() {
        val goal = com.roro.futurevoice.data.UpcomingGoal(kind = com.roro.futurevoice.data.UpcomingGoal.Kind.INTERVIEW, title = "t", language = "en")
        val prep = com.roro.futurevoice.talk.GoalPrep
        val id = prep.topicId(goal, "q")
        fun lesson(passed: Boolean) = com.roro.futurevoice.talk.TutorLesson(title = "t", titleTarget = "t", language = "en",
            challenges = emptyList(), createdAt = 0L, topicId = id,
            check = if (passed) com.roro.futurevoice.talk.TutorLesson.FinalCheck(startedAt = 0L, passedAt = 1L) else null)
        assertEquals(com.roro.futurevoice.talk.GoalPrep.QuestionState.UNTOUCHED, prep.state("q", goal, emptyList()))
        assertEquals(com.roro.futurevoice.talk.GoalPrep.QuestionState.PRACTICING, prep.state("q", goal, listOf(lesson(false))))
        assertEquals(com.roro.futurevoice.talk.GoalPrep.QuestionState.READY, prep.state("q", goal, listOf(lesson(false), lesson(true))))
    }
}
