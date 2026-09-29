package com.roro.futurevoice.data

import android.content.Context
import androidx.annotation.StringRes
import com.roro.futurevoice.R

/**
 * How fast the fluent self speaks — ElevenLabs `voice_settings.speed`, sent
 * with every synthesis (iOS `SpeechSpeed`, 2026-09-23). SYNTHESIS, not
 * playback: the pitch is untouched, so a slowed line still sounds like the
 * learner, and word timings come back measured against the audio made.
 *
 * Three rungs, each ~12% apart by ear: Normal 1.0 (the clone at the speed it
 * was recorded) · Relaxed 0.9 (the default) · Slow 0.8. Nothing below 0.8 has
 * been listened to, so nothing below 0.8 ships.
 */
enum class SpeechSpeed(val raw: String, @StringRes val label: Int) {
    NORMAL("normal", R.string.normal),
    SLOW("slow", R.string.relaxed),
    SLOWER("slower", R.string.slow);

    /** The multiplier sent upstream. The default rung is tunable from the
     *  server (`app_release.default_speech_speed`); the ends stay in the build. */
    fun multiplier(context: Context): Double = when (this) {
        NORMAL -> 1.0
        SLOW -> remoteDefault(context) ?: 0.9
        SLOWER -> 0.8
    }

    /**
     * Part of a cached line's key. EMPTY for the default rung, so every line
     * cached before the setting existed is still found and still plays —
     * produced audio is never orphaned. A rung picked on purpose, Normal
     * included, gets its own key.
     */
    fun cacheTag(context: Context): String =
        if (this == DEFAULT) "" else "s%.2f".format(java.util.Locale.US, multiplier(context))

    companion object {
        @Volatile private var appContext: Context? = null
        fun init(context: Context) { appContext = context.applicationContext }

        /** The multiplier to synthesize at now, for callers holding no context. */
        fun currentMultiplier(): Double? = appContext?.let { current(it).multiplier(it) }

        /** The current rung's cache tag, for callers holding no context. */
        fun currentCacheTag(): String = appContext?.let { current(it).cacheTag(it) } ?: ""

        const val KEY = "futurevoice.speechSpeed"
        private const val REMOTE_KEY = "futurevoice.speechSpeed.remoteDefault"
        val DEFAULT = SLOW

        private fun prefs(context: Context) =
            context.applicationContext.getSharedPreferences("futurevoice", Context.MODE_PRIVATE)

        fun current(context: Context): SpeechSpeed =
            prefs(context).getString(KEY, null)?.let { r -> entries.firstOrNull { it.raw == r } } ?: DEFAULT

        fun set(context: Context, speed: SpeechSpeed) =
            prefs(context).edit().putString(KEY, speed.raw).apply()

        /** Whether the learner has ever picked a rung (analytics). */
        fun picked(context: Context): Boolean = prefs(context).contains(KEY)

        private fun sane(v: Double) = v in 0.7..1.2

        fun remoteDefault(context: Context): Double? =
            prefs(context).getFloat(REMOTE_KEY, Float.NaN).toDouble().takeIf { !it.isNaN() && sane(it) }

        /** Mirror the server's default rung. Out-of-range is DROPPED, not
         *  clamped — guessing which edge a typo meant is how a voice nobody
         *  recognises ships. Null means the app's own default. */
        fun storeRemoteDefault(context: Context, value: Double?) {
            val e = prefs(context).edit()
            if (value == null || !sane(value)) e.remove(REMOTE_KEY) else e.putFloat(REMOTE_KEY, value.toFloat())
            e.apply()
        }
    }
}
