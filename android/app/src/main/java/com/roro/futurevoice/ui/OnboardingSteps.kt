package com.roro.futurevoice.ui

import android.content.Context

/**
 * The onboarding beats' "seen" flags.
 *
 * The daily-call and weekly-rhythm screens that used to follow the clone were
 * replaced by the routine builder over the Talk tab ([RoutineOnboardingOverlay],
 * iOS 2026-10-18). Their keys stay: [DAILY_CALL] is the builder's gate, so an
 * install that saw the old screens never sees the builder, and both are set
 * when it finishes so nothing that reads them asks again.
 */
object OnboardingFlags {
    private const val PREFS = "futurevoice"
    const val DAILY_CALL = "futurevoice.dailyCall.onboarded"
    /** The old "once a week" step (test day + time). */
    const val WEEKLY_RHYTHM = "futurevoice.weeklyRhythm.onboarded"

    fun seen(c: Context, key: String) =
        c.getSharedPreferences(PREFS, 0).getBoolean(key, false)

    fun markSeen(c: Context, key: String) {
        c.getSharedPreferences(PREFS, 0).edit().putBoolean(key, true).apply()
    }
}
