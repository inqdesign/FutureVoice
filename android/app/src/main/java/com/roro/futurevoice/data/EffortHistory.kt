package com.roro.futurevoice.data

import android.content.Context
import com.roro.futurevoice.talk.TurnRole
import java.util.Calendar

/**
 * What the learner put in, per day and per kind — the Growth tab's effort
 * card and the page behind it (`EffortDetailScreen`; iOS `EffortHistory`,
 * ce099149). Nothing here is counted for this page alone: talk is the meter's
 * minutes ([TalkTimeLog], the ring's number), every other kind is the count
 * the routine already reads ([PracticeLog]'s STUDIED reps, [ActivityEventLog]
 * for say-it-again runs and Speech takes), so the effort page, the routine
 * and the ring can never tell one day two ways.
 */
enum class EffortCategory {
    TALK, WORDS, EXPRESSIONS, SENTENCES, SHADOWING, SAY_IT_AGAIN, SPEECH, SCENES;

    /** Only talk is measured in time; the rest are things done. */
    val isTimed: Boolean get() = this == TALK
}

data class EffortDay(
    val day: Long,
    /** Time in the app that day, never less than the talk in it (a call in a
     *  pocket is metered but not foregrounded) — the day card's "Study". */
    val studySeconds: Int = 0,
    val talkSeconds: Int = 0,
    val talks: Int = 0,
    val words: Int = 0,
    val expressions: Int = 0,
    val sentences: Int = 0,
    val shadowing: Int = 0,
    val sayItAgain: Int = 0,
    val speech: Int = 0,
    val scenes: Int = 0,
) {
    /** In the category's own unit — minutes for talk, a count otherwise. */
    fun amount(c: EffortCategory): Double = when (c) {
        EffortCategory.TALK -> talkSeconds / 60.0
        EffortCategory.WORDS -> words.toDouble()
        EffortCategory.EXPRESSIONS -> expressions.toDouble()
        EffortCategory.SENTENCES -> sentences.toDouble()
        EffortCategory.SHADOWING -> shadowing.toDouble()
        EffortCategory.SAY_IT_AGAIN -> sayItAgain.toDouble()
        EffortCategory.SPEECH -> speech.toDouble()
        EffortCategory.SCENES -> scenes.toDouble()
    }

    /** Study time that wasn't talking — words, cards, shadowing, scenes… */
    val otherSeconds: Int get() = maxOf(0, studySeconds - talkSeconds)

    /** Something was DONE — opening the app alone is not a day of practice. */
    val isActive: Boolean get() = EffortCategory.entries.any { amount(it) > 0 }
}

object EffortHistory {
    /** How far back talk minutes reach — [TalkTimeLog] keeps 45 days, so a
     *  comparison window that starts earlier would read missing days as 0. */
    const val TALK_REACH_DAYS = 45

    fun studyMinutes(days: List<EffortDay>): Int = days.sumOf { it.studySeconds } / 60
    fun otherMinutes(days: List<EffortDay>): Int = days.sumOf { it.otherSeconds } / 60
    fun total(c: EffortCategory, days: List<EffortDay>): Double = days.sumOf { it.amount(c) }

    /** [count] days ending today, oldest first. */
    suspend fun days(context: Context, count: Int, language: String,
                     now: Long = System.currentTimeMillis()): List<EffortDay> {
        if (count <= 0) return emptyList()
        val cal = Calendar.getInstance().apply {
            timeInMillis = now
            set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
            add(Calendar.DAY_OF_YEAR, -(count - 1))
        }
        val starts = (0..count).map {
            val at = cal.timeInMillis
            cal.add(Calendar.DAY_OF_YEAR, 1)
            at
        }
        val events = ActivityEventLog.events(context, starts.first(), starts.last())
        val ended = SessionStore.shared(context).load(language).filter { it.endedAt != null }
        val attempts = ShadowAttemptStore.shared(context).load(language)
        val cards = DrillStore.shared(context).load(language)

        return (0 until count).map { i ->
            val d = starts[i]
            val next = starts[i + 1]
            fun inDay(at: Long) = at >= d && at < next
            val log = PracticeLog.day(context, d) ?: PracticeLog.Day()
            // The log only exists from the day it shipped; shadow attempts and
            // card review dates are the floor for the days before it — the
            // same backfill Growth's charts always used.
            val shadowed = attempts.count { inDay(it.createdAt) }
            val reviewed = cards.count { c -> c.lastReviewedAt?.let(::inDay) ?: false }
            val dayEvents = events.filter { inDay(it.at) }
            val talkSeconds = TalkTimeLog.secondsToday(context, d)
            EffortDay(
                day = d,
                studySeconds = maxOf(AppUsageLog.secondsWithOpenStint(context, d, now), talkSeconds),
                talkSeconds = talkSeconds,
                talks = ended.count { s ->
                    inDay(s.endedAt ?: s.startedAt) && s.turns.any { it.role == TurnRole.USER }
                },
                words = log.wordReps,
                expressions = log.expressionReps,
                sentences = maxOf(log.drillReps, reviewed),
                shadowing = maxOf(log.shadowReps, shadowed),
                sayItAgain = dayEvents.count { it.kind == ActivityEventLog.Kind.SAY_IT_AGAIN },
                speech = dayEvents.count { it.kind == ActivityEventLog.Kind.SPEECH },
                scenes = log.sceneReps,
            )
        }
    }
}
