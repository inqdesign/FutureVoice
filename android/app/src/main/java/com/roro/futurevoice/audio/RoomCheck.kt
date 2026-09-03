package com.roro.futurevoice.audio

import android.annotation.SuppressLint
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import kotlin.concurrent.thread
import kotlin.math.abs
import kotlin.math.log10
import kotlin.math.max
import kotlin.math.sqrt

/**
 * Listens to the ROOM — never writes a file. The quiet-spot step needs two
 * facts before the learner records the one take that becomes their voice, and
 * a clone made in the wrong room cannot be undone without spending another
 * provider slot.
 *
 *   ambientDbfs — how LOUD the room is: a ~0.6 s EMA of 10 ms RMS windows,
 *                 on an unprocessed capture chain so nothing is being gained
 *                 up underneath the reading.
 *   echoTailMs  — how LIVE the room is: after a clap, how long the energy
 *                 takes to fall 30 dB from its peak. Quiet alone is not
 *                 enough — an open room can be silent and still smear the
 *                 clone with its own reflections.
 *
 * The capture source is UNPROCESSED (falling back to VOICE_RECOGNITION, then
 * MIC): with AGC or noise suppression in the chain the phone quietly cleans
 * up the room and the gate then passes a room the CLONE will not forgive.
 */
class RoomCheck {

    @Volatile var isMonitoring: Boolean = false; private set

    /** dBFS, ~0.6 s EMA. Starts at silence so the first frame can only rise. */
    @Volatile var ambientDbfs: Float = -90f; private set

    /** Milliseconds for the last clap to decay 30 dB; null until one is heard. */
    @Volatile var echoTailMs: Double? = null; private set

    /** 0…1, for the surface — the room visibly stirs the orb. */
    @Volatile var level: Float = 0f; private set

    private var record: AudioRecord? = null
    private var worker: Thread? = null

    @SuppressLint("MissingPermission")   // RECORD_AUDIO is granted before this step
    fun start() {
        if (isMonitoring) return
        val minBuf = AudioRecord.getMinBufferSize(
            SAMPLE_RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
        val rec = sources.firstNotNullOfOrNull { src ->
            runCatching {
                AudioRecord(src, SAMPLE_RATE, AudioFormat.CHANNEL_IN_MONO,
                    AudioFormat.ENCODING_PCM_16BIT, max(minBuf, 8192))
            }.getOrNull()?.takeIf { it.state == AudioRecord.STATE_INITIALIZED }
        } ?: return
        record = rec
        isMonitoring = true
        ambientDbfs = -90f
        echoTailMs = null
        worker = thread(name = "RoomCheck") {
            val window = ShortArray(WINDOW)
            // The decay hunt, once a clap has been seen.
            var peakDb = 0f
            var sinceClapMs = 0.0
            var hunting = false
            rec.startRecording()
            while (isMonitoring) {
                val n = rec.read(window, 0, window.size)
                if (n <= 0) continue
                val db = dbfs(window, n)
                val ms = n * 1000.0 / SAMPLE_RATE

                // A clap is a sudden jump well above the room — loud in
                // absolute terms AND far above what the room has been doing,
                // so a door closing in a noisy room does not count.
                if (!hunting && db > CLAP_DBFS && db > ambientDbfs + CLAP_OVER_ROOM) {
                    hunting = true; peakDb = db; sinceClapMs = 0.0
                } else if (hunting) {
                    sinceClapMs += ms
                    if (db > peakDb) { peakDb = db; sinceClapMs = 0.0 }
                    if (db <= peakDb - DECAY_DB) {
                        echoTailMs = sinceClapMs
                        hunting = false
                    } else if (sinceClapMs > HUNT_TIMEOUT_MS) {
                        // Never decayed — that IS a live room, not a failed
                        // measurement, so it is reported rather than dropped.
                        echoTailMs = HUNT_TIMEOUT_MS
                        hunting = false
                    }
                    // A clap must not drag the ambient reading up with it.
                }

                if (!hunting) {
                    val a = EMA_PER_WINDOW
                    ambientDbfs = ambientDbfs * (1 - a) + db * a
                }
                level = ((db + 60f) / 60f).coerceIn(0f, 1f)
            }
            runCatching { rec.stop() }
            runCatching { rec.release() }
        }
    }

    fun stop() {
        isMonitoring = false
        worker?.join(500)
        worker = null
        record = null
        level = 0f
    }

    private fun dbfs(buf: ShortArray, n: Int): Float {
        var sum = 0.0
        for (i in 0 until n) { val v = buf[i] / 32768.0; sum += v * v }
        val rms = sqrt(sum / max(n, 1))
        return if (rms <= 1e-7) -90f else (20.0 * log10(rms)).toFloat().coerceAtLeast(-90f)
    }

    private val sources = listOf(
        MediaRecorder.AudioSource.UNPROCESSED,
        MediaRecorder.AudioSource.VOICE_RECOGNITION,
        MediaRecorder.AudioSource.MIC,
    )

    companion object {
        private const val SAMPLE_RATE = 16_000
        /** 10 ms windows, as iOS reads them. */
        private const val WINDOW = SAMPLE_RATE / 100
        /** ~0.6 s EMA over 10 ms windows. */
        private const val EMA_PER_WINDOW = 0.016f
        private const val CLAP_DBFS = -20f
        private const val CLAP_OVER_ROOM = 18f
        /** RT30 — the standard decay, and far enough to survive a noisy floor. */
        private const val DECAY_DB = 30f
        private const val HUNT_TIMEOUT_MS = 1500.0
    }
}

/**
 * The two gates the quiet-spot step shows, and the ONE place their thresholds
 * live. Both are derived from what the CLONE needs, not from a desk reading.
 */
object RoomGates {

    enum class State { GOOD, NEAR, BAD, UNKNOWN }

    /**
     * How loud the room is.
     *
     * Read at conversational distance a voice lands around −25 dBFS, and a
     * usable clone wants the room sitting ~30 dB under that. So −55 is
     * "quiet", and −45 (20 dB SNR) is the last tolerable rung.
     *
     * iOS ran −45/−35 until it found the bug: a room with a TV playing
     * measures about −47 dBFS, comfortably under the old −45 bar, so the gate
     * called a living room with the TV on "quiet" and sent the learner off to
     * record a take the noise had already ruined. Both rungs moved down 10 dB.
     */
    fun noise(dbfs: Float): State = when {
        dbfs > -45f -> State.BAD
        dbfs > -55f -> State.NEAR
        else -> State.GOOD
    }

    /**
     * How live the room is. Tails at or under this read as a dry, soft room;
     * longer means the space smears the voice back onto itself.
     */
    const val DRY_TAIL_MS = 220.0

    fun echo(tailMs: Double?): State = when {
        tailMs == null -> State.UNKNOWN
        tailMs <= DRY_TAIL_MS -> State.GOOD
        else -> State.NEAR
    }

    fun bothPass(dbfs: Float, tailMs: Double?): Boolean =
        noise(dbfs) == State.GOOD && echo(tailMs) == State.GOOD
}
