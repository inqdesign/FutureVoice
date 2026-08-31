package com.roro.futurevoice

import com.roro.futurevoice.talk.CarryoverDetector
import com.roro.futurevoice.data.DrillIngest
import com.roro.futurevoice.talk.DrillCard
import com.roro.futurevoice.talk.LearnerPattern
import com.roro.futurevoice.talk.LearnerProfile
import com.roro.futurevoice.talk.PhraseFeedback
import com.roro.futurevoice.talk.ScorecardMetrics
import com.roro.futurevoice.talk.SessionSummary
import com.roro.futurevoice.talk.Turn
import com.roro.futurevoice.talk.TurnRole
import com.roro.futurevoice.talk.TurnSuggestion
import com.roro.futurevoice.audio.FluencyStats
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.double
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant

/**
 * Golden vectors produced by the REAL Swift implementations
 * (`scripts/android/gen-vectors.sh` → `docs/contracts/vectors/
 * summary-ingestion.json`). A number that differs across platforms is a bug
 * on whichever side is newer (`android-launch-roadmap.md` §0.3). Lemma-
 * dependent paths are not vector'd — platform lemmatizers differ.
 */
class SummaryIngestionVectorTest {

    private val v: JsonObject = Json.parseToJsonElement(
        javaClass.getResourceAsStream("/vectors/summary-ingestion.json")!!
            .bufferedReader().readText()
    ).jsonObject

    private fun iso(s: String): Long = Instant.parse(s).toEpochMilli()
    private fun uuid(n: Int): String = String.format("00000000-0000-4000-8000-%012d", n)
    private val NOW = iso("2026-08-31T12:00:00Z")

    private fun str(o: JsonObject, k: String) = o[k]!!.jsonPrimitive.content
    private fun optStr(o: JsonObject, k: String): String? =
        o[k]?.takeIf { it != JsonNull }?.jsonPrimitive?.content

    @Test fun relevantFragment() {
        for (case in v["relevant_fragment"]!!.jsonArray.map { it.jsonObject }) {
            assertEquals(str(case, "result"),
                DrillIngest.relevantFragment(str(case, "source"), str(case, "target")))
        }
    }

    @Test fun coreSentence() {
        for (case in v["core_sentence"]!!.jsonArray.map { it.jsonObject }) {
            assertEquals(str(case, "result"),
                DrillIngest.coreSentence(str(case, "target"), str(case, "source")))
        }
    }

    @Test fun isDrillable() {
        for (case in v["is_drillable"]!!.jsonArray.map { it.jsonObject }) {
            assertEquals(str(case, "phrase"), case["result"]!!.jsonPrimitive.boolean,
                DrillIngest.isDrillable(str(case, "phrase")))
        }
    }

    @Test fun normalizedAndCreditable() {
        for (case in v["carryover_normalized"]!!.jsonArray.map { it.jsonObject }) {
            assertEquals(str(case, "result"), CarryoverDetector.normalized(str(case, "text")))
        }
        for (case in v["is_creditable"]!!.jsonArray.map { it.jsonObject }) {
            assertEquals(str(case, "phrase"), case["result"]!!.jsonPrimitive.boolean,
                CarryoverDetector.isCreditable(str(case, "phrase")))
        }
    }

    private fun detectFixture(): Pair<List<Turn>, List<DrillCard>> {
        val d = v["carryover_detect"]!!.jsonObject
        val turns = d["turns"]!!.jsonArray.map { it.jsonObject }.map { t ->
            Turn(
                id = uuid(t["idx"]!!.jsonPrimitive.int),
                role = if (str(t, "role") == "user") TurnRole.USER else TurnRole.FLUENT_SELF,
                transcript = str(t, "text"),
                suggestion = optStr(t, "suggestion")?.let { TurnSuggestion(it, "more natural") },
            )
        }
        val cards = d["cards"]!!.jsonArray.map { it.jsonObject }.map { c ->
            DrillCard(
                id = uuid(c["id"]!!.jsonPrimitive.int),
                sourcePhrase = "", targetPhrase = str(c, "target"), reason = "",
                createdAt = iso(str(c, "createdAt")), nextReviewAt = NOW, box = 0,
                sourceSessionId = uuid(c["sourceSessionIdx"]!!.jsonPrimitive.int),
            )
        }
        return turns to cards
    }

