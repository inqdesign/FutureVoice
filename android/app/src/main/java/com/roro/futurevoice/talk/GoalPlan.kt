package com.roro.futurevoice.talk

import android.content.Context
import android.content.res.Resources
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.roro.futurevoice.R
import com.roro.futurevoice.core.Analytics
import com.roro.futurevoice.data.IsoDateMillisSerializer
import com.roro.futurevoice.data.StoreEvents
import com.roro.futurevoice.data.StoreJson
import com.roro.futurevoice.data.StudyPlan
import com.roro.futurevoice.data.StudyPlanStore
import com.roro.futurevoice.data.UpcomingGoal
import com.roro.futurevoice.data.UpcomingGoalStore
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import java.io.File
import java.util.TimeZone
import kotlin.math.ceil

/**
 * The road from today to a dated goal, laid on the learner's own routine
 * (iOS `GoalPlan`, 6aece49b; founder 2026-11-12: "when there's a deadline,
 * show a rough plan; I say I'll go with it, and it really becomes my daily
 * routine"). The GOAL FILLS THE ROUTINE: the routine keeps its times (when),
 * the goal decides what each talk block practises until its day (what), and
 * the tutor says today's one thing. After the day the routine is what it was.
 *
 * Computed from what is already on disk (the goal's likely questions, where
 * each stands, the routine's talk days) and never stored: a skipped day or a
 * question done early simply moves the rest. The only stored fact is that the
 * learner said "use this plan" ([GoalPlanStore]).
 */
data class GoalPlan(
    val goal: UpcomingGoal,
    /** One row per practice day, from today to the goal's day. */
    val rows: List<Row>,
    val ready: Int,
    val total: Int,
) {
    /** What a day of the plan practises. */
    sealed interface Item {
        /** Build the answer to one likely question, in a tutor drill. */
        data class Question(val text: String) : Item
        /** Once more on the ones not ready yet: a build day with no new
         *  question left to give it. */
        data object CatchUp : Item
        /** The day itself as a run-through: the questions one after another. */
        data object Rehearse : Item
        /** The day: a short warm-up. */
        data object TheDay : Item

        val isQuestion: Boolean get() = this is Question

        /** One short line for the routine's day list and the tutor's note. */
        fun label(res: Resources): String = when (this) {
            is Question -> text
            CatchUp -> res.getString(R.string.once_more_the_ones_not_ready_yet)
            Rehearse -> res.getString(R.string.mock_run_the_questions_one_after_another)
            TheDay -> res.getString(R.string.the_day_a_short_warm_up)
        }

        /** The call this item opens, through the tutor's goal door. */
        fun call(c: Context, goal: UpcomingGoal): TutorBot.GoalCall = when (this) {
            is Question -> TutorBot.GoalCall(topic = "“$text” — ${goal.title}", blurb = goal.drillBlurb,
                lessonTopicId = GoalPrep.topicId(goal, text))
            CatchUp -> {
                val first = open(c, goal)?.first?.firstOrNull()
                if (first != null) Question(first).call(c, goal) else Rehearse.call(c, goal)
            }
            Rehearse -> {
                val qs = (GoalPrep.cachedQuestions(c, goal) ?: emptyList()).map { it.text }
                var blurb = goal.drillBlurb
                blurb += GoalPlanPrompts.MOCK_RUN
                if (qs.isNotEmpty()) blurb += GoalPlanPrompts.MOCK_RUN_QUESTIONS +
                    qs.joinToString(GoalPlanPrompts.MOCK_RUN_SEPARATOR)
                TutorBot.GoalCall(topic = c.getString(R.string.mock_run) + " — ${goal.title}", blurb = blurb,
                    tutor = false)
            }
            TheDay -> TutorBot.GoalCall(topic = c.getString(R.string.warm_up) + " — ${goal.title}",
                blurb = goal.drillBlurb + GoalPlanPrompts.THE_DAY, tutor = false)
        }
    }

    data class Row(val date: Long, val item: Item) {
        val id: Long get() = date
    }

    /** What today's talk practises: today's row, or (on a day the routine
     *  has no talk) the next question still open. */
    val today: Item?
        get() {
            val day = StudyPlan.startOfDay(System.currentTimeMillis())
            rows.firstOrNull { StudyPlan.isSameDay(it.date, day) }?.let { return it.item }
            return rows.firstOrNull()?.item
        }

    fun items(on: Long, zone: TimeZone = TimeZone.getDefault()): List<Item> =
        rows.filter { StudyPlan.isSameDay(it.date, on, zone) }.map { it.item }

    companion object {
        /** Days the routine has a talk on (Gregorian weekdays). Every day when
         *  the routine has none: adopting the plan adds one ([adopt]). */
        fun talkWeekdays(plan: StudyPlan): Set<Int> {
            val off = plan.offWeekdays ?: emptySet()
            val days = plan.blocks.filter { it.kind == StudyPlan.Kind.TALK }.flatMap { it.weekdays }.toSet() - off
            return if (days.isEmpty()) (1..7).toSet() - off else days
        }

        /** The questions not ready yet, in the page's order. */
        fun open(c: Context, goal: UpcomingGoal): Pair<List<String>, Int>? {
            val questions = GoalPrep.cachedQuestions(c, goal)?.takeIf { it.isNotEmpty() } ?: return null
            val lessons = TutorLessonStore.all(c, goal.language)
            val open = questions.map { it.text }
                .filter { GoalPrep.state(it, goal, lessons) != GoalPrep.QuestionState.READY }
            return open to questions.size
        }

        /** Null without a date, once the day has passed, or before the page
         *  has worked out the questions. */
        fun make(c: Context, goal: UpcomingGoal, routine: StudyPlan? = null,
                 now: Long = System.currentTimeMillis()): GoalPlan? {
            val left = goal.daysLeft(now) ?: return null
            if (left < 0) return null
            val date = goal.date ?: return null
            val qs = open(c, goal) ?: return null
            return make(goal, qs.first, qs.second, date,
                talkWeekdays(routine ?: StudyPlanStore.current(c)), now)
        }

        /** The pure half (`GoalPlanTest`). */
        fun make(goal: UpcomingGoal, open: List<String>, total: Int, day: Long, talkDays: Set<Int>,
                 now: Long, zone: TimeZone = TimeZone.getDefault()): GoalPlan {
            val today = StudyPlan.startOfDay(now, zone)
            val theDay = StudyPlan.startOfDay(day, zone)
            val practice = ArrayList<Long>()
            var d = today
            while (d < theDay) {
                if (StudyPlan.weekday(d, zone) in talkDays) practice += d
                d = StudyPlan.addDays(d, 1, zone)
            }
            // The last days before are a run-through, not new answers: two
            // when there's room, one when it's short, none when there's
            // barely time to build an answer per question.
            val rehearsals = if (practice.size >= open.size + 2) 2 else if (practice.size >= open.size + 1) 1 else 0
            val build = practice.dropLast(rehearsals)
            val rows = ArrayList<Row>()
            // More questions than days: several a day, in order. Fewer: one a
            // day, then the days left go over what's still not ready.
            val perDay = if (build.isEmpty()) 0
                else maxOf(1, ceil(open.size.toDouble() / build.size.toDouble()).toInt())
            for ((i, date) in build.withIndex()) {
                val slice = open.drop(i * perDay).take(perDay)
                if (slice.isEmpty()) {
                    rows += Row(date, if (open.isEmpty()) Item.Rehearse else Item.CatchUp)
                } else {
                    rows += slice.map { Row(date, Item.Question(it)) }
                }
            }
            rows += practice.takeLast(rehearsals).map { Row(it, Item.Rehearse) }
            rows += Row(theDay, Item.TheDay)
            return GoalPlan(goal, rows, ready = total - open.size, total = total)
        }

        /** The goal whose plan the learner put in their routine, for a target
         *  language: the nearest one when there are several. */
        fun active(c: Context, language: String, now: Long = System.currentTimeMillis()): GoalPlan? {
            val adopted = GoalPlanStore.adopted(c)
            for (goal in UpcomingGoalStore.active(c, language, now)) {
                if (goal.id !in adopted) continue
                make(c, goal, now = now)?.let { return it }
            }
            return null
        }

        /** What a routine talk opens today, when a plan is in the routine. */
        fun todaysCall(c: Context, language: String): TutorBot.GoalCall? {
            val plan = active(c, language) ?: return null
            val item = plan.today ?: return null
            return item.call(c, plan.goal)
        }

        /** "Use this plan": remember it, and give a routine with no talk one. */
        fun adopt(c: Context, goal: UpcomingGoal) {
            GoalPlanStore.set(c, goal.id, adopted = true)
            val plan = StudyPlanStore.current(c)
            if (plan.blocks.none { it.kind == StudyPlan.Kind.TALK }) {
                val days = (1..7).toSet() - (plan.offWeekdays ?: emptySet())
                val talk = StudyPlan.Block(kind = StudyPlan.Kind.TALK, weekdays = days, hour = 0, minute = 0,
                    minutes = maxOf(10, StudyPlanStore.goalMinutes(c)), anytime = true)
                StudyPlanStore.update(c, plan.copy(blocks = listOf(talk) + plan.blocks), byLearner = true)
            }
            Analytics.capture("goal_plan_adopted", mapOf("kind" to goal.kind.raw, "days_left" to (goal.daysLeft() ?: -1)))
        }
    }
}

