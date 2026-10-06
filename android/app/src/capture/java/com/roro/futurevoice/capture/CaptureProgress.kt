package com.roro.futurevoice.capture

import android.content.Context
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.roro.futurevoice.data.LanguageCatalog
import com.roro.futurevoice.data.LanguageScope
import com.roro.futurevoice.data.SessionStore
import com.roro.futurevoice.data.StoreEvents
import com.roro.futurevoice.data.TalkTimeLog
import com.roro.futurevoice.data.StoreJson
import com.roro.futurevoice.talk.AxisScore
import com.roro.futurevoice.talk.Session
import com.roro.futurevoice.talk.SessionMode
import com.roro.futurevoice.talk.SessionOrigin
import com.roro.futurevoice.talk.SessionScorecard
import com.roro.futurevoice.talk.SessionSummary
import com.roro.futurevoice.talk.Turn
import com.roro.futurevoice.talk.TurnRole
import com.roro.futurevoice.data.WeeklyReport
import com.roro.futurevoice.data.WeeklyReportStore
import com.roro.futurevoice.ui.ActivityScreen
import com.roro.futurevoice.ui.DayCardSheet
import com.roro.futurevoice.ui.Dim
import com.roro.futurevoice.ui.ProgressBody
import com.roro.futurevoice.ui.brand.AppSurfaces
import com.roro.futurevoice.ui.brand.DayCardData
import java.time.ZonedDateTime
import java.util.UUID

/**
 * Capture modes for the Progress area. This file owns exactly these iOS modes:
 *
 *   progress
 *   progress-grammar
 *   progress-beginner
 *   progress-beginner-grammar
 *   activity
 *   activity-cards
 *   activity-unsaved
 *   daycard
 *
 * A mode is either WIRED (the real Android screen over `CaptureSeed` data),
 * NOT PORTED (the Android app has no such screen or feature yet — the reason
 * names the master-plan item), or absent (still NOT WIRED in the gallery).
 */
object CaptureProgress {
    val wired: Map<String, @Composable (Context) -> Unit> = mapOf(
        // The Progress tab with a pooled weekly read, so the big CEFR level
        // (not "building") renders. Body only: the tab's top and bottom bars
        // live in `HomeScreen`, private to RootScreen.kt.
        "progress" to @Composable { c: Context ->
            Seeded({ CaptureSeed.once("progress") { seedProgress(c) } }) { ProgressPage(c) }
        },
        // The Grammar page over the ordinary scored talks (no range on file),
        // so the band reads with the vocabulary stand-in ceiling — iOS's
        // `progress-grammar`.
        "progress-grammar" to @Composable { c: Context ->
            Seeded({ CaptureSeed.once("progress-grammar") {
                CaptureSeed.seedVocab(c); CaptureSeed.seedSessions(c, scored = true)
            } }) { ProgressPage(c, Dim.GRAMMAR) }
        },
        // iOS `progress-beginner` (2026-09-24 report): short accurate
        // sentences, no slips — used to read ≈C2. The talks carry a range of
        // a2, so the Grammar row must show ≈A2 with the range line under it.
        "progress-beginner" to @Composable { c: Context ->
            Seeded({ CaptureSeed.once("progress-beginner") { seedBeginner(c) } }) { ProgressPage(c) }
        },
        "progress-beginner-grammar" to @Composable { c: Context ->
            Seeded({ CaptureSeed.once("progress-beginner") { seedBeginner(c) } }) {
                ProgressPage(c, Dim.GRAMMAR)
            }
        },
        // The activity calendar with today selected — the day summary carries
        // the share-card button. iOS's "-cards" grid was folded back into this
        // calendar, and its route renders the very same view, so both do here.
        "activity" to @Composable { c: Context -> Activity(c) },
        "activity-cards" to @Composable { c: Context -> Activity(c) },
        // A call closed without saving — metered, no Session. The day must
        // still be on the calendar, in the month total, and able to make its card.
        "activity-unsaved" to @Composable { c: Context ->
            Seeded({ CaptureSeed.once("activity-unsaved") { meter(c, 8, System.currentTimeMillis()) } }) {
                ActivityScreen(language = lang(c), onOpenTalk = {}, onBack = {})
            }
        },
        // Today's share card with a sample day — no photo, so the ink fallback.
        "daycard" to @Composable { _: Context ->
            DayCardSheet(DayCardData(
                date = System.currentTimeMillis(), talkMinutes = 12, studyMinutes = 25,
                streakDays = 7, talks = 3, reviews = 18, shadowTakes = 4,
                topics = listOf("Did you read about the study on AI replacing language teachers?",
                    "Weekend plans", "Job interview"),
            )) {}
        },
    )

