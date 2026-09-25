package com.roro.futurevoice.data

import android.app.Activity
import android.content.Context
import com.roro.futurevoice.BuildConfig
import com.roro.futurevoice.core.Analytics
import com.google.android.play.core.review.ReviewManagerFactory

/**
 * Play's own rating prompt, asked of people who have actually LIVED with the
 * app — never of someone still forming a first impression. Port of
 * `ReviewRequest.swift`.
 *
 * Three bars, all on the meter the ring reads ([TalkTimeLog]), and each rules
 * out a rating that says nothing:
 *
 * - **20 minutes of talk in total.** Talking is the product; a rating from
 *   someone who hasn't spent real time in a call rates the onboarding.
 * - **Talk on 3 different days.** Coming back is the verdict; twenty minutes
 *   in one sitting is still a first impression.
 * - **The call that just ended ran 3 minutes.** Asked on the way out of a
 *   real conversation, never after a dropped or abandoned one.
 *
 * Rules that come from Play, not from us: the store decides whether the sheet
 * appears (quota per user, and nothing appears for an internal-test build),
 * and nothing tells the app whether it did. So the ask is spent per APP
 * VERSION the moment it is requested — a version is the unit a new rating
 * actually describes. And it is gated on USE, never on sentiment: showing it
 * only to someone who gave five stars is review gating, which both stores
 * forbid. The feedback sheet wins its call; this waits for a later one.
 */
object ReviewRequest {
    const val MIN_TALK_SECONDS = 20 * 60
    const val MIN_TALK_DAYS = 3
    const val MIN_CALL_SECONDS = 3 * 60

    private const val ASKED_VERSION_KEY = "futurevoice.reviewRequest.askedVersion"

    fun shouldAsk(context: Context, callSeconds: Long): Boolean {
        if (callSeconds < MIN_CALL_SECONDS) return false
        val prefs = context.getSharedPreferences("futurevoice", 0)
        if (prefs.getString(ASKED_VERSION_KEY, null) == BuildConfig.VERSION_NAME) return false
        return TalkTimeLog.totalSeconds(context) >= MIN_TALK_SECONDS &&
            TalkTimeLog.daysWithTalk(context) >= MIN_TALK_DAYS
    }

    /** Spends this version's ask and asks Play for the sheet. */
    fun ask(activity: Activity) {
        val context = activity.applicationContext
        context.getSharedPreferences("futurevoice", 0).edit()
            .putString(ASKED_VERSION_KEY, BuildConfig.VERSION_NAME).apply()
        Analytics.capture("review_requested", mapOf(
            "talk_seconds" to TalkTimeLog.totalSeconds(context),
            "talk_days" to TalkTimeLog.daysWithTalk(context)))
        runCatching {
            val manager = ReviewManagerFactory.create(context)
            manager.requestReviewFlow().addOnCompleteListener { task ->
                if (!task.isSuccessful) return@addOnCompleteListener
                // Whether anything is shown is Play's call, and the result
                // says nothing either way — there is nothing to handle.
                runCatching { manager.launchReviewFlow(activity, task.result) }
            }
        }
    }
}