    @Test fun carryoverDetect() {
        val d = v["carryover_detect"]!!.jsonObject
        val (turns, cards) = detectFixture()
        val result = CarryoverDetector.detect(
            turns = turns, cards = cards,
            curriculumItems = d["curriculum"]!!.jsonArray.map {
                CarryoverDetector.CurriculumItem(uuid(201), it.jsonPrimitive.content, isWord = false)
            },
            studyingExpressions = d["studyingExpressions"]!!.jsonArray.map { it.jsonPrimitive.content },
            sessionId = uuid(901), sessionStartedAt = iso(str(d, "sessionStartedAt")), now = NOW,
        )
        val expected = d["result"]!!.jsonArray.map { it.jsonObject }
        assertEquals(expected.size, result.size)
        for ((exp, got) in expected.zip(result)) {
            assertEquals(str(exp, "source"), got.source.name.let {
                when (it) { "DRILL_CARD" -> "drillCard"; "CURRICULUM_ITEM" -> "curriculumItem"
                    "STUDYING_EXPRESSION" -> "studyingExpression"; "SUGGESTION" -> "suggestion"
                    else -> "studyingWord" } })
            assertEquals(str(exp, "item"), got.item)
            assertEquals(str(exp, "quote"), got.quote)
            assertEquals(uuid(exp["turnIdx"]!!.jsonPrimitive.int), got.turnId)
        }
    }

    @Test fun contentWordGuard() {
        val g = v["carryover_content_word_guard"]!!.jsonObject
        val turn = Turn(id = uuid(3), role = TurnRole.USER, transcript = str(g, "turn"))
        assertEquals(g["matched"]!!.jsonPrimitive.boolean,
            CarryoverDetector.firstMatch(str(g, "item"), listOf(turn)) != null)
    }

    @Test fun drillIngest() {
        val d = v["drill_ingest"]!!.jsonObject
        val turns = d["turns"]!!.jsonArray.map { it.jsonObject }.map { t ->
            Turn(id = uuid(t["idx"]!!.jsonPrimitive.int), role = TurnRole.USER,
                transcript = str(t, "text"),
                suggestion = optStr(t, "suggestion")?.let { TurnSuggestion(it, optStr(t, "reason") ?: "") })
        }
        val sm = d["summary"]!!.jsonObject
        val summary = SessionSummary(
            phrasesUsed = sm["phrases"]!!.jsonArray.map { it.jsonObject }.map {
                PhraseFeedback(userSaid = str(it, "userSaid"), fluentAlternative = str(it, "alt"),
                    reason = str(it, "reason")) },
            newPatternsDetected = sm["patterns"]!!.jsonArray.map { it.jsonObject }.map {
                LearnerPattern(mistake = str(it, "mistake"), correction = str(it, "correction"),
                    context = str(it, "context")) },
            suggestedDrills = sm["drills"]!!.jsonArray.map { it.jsonPrimitive.content },
        )
        val minted = DrillIngest.mint(emptyList(), summary, turns, uuid(901), NOW)
        assertEquals(d["mintedCount"]!!.jsonPrimitive.int, minted.size)
        val expected = d["cards"]!!.jsonArray.map { it.jsonObject }
        val got = minted.sortedBy { it.targetPhrase }
        for ((exp, card) in expected.zip(got)) {
            assertEquals(str(exp, "source"), card.sourcePhrase)
            assertEquals(str(exp, "target"), card.targetPhrase)
            assertEquals(str(exp, "reason"), card.reason)
            assertEquals(exp["box"]!!.jsonPrimitive.int, card.box)
            val expTurn = exp["turnIdx"]?.takeIf { it != JsonNull }?.jsonPrimitive?.int
            assertEquals(expTurn?.let { uuid(it) }, card.sourceTurnId)
        }
    }

