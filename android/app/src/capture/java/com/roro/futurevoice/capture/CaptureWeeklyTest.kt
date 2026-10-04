package com.roro.futurevoice.capture

import android.content.Context
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.roro.futurevoice.R
import com.roro.futurevoice.capture.flags.PracticeCaptureFlags
import com.roro.futurevoice.capture.flags.WeeklyTestCaptureFlags
import com.roro.futurevoice.data.CefrLevel
import com.roro.futurevoice.data.DrillStore
import com.roro.futurevoice.data.LanguageScope
import com.roro.futurevoice.data.SessionStore
import com.roro.futurevoice.data.VocabStore
import com.roro.futurevoice.data.WeekRecapStore
import com.roro.futurevoice.data.WeeklyTest
import com.roro.futurevoice.data.WeeklyTestAnswer
import com.roro.futurevoice.data.WeeklyTestItem
import com.roro.futurevoice.data.WeeklyTestSettings
import com.roro.futurevoice.data.WeeklyTestStore
import com.roro.futurevoice.talk.DrillCard
import com.roro.futurevoice.talk.Session
import com.roro.futurevoice.talk.SessionSummary
import com.roro.futurevoice.talk.Turn
import com.roro.futurevoice.talk.TurnRole
import com.roro.futurevoice.talk.TurnSuggestion
import com.roro.futurevoice.ui.PracticeBody
import com.roro.futurevoice.ui.Shelf
import com.roro.futurevoice.ui.WeeklyTestScreen
import com.roro.futurevoice.ui.brand.AppSurfaces
import kotlinx.coroutines.runBlocking
import java.io.File
import java.util.UUID

/**
 * Capture modes for the weekly and monthly test (iOS `DebugCaptureHarness`,
 * the same names):
 *
 *   weekly-test, weekly-test-word, weekly-test-gap, weekly-test-build,
 *   weekly-test-listen, weekly-test-speak, weekly-test-word-right,
 *   weekly-test-gap-wrong, weekly-test-build-wrong, weekly-test-build-right,
 *   weekly-test-grammar[-right|-wrong], weekly-test-upgrade[-right|-wrong],
 *   weekly-test-result, practice-weekly, monthly-test, practice-monthly
 *
 * The material is one seeded week (iOS `seedWeeklyTestWeek`): notebook words,
 * a talk whose summary offered phrases the fluent self actually said,
 * corrections with the learner's own wording, and fluent lines with audio on
 * disk (the bundled ringtone stands in for a saved line). Glosses are stubbed
 * so a meaning item can be built offline.
 */
object CaptureWeeklyTest {

    private const val DAY = 86_400_000L
    private fun lang(c: Context) = LanguageScope.active(c)
    private fun level(c: Context) =
        CefrLevel.from(c.getSharedPreferences("futurevoice", 0).getString("futurevoice.proficiency", "b1"))
    private fun id(key: String) = UUID.nameUUIDFromBytes("capture:weekly:$key".toByteArray()).toString().uppercase()

    private val glosses = mapOf(
        "chore" to "A task you have to do regularly and find tedious.",
        "exhausting" to "Making you feel very tired.",
        "appreciate" to "To be grateful for something.",
        "negotiate" to "To discuss something to reach an agreement.",
        "overwhelmed" to "Feeling that there is too much to deal with.",
        "reschedule" to "To change the time of a planned event.",
        "hesitate" to "To pause before doing something because you are unsure.",
    )

