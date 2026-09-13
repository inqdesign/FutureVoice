package com.roro.futurevoice.data

import android.content.Context

/**
 * Seconds of talk that make a day COUNT, mirrored from the server's
 * `core_club_config.daily_bar_seconds`.
 *
 * Cached because the streak is drawn on Home, in Activity, in Progress and on
 * the day card — all of which must render offline and none of which can wait
 * on a round trip. The default matches the shipped config, so a device that
 * has never synced still applies the real rule.
 */
object CoreBar {

    private const val PREFS = "futurevoice"
    private const val KEY = "futurevoice.core.dailyBarSeconds"
    private const val DEFAULT_SECONDS = 240

    fun seconds(context: Context): Int {
        val cached = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getInt(KEY, 0)
        return if (cached > 0) cached else DEFAULT_SECONDS
    }

    /** A failure leaves the last known value in place rather than dropping
     *  back to a guess mid-session, so only a real figure is ever written. */
    fun remember(context: Context, seconds: Int) {
        if (seconds <= 0) return
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putInt(KEY, seconds).apply()
    }
}