    @Test fun scorecardMetrics() {
        val d = v["scorecard_metrics"]!!.jsonObject
        val turns = d["turns"]!!.jsonArray.map { it.jsonObject }.map { t ->
            Turn(id = uuid(0), role = if (str(t, "role") == "user") TurnRole.USER else TurnRole.FLUENT_SELF,
                transcript = str(t, "text"),
                durationMs = t["durationMs"]!!.jsonPrimitive.int,
                excludedFromScoring = t["excluded"]!!.jsonPrimitive.boolean,
                suggestion = if (t["hasSuggestion"]!!.jsonPrimitive.boolean) TurnSuggestion("x", "y") else null,
                fluency = t["fluency"]?.takeIf { it != JsonNull }?.jsonObject?.let { f ->
                    FluencyStats(f["speakingSeconds"]!!.jsonPrimitive.double,
                        f["totalSeconds"]!!.jsonPrimitive.double,
                        f["pauseCount"]!!.jsonPrimitive.int,
                        f["pauseSeconds"]!!.jsonPrimitive.double, 0.0)
                })
        }
        val expected = Json.parseToJsonElement(str(d, "promptJSON")).jsonObject
        val got = ScorecardMetrics.compute(turns).promptJson()
        for ((k, value) in expected) {
            if (k == "distinct_words_by_cefr_level") continue   // lemma-dependent, not vector'd
            assertEquals(k, value, got[k])
        }
    }

    @Test fun profileAbsorb() {
        val d = v["profile_absorb"]!!.jsonObject
        val before = d["before"]!!.jsonObject
        val profile = LearnerProfile(
            userId = uuid(401), targetLanguage = "en", proficiencyLevel = "b1",
            recurringMistakes = before["recurring"]!!.jsonArray.map { it.jsonObject }.map {
                LearnerPattern(mistake = str(it, "mistake"), correction = str(it, "correction"),
                    context = str(it, "context"), frequency = it["frequency"]!!.jsonPrimitive.int,
                    lastSeenAt = iso(str(it, "lastSeenAt"))) },
            weakVocabAreas = before["weak"]!!.jsonArray.map { it.jsonPrimitive.content },
            totalSessions = before["totalSessions"]!!.jsonPrimitive.int,
            totalSpeakingSeconds = before["totalSpeakingSeconds"]!!.jsonPrimitive.int,
        )
        val inc = d["incoming"]!!.jsonObject
        val summary = SessionSummary(
            newPatternsDetected = inc["patterns"]!!.jsonArray.map { it.jsonObject }.map {
                LearnerPattern(mistake = str(it, "mistake"), correction = str(it, "correction"),
                    context = str(it, "context"), frequency = it["frequency"]!!.jsonPrimitive.int,
                    lastSeenAt = NOW) },
            weakVocabAreas = inc["weak"]!!.jsonArray.map { it.jsonPrimitive.content },
        )
        profile.absorb(summary, inc["speakingSeconds"]!!.jsonPrimitive.double, NOW)
        val after = d["after"]!!.jsonObject
        assertEquals(after["totalSessions"]!!.jsonPrimitive.int, profile.totalSessions)
        assertEquals(after["totalSpeakingSeconds"]!!.jsonPrimitive.int, profile.totalSpeakingSeconds)
        assertEquals(iso(str(after, "lastSessionAt")), profile.lastSessionAt)
        assertEquals(after["weak"]!!.jsonArray.map { it.jsonPrimitive.content }, profile.weakVocabAreas)
        val expPatterns = after["recurring"]!!.jsonArray.map { it.jsonObject }
        assertEquals(expPatterns.size, profile.recurringMistakes.size)
        for ((exp, got) in expPatterns.zip(profile.recurringMistakes)) {
            assertEquals(str(exp, "mistake"), got.mistake)
            assertEquals(str(exp, "correction"), got.correction)
            assertEquals(str(exp, "context"), got.context)
            assertEquals(exp["frequency"]!!.jsonPrimitive.int, got.frequency)
            assertEquals(iso(str(exp, "lastSeenAt")), got.lastSeenAt)
        }
        assertTrue(profile.recurringMistakes.size <= LearnerProfile.MAX_RECURRING)
    }
}
