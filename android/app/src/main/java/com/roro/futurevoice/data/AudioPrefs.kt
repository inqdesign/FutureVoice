package com.roro.futurevoice.data

import android.content.Context

/**
 * The two hardware facts the learner gets to decide: how loud the fluent self
 * speaks, and which mic listens when earphones are connected.
 *
 * They live together because they are facts about the device in the hand, not
 * about the learner — which is why iOS keeps them on their own page rather
 * than beside the profile.
 */
object AudioPrefs {

    private const val PREFS = "futurevoice"
    private const val VOLUME = "futurevoice.talkVoiceVolume"
    private const val MIC = "futurevoice.micPreference"

    /**
     * A multiplier on the fluent self's voice, 0.25…1.0.
     *
     * On Bluetooth a call plays through the earphone's CALL chain, which the
     * system's headphone-safety cap does NOT limit — so with that cap on, the
     * call can tower over every other listening surface in the app. We cannot
     * detect the cap and will not tell anyone to switch off a hearing-safety
     * setting; this brings the voice DOWN to meet it instead.
     */
    fun talkVoiceVolume(c: Context): Float =
        c.getSharedPreferences(PREFS, 0).getFloat(VOLUME, 1f).coerceIn(0.25f, 1f)

    fun setTalkVoiceVolume(c: Context, v: Float) {
        c.getSharedPreferences(PREFS, 0).edit()
            .putFloat(VOLUME, v.coerceIn(0.25f, 1f)).apply()
    }

    /**
     * Which mic wins while earphones are connected.
     *
     * EARPHONE is the default and the app-wide rule: the mic a learner is
     * WEARING is closer to their mouth than the one in their pocket. The
     * voice clone is the one exception, and it opts out at its own call site
     * rather than by flipping this — Bluetooth records at phone-call quality,
     * and the clone is the surface that cannot forgive it.
     */
    enum class Mic { EARPHONE, PHONE }

    fun mic(c: Context): Mic =
        if (c.getSharedPreferences(PREFS, 0).getString(MIC, null) == "phone") Mic.PHONE
        else Mic.EARPHONE

    fun setMic(c: Context, m: Mic) {
        c.getSharedPreferences(PREFS, 0).edit()
            .putString(MIC, if (m == Mic.PHONE) "phone" else "earphone").apply()
    }
}