    private suspend fun seedWeek(c: Context) {
        val language = lang(c)
        WeeklyTestStore.shared(c).removeAll(language)
        WeeklyTestSettings.clearThin(c)
        CaptureSeed.seedVocab(c)
        val ended = System.currentTimeMillis() - 2 * 3_600_000L
        val started = ended - 900_000L
        val lines = listOf(
            TurnRole.FLUENT_SELF to "So how did the move go? Did you end up hiring movers?",
            TurnRole.USER to "It was okay. I end up carrying most boxes myself.",
            TurnRole.FLUENT_SELF to "That sounds exhausting. Honestly, next time I'd push back on doing it alone.",
            TurnRole.USER to "Yeah, my back is still sore from it.",
            TurnRole.FLUENT_SELF to "Give yourself a day off. You can always catch up on the unpacking later.",
            TurnRole.USER to "I have to unpack the kitchen first, it's a chore.",
            TurnRole.FLUENT_SELF to "Kitchens are the worst part. Let me walk you through how I did mine.",
            // The week report's quotes (`CaptureWeekRecap.sample`), so the
            // grammar and upgrade items find the learner's own lines.
            TurnRole.USER to "Yesterday I went to the flat and the landlord says it's fine.",
            TurnRole.FLUENT_SELF to "That's a relief. Did you sign anything yet?",
            TurnRole.USER to "Not yet. I was very tired after the move.",
            TurnRole.FLUENT_SELF to "Fair enough. And the flat itself?",
            TurnRole.USER to "The flat is good for the price.",
        )
        val audioDir = File(c.filesDir, "turn-audio").apply { mkdirs() }
        val ringtone = c.resources.openRawResource(R.raw.ringtone).use { it.readBytes() }
        val turns = lines.mapIndexed { i, (role, text) ->
            val t = Turn(id = id("turn-$i"), role = role, transcript = text,
                durationMs = if (role == TurnRole.USER) 9_000 else 3_500, timestamp = started + i * 20_000L,
                suggestion = if (i == 1) TurnSuggestion("I ended up carrying most of the boxes myself.",
                    "Past tense, and \"most of the\" before a noun.") else null)
            if (role == TurnRole.FLUENT_SELF) File(audioDir, "${t.id}.wav").writeBytes(ringtone)
            t
        }
        val session = Session(id = id("session"), userId = "capture", targetLanguage = language,
            startedAt = started, endedAt = ended, turns = turns, summary = SessionSummary(
                overallNote = "Relaxed and clear.",
                expressionsOffered = listOf("end up", "push back on", "catch up on", "walk you through"),
                expressionsUsed = listOf("a chore")))
        SessionStore.shared(c).save(session)
        DrillStore.shared(c).upsertMany(listOf(
            DrillCard(id = id("card-1"), sourcePhrase = turns[1].transcript,
                targetPhrase = "I ended up carrying most of the boxes myself.",
                reason = "Past tense, and \"most of the\" before a noun.", createdAt = ended,
                nextReviewAt = ended + DAY, box = 0, sourceSessionId = session.id, sourceTurnId = turns[1].id),
            DrillCard(id = id("card-2"), sourcePhrase = turns[5].transcript,
                targetPhrase = "I have to unpack the kitchen first. It's such a chore.",
                reason = "Two sentences read better out loud.", createdAt = ended,
                nextReviewAt = ended + DAY, box = 0, sourceSessionId = session.id, sourceTurnId = turns[5].id),
        ), language)
        val vocab = VocabStore.shared(c)
        vocab.addStudying("chore", language)
        vocab.addStudying("exhausting", language)
        // The closed week's report, coach written, so the paper never waits on
        // the network for its grammar and upgrade items.
        WeekRecapStore.save(c, CaptureWeekRecap.sample(c))
    }

