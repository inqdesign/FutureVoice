package com.roro.futurevoice.data

import android.content.Context
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import java.io.File

/**
 * The routine on disk (`files/study_plan.json`) plus the published copy every
 * screen watches (iOS `StudyPlanStore`). Device-local, like the daily call it
 * schedules.
 *
 * The routine and the call are ONE list: the plan's timed talk blocks ARE the
 * call times. An edit here mirrors its distinct talk times into
 * [DailyCallStore]; a call time set elsewhere (Me → Call, onboarding) comes
 * back in through [callTimesChanged].
 */
object StudyPlanStore {

    private val _plan = MutableStateFlow(StudyPlan())
    val plan: StateFlow<StudyPlan> = _plan
    @Volatile private var loaded = false
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    private fun file(c: Context) = File(c.filesDir, "study_plan.json")

    /** The plan, read from disk once (seeded on first use). */
    fun current(c: Context): StudyPlan { ensure(c); return _plan.value }

    @Synchronized
    private fun ensure(c: Context) {
        if (loaded) return
        val decoded = runCatching {
            file(c).takeIf { it.exists() }?.readText()
                ?.let { StoreJson.json.decodeFromString(StudyPlan.serializer(), it) }
        }.getOrNull()
        val plan = decoded?.foldingIntoReview() ?: seededNow(c)
        _plan.value = plan
        loaded = true
        if (plan != decoded) write(c, plan)
    }

    private fun seededNow(c: Context) = StudyPlan.seeded(
        callTimes = DailyCallStore.times(c), goalMinutes = goalMinutes(c),
        callEnabled = DailyCallStore.isEnabled(c))

    fun goalMinutes(c: Context): Int =
        c.getSharedPreferences("futurevoice", 0).getInt("futurevoice.dailyGoalMinutes", 10)
            .takeIf { it > 0 } ?: 10

    /**
     * Setup just finished: the first routine is what onboarding said — talk
     * X minutes a day. Nothing could have edited the routine before this (it
     * is reached from the app, after setup), so it is written fresh; the
     * call step that follows places its time through [callTimesChanged].
     */
    fun seedFromOnboarding(c: Context) {
        ensure(c)
        val plan = seededNow(c)
        _plan.value = plan
        write(c, plan)
        StoreEvents.bump()
    }

    /**
     * Replace the plan. False (and nothing changes) when it would need more
     * call times than the call can ring.
     *
     * [byLearner]: the learner changed their routine by hand. That is what
     * makes it their PROMISE: the first hand edit starts `streakSince`. An
     * empty routine is no promise.
     */
    fun update(c: Context, new: StudyPlan, byLearner: Boolean = false): Boolean {
        ensure(c)
        val old = _plan.value
        val now = System.currentTimeMillis()
        var next = new.foldingIntoReview()
        next = when {
            next.blocks.isEmpty() -> next.copy(streakSince = null)
            byLearner && next.streakSince == null -> next.copy(streakSince = StudyPlan.startOfDay(now))
            else -> next
        }.prunedBefore(now)
        if (!next.isCallable) return false
        val callsChanged = next.callTimes != old.callTimes ||
            next.blocks.filter { it.kind == StudyPlan.Kind.TALK } != old.blocks.filter { it.kind == StudyPlan.Kind.TALK } ||
            next.exceptions != old.exceptions || next.restDays != old.restDays ||
            next.offWeekdays != old.offWeekdays
        _plan.value = next
        write(c, next)
        if (callsChanged) {
            if (next.callTimes.isNotEmpty()) DailyCallStore.mirrorTimes(c, next.callTimes)
            if (DailyCallStore.isEnabled(c)) DailyCallScheduler.schedule(c)
        }
        afterChange(c)
        return true
    }

    /** The daily call was switched on: a routine whose talks are all "any
     *  time" gets them placed at the call's time — otherwise turning the call
     *  on would ring nothing. A routine with a timed talk is left alone. */
    fun callTurnedOn(c: Context) {
        val plan = current(c)
        if (plan.hasTimedTalk) return
        update(c, plan.adoptingCallTimes(DailyCallStore.times(c), goalMinutes(c)))
    }

    /** The call times were set from somewhere other than the plan. */
    fun callTimesChanged(c: Context, times: List<Int>) {
        val plan = current(c)
        val next = plan.adoptingCallTimes(times, goalMinutes(c))
        if (next == plan) return
        _plan.value = next
        write(c, next)
        afterChange(c)
    }

    private fun afterChange(c: Context) {
        val app = c.applicationContext
        scope.launch {
            // The day's promise standing follows the plan it is judged by.
            runCatching { PromiseJudge.refresh(app) }
            runCatching { DrillReminder.reschedule(app) }
            runCatching { PlanReminder.reschedule(app) }
            StoreEvents.bump()
        }
    }

    private fun write(c: Context, plan: StudyPlan) {
        runCatching {
            val target = file(c)
            val tmp = File(target.parentFile, target.name + ".tmp")
            tmp.writeText(StoreJson.json.encodeToString(StudyPlan.serializer(), plan))
            if (!tmp.renameTo(target)) { target.delete(); tmp.renameTo(target) }
        }
    }
}
