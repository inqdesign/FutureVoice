package com.roro.futurevoice.audio

import android.content.Context
import android.media.AudioAttributes
import android.media.SoundPool
import com.roro.futurevoice.R
import com.roro.futurevoice.data.WeeklyTestSettings

/**
 * The app's few UI sounds — today only the weekly test's answer cues (iOS
 * `SoundEffects`). The files are the same synthesized WAVs iOS ships
 * (`scripts/make-ui-sounds.py`, -12 dBFS): nothing sampled, nothing licensed.
 *
 * A `SoundPool` on the MEDIA usage, so a cue is heard wherever the fluent
 * self is (a sonification stream follows the ringer and is silent on half the
 * phones people own) — and the goals sheet's Sounds toggle is the one
 * control. Haptics stay with the view; a view fires both, one line each.
 */
object SoundEffects {
    enum class Cue(val res: Int) {
        TAP(R.raw.test_tap), RIGHT(R.raw.test_right), WRONG(R.raw.test_wrong), DONE(R.raw.test_done)
    }

    private var pool: SoundPool? = null
    private val ids = HashMap<Cue, Int>()
    private val loaded = HashSet<Int>()

    private fun pool(context: Context): SoundPool = pool ?: SoundPool.Builder()
        .setMaxStreams(2)
        .setAudioAttributes(AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_MEDIA)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build())
        .build().also { p ->
            p.setOnLoadCompleteListener { _, id, status -> if (status == 0) synchronized(loaded) { loaded += id } }
            pool = p
            // Load all four up front: a cue loaded on first use arrives late
            // or not at all, and the first answer is the one that matters.
            Cue.entries.forEach { cue -> ids[cue] = p.load(context.applicationContext, cue.res, 1) }
        }

    /** Warm the pool before the first answer. */
    fun prepare(context: Context) { pool(context) }

    fun play(context: Context, cue: Cue, enabled: Boolean = WeeklyTestSettings.soundsOn(context)) {
        if (!enabled) return
        val p = pool(context)
        val id = ids[cue] ?: return
        if (synchronized(loaded) { id !in loaded }) return
        p.play(id, 0.9f, 0.9f, 1, 0, 1f)
    }
}
