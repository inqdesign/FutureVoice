package com.roro.futurevoice.ui.brand

import androidx.compose.runtime.Composable
import androidx.compose.ui.res.stringResource
import com.roro.futurevoice.R
import java.util.Calendar

/**
 * The line above the ring — `HeroGreeting.swift`. Short on purpose: it is
 * set in a display face above the ring, and anything past a line and a half
 * pushes the ring off the fold. Rotation is the day plus the finished-call
 * cursor, so the line can never change while it is on screen.
 */
object HeroGreeting {

    data class Input(
        val sessionCount: Int = 0,
        val daysSinceLastTalk: Int? = null,
        val todaySpokenSeconds: Int = 0,
        val dailyGoalMinutes: Int = 10,
        val rotationCursor: Int = 0,
        val hour: Int = Calendar.getInstance().get(Calendar.HOUR_OF_DAY),
        val dayOfYear: Int = Calendar.getInstance().get(Calendar.DAY_OF_YEAR),
    )

    @Composable
    fun text(input: Input): String {
        val options: List<Int> = when {
            input.sessionCount == 0 -> listOf(
                R.string.ready_for_your_first_talk, R.string.shall_we_start_small)
            (input.daysSinceLastTalk ?: 0) >= 4 -> listOf(
                R.string.it_s_been_a_while, R.string.good_to_have_you_back,
                R.string.long_time_where_were_we)
            input.todaySpokenSeconds >= input.dailyGoalMinutes * 60 -> listOf(
                R.string.today_s_done_one_more, R.string.you_hit_today_s_goal,
                R.string.goal_met_how_did_it_feel)
            else -> questions(input.hour)
        }
        val i = ((input.dayOfYear + input.rotationCursor) % options.size).let {
            if (it < 0) it + options.size else it
        }
        return stringResource(options[i])
    }

    /** Four openings per stretch of the day. */
    private fun questions(hour: Int): List<Int> = when (hour) {
        in 5..11 -> listOf(R.string.what_s_on_your_mind_this_morning, R.string.did_you_sleep_well,
            R.string.what_s_the_plan_today, R.string.how_does_today_look)
        in 12..16 -> listOf(R.string.what_s_on_your_mind_this_afternoon, R.string.how_s_your_day_going,
            R.string.busy_today, R.string.what_did_you_do_today)
        in 17..21 -> listOf(R.string.what_s_on_your_mind_this_evening_e4eefc, R.string.how_was_your_day,
            R.string.anything_good_today, R.string.how_did_today_go)
        else -> listOf(R.string.what_s_on_your_mind_tonight, R.string.still_up,
            R.string.how_was_today, R.string.thinking_about_tomorrow)
    }
}