    /** mode → why Android can't show it yet (name the master-plan item). */
    val notPorted: Map<String, String> = mapOf(
    )

    /** The Progress tab's body as the host lays it out: a chip pager that
     *  scrolls its own pages. Body only: the tab's top and bottom bars live
     *  in `HomeScreen`, private to RootScreen.kt. */
    @Composable
    private fun ProgressPage(c: Context, dim: Dim = Dim.OVERALL) {
        Column(
            Modifier.fillMaxSize().background(AppSurfaces.ground).statusBarsPadding(),
        ) {
            ProgressBody(
                language = lang(c),
                nativeLanguage = c.getSharedPreferences("futurevoice", 0)
                    .getString("futurevoice.nativeLanguage", null)
                    ?: LanguageCatalog.defaultNative(),
                onOpenAssessment = {}, onOpenActivity = {},
                goalMinutes = c.getSharedPreferences("futurevoice", 0)
                    .getInt("futurevoice.dailyGoalMinutes", 10),
                onStartTalk = {},
                initialDim = dim,
            )
        }
    }

    @Composable
    private fun Activity(c: Context) {
        Seeded({ CaptureSeed.once("activity") { seedActivity(c) } }) {
            ActivityScreen(language = lang(c), onOpenTalk = {}, onBack = {})
        }
    }

    /** iOS `progress` seed: vocab, scored talks, a scored carryover talk and a b2 weekly read. */
    private suspend fun seedProgress(c: Context) {
        CaptureSeed.seedVocab(c)
        CaptureSeed.seedSessions(c, scored = true)
        CaptureSeed.seedCarryoverSession(c, scored = true)
        val now = System.currentTimeMillis()
        WeeklyReportStore.shared(c).save(WeeklyReport(
            id = UUID.nameUUIDFromBytes("capture:report:progress".toByteArray()).toString().uppercase(),
            periodStart = now - 7 * 86_400_000L, periodEnd = now,
            sessionCount = 6, targetLanguage = "en",
            summary = "Steady, confident week — your range is widening.",
            cefrLevel = "b2", generatedAt = now,
        ), lang(c))
    }

    /** iOS `beginnerScorecard`: accurate, short, one-clause — range a2. */
    private val beginnerScorecard = SessionScorecard(
        vocabulary = AxisScore(60, "Everyday words, used correctly."),
        grammar = AxisScore(96, "No slips in what you said."),
        expressiveness = AxisScore(40, "Short answers — add a detail."),
        fluency = AxisScore(55, "Even pace, short turns."),
        pronunciation = null,
        topLine = "Clear and simple — try linking two ideas.",
        cefrLevel = "a2",
        grammarRange = "a2",
    )

