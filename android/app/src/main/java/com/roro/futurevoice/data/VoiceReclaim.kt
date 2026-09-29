package com.roro.futurevoice.data

import android.content.Context

/**
 * A clone made before sign-up is collected upstream 30 minutes after the
 * anonymous user was created (`cleanup-anonymous-voices`). Android never
 * dials it — the voice id is always restored from the server — but someone
 * who comes back to the clone flow deserves to be told why, rather than be
 * greeted as a newcomer (iOS `709b9a0`: positive first, the reason second).
 */
object VoiceReclaim {
    private const val KEY = "futurevoice.unclaimedVoiceSince"
    /** Keep equal to the sweep's GRACE_MINUTES. */
    private const val GRACE_MS = 30L * 60 * 1000

    private fun prefs(c: Context) = c.applicationContext.getSharedPreferences("futurevoice", 0)

    /** A voice was just made on an anonymous session. */
    fun markUnclaimed(c: Context) = prefs(c).edit().putLong(KEY, System.currentTimeMillis()).apply()

    /** An account owns the session (or a new voice exists) — off the clock. */
    fun clear(c: Context) = prefs(c).edit().remove(KEY).apply()

    /** Back at the clone flow with an unclaimed voice past the grace: it's gone. */
    fun wasReclaimed(c: Context): Boolean {
        val since = prefs(c).getLong(KEY, 0L)
        return since > 0 && System.currentTimeMillis() - since > GRACE_MS
    }
}