    private fun sampleItems(weeksBack: Int = 0): List<WeeklyTestItem> = listOf(
        WeeklyTestItem(kind = WeeklyTestItem.Kind.MEANING, prompt = "Making you feel very tired.",
            answer = "exhausting", options = listOf("thrilling", "exhausting", "soothing", "spare")),
        WeeklyTestItem(kind = WeeklyTestItem.Kind.GAP, prompt = "Honestly, next time I'd ______ doing it alone.",
            answer = "push back on", options = listOf("end up", "push back on", "catch up on", "walk you through")),
        WeeklyTestItem(kind = WeeklyTestItem.Kind.BUILD, prompt = "I end up carrying most boxes myself.",
            answer = "I ended up carrying most of the boxes myself.",
            options = listOf("most", "I", "myself.", "ended", "the", "up", "boxes", "carrying", "of", "end")),
        WeeklyTestItem(kind = WeeklyTestItem.Kind.MEANING,
            prompt = if (weeksBack == 1) "A task you have to do regularly and find tedious." else "In a careless or lazy way.",
            answer = if (weeksBack == 1) "chore" else "slackly",
            options = if (weeksBack == 1) listOf("chore", "errand", "hobby", "shift")
                else listOf("slackly", "briskly", "neatly", "gladly")),
        WeeklyTestItem(kind = WeeklyTestItem.Kind.SPEAK, prompt = "", answer = "Give yourself a day off."),
    )

    /** Two finished weekly tests with misses, inside the month the monthly
     *  paper collects from (iOS `seedMonthOfMisses`). */
    private suspend fun seedMonthOfMisses(c: Context) {
        val language = lang(c)
        val store = WeeklyTestStore.shared(c)
        store.removeAll(language)
        val opening = WeeklyTestSettings.schedule(c).monthOpening()
        for (weeksBack in listOf(1, 2)) {
            val at = opening - weeksBack * 7 * DAY + 3_600_000L
            val items = sampleItems(weeksBack)
            store.save(WeeklyTest(targetLanguage = language, periodStart = at - 7 * DAY, periodEnd = at,
                createdAt = at, startedAt = at, finishedAt = at + 600_000, appliedAt = at + 600_000, items = items,
                answers = items.mapIndexed { i, item ->
                    val ok = i == 1 && weeksBack == 2
                    WeeklyTestAnswer(item.id, if (ok) item.answer else "", ok, at + i * 30_000L)
                }))
        }
    }

    /** A finished test on file for this week (iOS `seedFinishedWeeklyTest`). */
    private suspend fun seedFinished(c: Context) {
        val language = lang(c)
        val store = WeeklyTestStore.shared(c)
        store.removeAll(language)
        val now = System.currentTimeMillis()
        val items = listOf(
            WeeklyTestItem(kind = WeeklyTestItem.Kind.MEANING, prompt = "A task you have to do regularly and find tedious.",
                answer = "chore", options = listOf("chore", "errand", "hobby", "shift")),
        ) + sampleItems().take(3) + listOf(
            WeeklyTestItem(kind = WeeklyTestItem.Kind.GAP, prompt = "You can always ______ the unpacking later.",
                answer = "catch up on", options = listOf("catch up on", "push back on", "end up", "walk you through")),
            WeeklyTestItem(kind = WeeklyTestItem.Kind.LISTEN, prompt = "", answer = "Give yourself a day off.",
                options = listOf("off.", "Give", "a", "yourself", "day")),
            WeeklyTestItem(kind = WeeklyTestItem.Kind.BUILD, prompt = "my back is still sore from it",
                answer = "my back is still sore from all that lifting",
                options = listOf("sore", "from", "my", "all", "back", "that", "is", "lifting", "still", "it")),
        )
        val wrong = setOf(1, 3)
        store.save(WeeklyTest(targetLanguage = language, periodStart = now - 7 * DAY, periodEnd = now,
            createdAt = now - 600_000, startedAt = now - 600_000, finishedAt = now, appliedAt = now,
            bestStreak = 3, items = items, answers = items.mapIndexed { i, item ->
                val ok = i !in wrong
                WeeklyTestAnswer(item.id, if (ok) item.answer else "", ok, now - 600_000 + i * 30_000L)
            }))
        // Last week's, so the result's comparison line has something to say.
        val last = now - 7 * DAY
        store.save(WeeklyTest(targetLanguage = language, periodStart = last - 7 * DAY, periodEnd = last,
            createdAt = last, finishedAt = last + 600_000, appliedAt = last + 600_000, items = items.take(6),
            answers = items.take(6).mapIndexed { i, item -> WeeklyTestAnswer(item.id, "", i % 2 == 0, last) }))
    }