    /** iOS `progress-beginner` seed: vocab, three beginner talks (one-clause
     *  present-tense replies, no slips, range a2) and an a2 weekly read. */
    private suspend fun seedBeginner(c: Context) {
        CaptureSeed.seedVocab(c)
        val now = System.currentTimeMillis()
        val origins = listOf(SessionOrigin.FREE, SessionOrigin.NEWS, SessionOrigin.SCENARIO)
        val uid = StoreJson.newId()
        for (day in 0 until 3) {
            val ended = now - day * 86_400_000L + 3_600_000L
            val started = ended - 600_000L
            val turns = listOf(
                Turn(role = TurnRole.FLUENT_SELF, transcript = "How are you today?",
                    durationMs = 1800, timestamp = started),
                Turn(role = TurnRole.USER, transcript = "I am fine. I am tired.",
                    durationMs = 4_000, timestamp = started + 4_000L),
                Turn(role = TurnRole.FLUENT_SELF, transcript = "What did you do?",
                    durationMs = 1500, timestamp = started + 10_000L),
                Turn(role = TurnRole.USER, transcript = "I go to work. I eat lunch. I like pasta.",
                    durationMs = 6_000, timestamp = started + 14_000L),
            )
            val origin = origins[day % 3]
            SessionStore.shared(c).save(Session(
                // The SAME ids `CaptureSeed.seedSessions` writes, as iOS's
                // `seedSessions(beginner:)` does: the beginner talks replace the
                // ordinary ones instead of joining them on the trend.
                id = UUID.nameUUIDFromBytes("capture:session:sessions-$day".toByteArray())
                    .toString().uppercase(),
                userId = uid, targetLanguage = "en", mode = SessionMode.CONVERSATION,
                topic = when (origin) {
                    SessionOrigin.FREE -> null
                    SessionOrigin.NEWS -> "Four-day work week"
                    SessionOrigin.SCENARIO -> "Job interview"
                },
                startedAt = started, endedAt = ended, turns = turns, origin = origin,
                summary = SessionSummary(
                    overallNote = "Clear and simple — try linking two ideas.",
                    scorecard = beginnerScorecard,
                    expressionsOffered = listOf("what surprised you most", "how did it go"))))
        }
        WeeklyReportStore.shared(c).save(WeeklyReport(
            id = UUID.nameUUIDFromBytes("capture:report:beginner".toByteArray()).toString().uppercase(),
            periodStart = now - 7 * 86_400_000L, periodEnd = now,
            sessionCount = 3, targetLanguage = "en",
            summary = "Short, clear sentences — start linking two ideas in one.",
            cefrLevel = "a2", generatedAt = now,
        ), lang(c))
    }

    /** iOS `activity` seed: the talk-detail talk today plus five earlier talks, each metered. */
    private suspend fun seedActivity(c: Context) {
        val store = SessionStore.shared(c)
        store.save(CaptureSeed.talkDetailSession)
        // Minutes come from the METER, not from the sessions — a seed that
        // only writes sessions draws a flat, empty month.
        meter(c, 11, System.currentTimeMillis())
        val base = CaptureSeed.talkDetailSession
        for ((back, title, mins) in listOf(
            Triple(1, "Weekend plans", 14), Triple(2, "Moving apartments", 6),
            Triple(4, "The interview follow-up", 22), Triple(6, "Coffee with Sarah", 9),
            Triple(9, "Explaining my job", 4))) {
            val ended = ZonedDateTime.now().minusDays(back.toLong()).toInstant().toEpochMilli()
            store.save(base.copy(
                id = UUID.nameUUIDFromBytes("capture:session:activity-$back".toByteArray())
                    .toString().uppercase(),
                topic = title, startedAt = ended - 600_000L, endedAt = ended))
            meter(c, mins, ended)
        }
    }

    /** TOP UP the day's metered talk to [minutes] rather than add, so a
     *  re-launch doesn't grow it (iOS does the same). */
    private fun meter(c: Context, minutes: Int, day: Long) {
        val want = minutes * 60 - TalkTimeLog.secondsOn(c, day, lang(c))
        if (want > 0) TalkTimeLog.add(c, want, lang(c), now = day)
    }
}

private fun lang(c: Context) = LanguageScope.active(c)

/** Run the seed first, then draw the real screen over it. */
@Composable
private fun Seeded(seed: suspend () -> Unit, content: @Composable () -> Unit) {
    var ready by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { seed(); StoreEvents.bump(); ready = true }
    if (ready) content()
}
