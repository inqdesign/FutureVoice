package com.roro.futurevoice.capture

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import com.roro.futurevoice.data.ActivityEventLog
import com.roro.futurevoice.data.LanguageScope
import com.roro.futurevoice.data.PromiseLedger
import com.roro.futurevoice.data.SessionStore
import com.roro.futurevoice.data.StoreEvents
import com.roro.futurevoice.data.StudyPlan
import com.roro.futurevoice.data.StudyPlan.Block
import com.roro.futurevoice.data.StudyPlan.Kind
import com.roro.futurevoice.data.StudyPlanStore
import com.roro.futurevoice.data.TalkTimeLog
import com.roro.futurevoice.ui.ActivityScreen
import com.roro.futurevoice.ui.BlockTarget
import com.roro.futurevoice.ui.WeeklyPlanEditor
import java.util.UUID

/**
 * "My routine" (iOS 1.1.4): the routine page, its weekly editor and the
 * block sheet, over a seeded week.
 *
 *   activity-week       the day view, a promise kept since Monday
 *   activity-week-edit  the weekly plan editor
 *   plan-block          the block sheet, a new block at 20:00 today
 *   plan-editor         the editor with "any time" blocks and Sunday off
 *   routine-new         the onboarding routine: talk 10 min, any time
 *
 * `--es activityMode month|year` opens the page on that view.
 */
object CaptureRoutine {
    val wired: Map<String, @Composable (Context) -> Unit> = mapOf(
        "activity-week" to @Composable { c: Context ->
            Seeded({ CaptureSeed.once("activity-week") { seedWeek(c) } }) {
                ActivityScreen(language = LanguageScope.active(c), onOpenTalk = {}, onBack = {},
                    initialMode = (c as? android.app.Activity)?.intent?.getStringExtra("activityMode"))
            }
        },
        "activity-week-edit" to @Composable { c: Context ->
            Seeded({ CaptureSeed.once("activity-week") { seedWeek(c) } }) {
                ActivityScreen(language = LanguageScope.active(c), onOpenTalk = {}, onBack = {}, startEditing = true)
            }
        },
        "plan-block" to @Composable { c: Context ->
            Seeded({ CaptureSeed.once("activity-week") { seedWeek(c) } }) {
                WeeklyPlanEditor(onClose = {}, captureBlock = BlockTarget.NewInWeek(
                    StudyPlan.weekday(System.currentTimeMillis()), 20, 0))
            }
        },
        "plan-editor" to @Composable { c: Context ->
            Seeded({ CaptureSeed.once("plan-editor") { seedEditor(c) } }) { WeeklyPlanEditor(onClose = {}) }
        },
        "routine-new" to @Composable { c: Context ->
            Seeded({ CaptureSeed.once("routine-new") {
                StudyPlanStore.update(c, StudyPlan.seeded(emptyList(), 10, callEnabled = false))
                PromiseLedger.replaceAll(c, emptyMap())
            } }) {
                ActivityScreen(language = LanguageScope.active(c), onOpenTalk = {}, onBack = {})
            }
        },
    )

    /**
     * A weekday talk at 8:00 with say it again after it, review twice a
     * week and every evening, and a few days of what actually happened — one
     * talk moved to noon, review sittings, one say-it-again run.
     */
    private suspend fun seedWeek(c: Context) {
        val today = StudyPlan.startOfDay(System.currentTimeMillis())
        fun at(back: Int, h: Int, m: Int = 0) = StudyPlan.at(StudyPlan.addDays(today, -back), h, m)
        val plan = StudyPlan(
            blocks = listOf(
                Block(kind = Kind.TALK, weekdays = (2..6).toSet(), hour = 8, minute = 0, minutes = 10),
                Block(kind = Kind.SAY_IT_AGAIN, weekdays = (2..6).toSet(), hour = 8, minute = 10, minutes = 1),
                Block(kind = Kind.REVIEW, weekdays = setOf(3, 5), hour = 19, minute = 30, minutes = 10),
                Block(kind = Kind.REVIEW, weekdays = (2..6).toSet(), hour = 21, minute = 0, minutes = 20),
            ),
            streakSince = StudyPlan.addDays(today, -4),
        )
        PromiseLedger.replaceAll(c, emptyMap())
        StudyPlanStore.update(c, plan)
        val store = SessionStore.shared(c)
        val base = CaptureSeed.talkDetailSession
        val language = LanguageScope.active(c)
        for ((back, span, title) in listOf(
            Triple(3, at(3, 8, 3) to at(3, 8, 15), "Weekend plans"),
            Triple(2, at(2, 12, 20) to at(2, 12, 33), "Moving apartments"),
            Triple(1, at(1, 8, 1) to at(1, 8, 12), "The interview follow-up"),
            Triple(0, at(0, 8, 2) to at(0, 8, 14), "Coffee with Sarah"))) {
            store.save(base.copy(
                id = UUID.nameUUIDFromBytes("capture:session:routine-$back".toByteArray()).toString().uppercase(),
                topic = title, startedAt = span.first, endedAt = span.second))
            val want = ((span.second - span.first) / 60_000L).toInt() * 60 - TalkTimeLog.secondsOn(c, span.first, language)
            if (want > 0) TalkTimeLog.add(c, want, language, now = span.first)
        }
        val events = buildList {
            for (m in 5 until 20 step 3) add(ActivityEventLog.Event(ActivityEventLog.Kind.DRILL, at(3, 21, m)))
            for (m in 0 until 12 step 4) add(ActivityEventLog.Event(ActivityEventLog.Kind.SHADOW, at(2, 17, m)))
            for (m in 32 until 45 step 4) add(ActivityEventLog.Event(ActivityEventLog.Kind.WORD, at(2, 19, m)))
            for (m in 2 until 18 step 3) add(ActivityEventLog.Event(ActivityEventLog.Kind.DRILL, at(1, 21, m)))
            add(ActivityEventLog.Event(ActivityEventLog.Kind.SAY_IT_AGAIN, at(0, 8, 20)))
        }
        ActivityEventLog.replaceAll(c, events)
    }

    private fun seedEditor(c: Context) {
        StudyPlanStore.update(c, StudyPlan(
            blocks = listOf(
                Block(kind = Kind.TALK, weekdays = (2..6).toSet(), hour = 8, minute = 0, minutes = 10),
                Block(kind = Kind.SAY_IT_AGAIN, weekdays = setOf(2, 4), hour = 20, minute = 30, minutes = 1),
                Block(kind = Kind.REVIEW, weekdays = setOf(3, 5), hour = 19, minute = 30, minutes = 10),
                // Blocks with no hour, for the editor's "any time" row.
                Block(kind = Kind.TALK, weekdays = setOf(7), hour = 0, minute = 0, minutes = 15, anytime = true),
                Block(kind = Kind.REVIEW, weekdays = setOf(2, 4, 6), hour = 0, minute = 0, minutes = 10, anytime = true),
                Block(kind = Kind.REVIEW, weekdays = (1..7).toSet(), hour = 21, minute = 0, minutes = 20),
            ),
            offWeekdays = setOf(1),
        ))
    }
}

/** Run the seed first, then draw the real screen over it. */
@Composable
private fun Seeded(seed: suspend () -> Unit, content: @Composable () -> Unit) {
    var ready by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { seed(); StoreEvents.bump(); ready = true }
    if (ready) content()
}