    private fun mode(seed: suspend (Context) -> Unit, screen: @Composable (Context) -> Unit):
        @Composable (Context) -> Unit = { ctx ->
        remember {
            PracticeCaptureFlags.offlineLookups = true
            WeeklyTestCaptureFlags.glosses = glosses
            runBlocking { seed(ctx) }
            true
        }
        screen(ctx)
    }

    private fun test(kind: WeeklyTestItem.Kind?, answer: Boolean?) = mode({ c ->
        CaptureSeed.once("weekly-test") { seedWeek(c) }
        WeeklyTestCaptureFlags.kind = kind ?: WeeklyTestItem.Kind.MEANING
        WeeklyTestCaptureFlags.answer = answer
    }) { c -> WeeklyTestScreen(language = lang(c), level = level(c), onClose = {}) }

    @Composable
    private fun Practice(c: Context) {
        // The test's door is the Review page's HEADER now (the host's face at
        // the far right), so the shot is the whole tab shell.
        CapturePractice.Practice(c, Shelf.STUDYING)
    }

    val wired: Map<String, @Composable (Context) -> Unit> = mapOf(
        "weekly-test" to test(null, null),
        "weekly-test-word" to test(WeeklyTestItem.Kind.MEANING, null),
        "weekly-test-gap" to test(WeeklyTestItem.Kind.GAP, null),
        "weekly-test-build" to test(WeeklyTestItem.Kind.BUILD, null),
        "weekly-test-listen" to test(WeeklyTestItem.Kind.LISTEN, null),
        "weekly-test-speak" to test(WeeklyTestItem.Kind.SPEAK, null),
        "weekly-test-word-right" to test(WeeklyTestItem.Kind.MEANING, true),
        "weekly-test-gap-wrong" to test(WeeklyTestItem.Kind.GAP, false),
        "weekly-test-build-wrong" to test(WeeklyTestItem.Kind.BUILD, false),
        "weekly-test-build-right" to test(WeeklyTestItem.Kind.BUILD, true),
        "weekly-test-grammar" to test(WeeklyTestItem.Kind.GRAMMAR, null),
        "weekly-test-grammar-right" to test(WeeklyTestItem.Kind.GRAMMAR, true),
        "weekly-test-grammar-wrong" to test(WeeklyTestItem.Kind.GRAMMAR, false),
        "weekly-test-upgrade" to test(WeeklyTestItem.Kind.UPGRADE, null),
        "weekly-test-upgrade-right" to test(WeeklyTestItem.Kind.UPGRADE, true),
        "weekly-test-upgrade-wrong" to test(WeeklyTestItem.Kind.UPGRADE, false),
        "weekly-test-result" to mode({ c -> CaptureSeed.once("weekly-test-result") { seedFinished(c) } }) { c ->
            WeeklyTestScreen(language = lang(c), level = level(c), onClose = {})
        },
        "practice-weekly" to mode({ c ->
            CaptureSeed.once("practice-weekly") {
                CaptureSeed.seedVocab(c); CaptureSeed.seedSessions(c); CaptureSeed.seedScenarios(c); seedFinished(c)
            }
        }) { Practice(it) },
        "monthly-test" to mode({ c ->
            CaptureSeed.once("monthly-test") { seedWeek(c); seedMonthOfMisses(c) }
        }) { c -> WeeklyTestScreen(language = lang(c), level = level(c), monthly = true, onClose = {}) },
        "practice-monthly" to mode({ c ->
            CaptureSeed.once("practice-monthly") {
                CaptureSeed.seedVocab(c); CaptureSeed.seedSessions(c); CaptureSeed.seedScenarios(c)
                seedMonthOfMisses(c)
            }
        }) { Practice(it) },
    )

    val notPorted: Map<String, String> = emptyMap()
}