/**
 * Which goals' plans are in the routine (iOS `GoalPlanStore`,
 * `goal_plans.json`). Its own file and sync kind, never a field on
 * [UpcomingGoal]: an older build re-saving the goal would drop a field it
 * doesn't know, and the newer stamp would win.
 */
object GoalPlanStore {
    const val FILENAME = "goal_plans.json"

    @Serializable
    data class Entry(
        /** The goal's id. */
        val id: String,
        @Serializable(with = IsoDateMillisSerializer::class) val adoptedAt: Long,
        @Serializable(with = IsoDateMillisSerializer::class) val updatedAt: Long,
    )

    var entries by mutableStateOf<List<Entry>>(emptyList())
        private set

    private var loaded = false
    private val serializer = ListSerializer(Entry.serializer())

    private fun file(c: Context) = File(c.applicationContext.filesDir, FILENAME)

    fun adopted(c: Context): Set<String> {
        ensureLoaded(c)
        return entries.map { it.id }.toSet()
    }

    fun ensureLoaded(c: Context) {
        if (!loaded) reload(c)
    }

    fun reload(c: Context) {
        loaded = true
        entries = runCatching {
            file(c).takeIf { it.exists() }?.readText()?.let { StoreJson.json.decodeFromString(serializer, it) }
        }.getOrNull().orEmpty()
    }

    fun set(c: Context, goalId: String, adopted: Boolean) {
        ensureLoaded(c)
        var list = entries.filter { it.id != goalId }
        if (adopted) {
            val now = System.currentTimeMillis()
            list = list + Entry(goalId, adoptedAt = now, updatedAt = now)
        }
        entries = list
        runCatching {
            val target = file(c)
            val tmp = File(target.parentFile, target.name + ".tmp")
            tmp.writeText(StoreJson.json.encodeToString(serializer, list))
            if (!tmp.renameTo(target)) { target.delete(); tmp.renameTo(target) }
        }
        StoreEvents.bump()
    }
}
