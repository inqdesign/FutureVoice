package com.roro.futurevoice.data

import android.content.Context
import androidx.annotation.StringRes
import com.roro.futurevoice.R
import com.roro.futurevoice.talk.ConversationPrompt

/**
 * What the learner's fluent self already DOES — picked once in setup
 * ("Imagine your future", iOS `FutureGoal`, 3d655c8b). Each purpose offers
 * two or three; the learner ticks as many as they like.
 *
 * Stored as ids on `UserPersona.goals`, never as text: the label follows the
 * app language, the prompt reads [promptText], and an id from a newer build
 * that this one doesn't know is simply skipped. Never shown to strangers —
 * nothing that writes the public intro or a cast counterpart's block reads it.
 */
enum class FutureGoal(val raw: String) {
    START_ORDER("start.order"),
    START_CHAT("start.chat"),
    HOBBY_LIKES("hobby.likes"),
    HOBBY_NO_SUBS("hobby.noSubs"),
    HOBBY_FRIENDS("hobby.friends"),
    EXAM_SCORE("exam.score"),
    EXAM_CALM("exam.calm"),
    STUDY_SEMINAR("study.seminar"),
    STUDY_PRESENT("study.present"),
    JOB_INTERVIEW("job.interview"),
    JOB_OFFER("job.offer"),
    WORK_MEETINGS("work.meetings"),
    WORK_CLIENTS("work.clients"),
    WORK_BANTER("work.banter"),
    ABROAD_ERRANDS("abroad.errands"),
    ABROAD_NEIGHBORS("abroad.neighbors"),
    ABROAD_HOME("abroad.home"),
    TRAVEL_ALONE("travel.alone"),
    TRAVEL_LOCALS("travel.locals");

    val purpose: LearningPurpose get() = when (this) {
        START_ORDER, START_CHAT -> LearningPurpose.START
        HOBBY_LIKES, HOBBY_NO_SUBS, HOBBY_FRIENDS -> LearningPurpose.HOBBY
        EXAM_SCORE, EXAM_CALM -> LearningPurpose.EXAM
        STUDY_SEMINAR, STUDY_PRESENT -> LearningPurpose.STUDY
        JOB_INTERVIEW, JOB_OFFER -> LearningPurpose.JOB
        WORK_MEETINGS, WORK_CLIENTS, WORK_BANTER -> LearningPurpose.WORK
        ABROAD_ERRANDS, ABROAD_NEIGHBORS, ABROAD_HOME -> LearningPurpose.ABROAD
        TRAVEL_ALONE, TRAVEL_LOCALS -> LearningPurpose.TRAVEL
    }

    /** First person, present tense: the future already lived. */
    @get:StringRes val title: Int get() = when (this) {
        START_ORDER -> R.string.i_order_and_ask_for_things_without_freezing
        START_CHAT -> R.string.i_keep_a_simple_conversation_going
        HOBBY_LIKES -> R.string.i_talk_about_what_i_love_for_as_long_as_i_want
        HOBBY_NO_SUBS -> R.string.i_watch_shows_without_subtitles
        HOBBY_FRIENDS -> R.string.i_have_friends_i_chat_with_in_the_language
        EXAM_SCORE -> R.string.i_got_the_score_i_needed
        EXAM_CALM -> R.string.i_answer_the_speaking_test_calmly
        STUDY_SEMINAR -> R.string.i_speak_up_in_seminars
        STUDY_PRESENT -> R.string.i_present_my_work_with_confidence
        JOB_INTERVIEW -> R.string.i_tell_my_story_in_interviews_without_freezing
        JOB_OFFER -> R.string.i_got_the_job_i_wanted
        WORK_MEETINGS -> R.string.i_lead_meetings
        WORK_CLIENTS -> R.string.client_calls_don_t_make_me_nervous
        WORK_BANTER -> R.string.i_joke_around_with_my_colleagues
        ABROAD_ERRANDS -> R.string.i_handle_the_doctor_the_landlord_and_the_town_hall_myself
        ABROAD_NEIGHBORS -> R.string.i_chat_easily_with_neighbors_and_other_parents
        ABROAD_HOME -> R.string.this_place_feels_like_home
        TRAVEL_ALONE -> R.string.i_travel_on_my_own_without_worrying
        TRAVEL_LOCALS -> R.string.i_talk_with_locals_not_just_order
    }

    /** What the fluent self is told (iOS `promptText(languageName:)`, lifted
     *  into [ConversationPrompt.futureGoalText]). */
    fun promptText(languageName: String): String = ConversationPrompt.futureGoalText(raw, languageName)

    companion object {
        fun from(raw: String): FutureGoal? = entries.firstOrNull { it.raw == raw }

        fun options(purpose: LearningPurpose): List<FutureGoal> = entries.filter { it.purpose == purpose }

        /** Ids on disk → goals this build knows, in the order ticked. */
        fun decode(ids: List<String>): List<FutureGoal> = ids.mapNotNull { from(it) }
    }
}

/**
 * The goals picked in setup, held until the persona exists (it is written
 * one step later, by the persona cards) — `AppViewModel.savePersona` moves
 * them onto it (iOS `FutureGoalStore`, same key).
 */
object FutureGoalStore {
    private const val PREFS = "futurevoice"
    private const val KEY = "futurevoice.pendingFutureGoals"

    private fun p(c: Context) = c.getSharedPreferences(PREFS, 0)

    fun pending(c: Context): List<FutureGoal> =
        FutureGoal.decode((p(c).getString(KEY, null) ?: "").split(',').filter { it.isNotEmpty() })

    fun setPending(c: Context, value: List<FutureGoal>) {
        if (value.isEmpty()) p(c).edit().remove(KEY).apply()
        else p(c).edit().putString(KEY, value.joinToString(",") { it.raw }).apply()
    }
}
