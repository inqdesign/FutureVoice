package com.roro.futurevoice.audio

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import android.media.MediaPlayer
import android.media.PlaybackParams
import android.os.Handler
import android.os.Looper
import com.roro.futurevoice.core.Analytics
import java.io.File

/**
 * The shadow target line's player — iOS's `AudioPlayer` as the trimmer
 * drives it: a SEGMENT of the file (the selected phrase, or the whole line),
 * optionally looped, at a chosen speed, with a playhead the karaoke follows.
 * Speed is time-stretch (`PlaybackParams`, pitch held at 1), so a slowed
 * line is still the learner's voice.
 */
class TargetPlayer {
    private var player: MediaPlayer? = null
    private var file: File? = null
    private val main = Handler(Looper.getMainLooper())
    private var segmentEnd: Int? = null
    private var segmentStart = 0
    var loop = false
    var rate = 1f
        set(value) {
            field = value
            player?.takeIf { it.isPlaying }?.let { p ->
                runCatching { p.playbackParams = PlaybackParams().setSpeed(value).setPitch(1f) }
            }
        }

    val isLoaded: Boolean get() = player != null
    val isPlaying: Boolean get() = runCatching { player?.isPlaying == true }.getOrDefault(false)
    val positionMs: Int get() = runCatching { player?.currentPosition ?: 0 }.getOrDefault(0)
    val durationMs: Int get() = runCatching { player?.duration ?: 0 }.getOrDefault(0)

    fun load(f: File) {
        if (file == f && player != null) return
        release()
        file = f
        player = runCatching {
            MediaPlayer().apply {
                setAudioAttributes(AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build())
                setDataSource(f.absolutePath)
                prepare()
                setOnCompletionListener { onEnd() }
            }
        }.getOrNull()
    }

    /** Play [fromMs]…[toMs] (null = to the end of the file). */
    fun playSegment(fromMs: Int, toMs: Int?, loop: Boolean = this.loop) {
        val p = player ?: return
        Analytics.capture("audio_played", mapOf("source" to "shadow"))
        this.loop = loop
        segmentStart = fromMs
        segmentEnd = toMs
        runCatching {
            p.seekTo(fromMs.toLong(), MediaPlayer.SEEK_CLOSEST)
            p.playbackParams = PlaybackParams().setSpeed(rate).setPitch(1f)
            p.start()
        }
        watch()
    }

    /** Move a live segment's bounds (the trimmer handle moved mid-loop). */
    fun updateSegment(fromMs: Int, toMs: Int?) {
        segmentStart = fromMs; segmentEnd = toMs
    }

    fun seek(ms: Int) { runCatching { player?.seekTo(ms.toLong(), MediaPlayer.SEEK_CLOSEST) } }

    fun pause() { runCatching { player?.pause() }; main.removeCallbacksAndMessages(null) }

    fun stop() {
        main.removeCallbacksAndMessages(null)
        runCatching { if (player?.isPlaying == true) player?.pause() }
        runCatching { player?.seekTo(0) }
    }

    fun release() {
        main.removeCallbacksAndMessages(null)
        player?.let { runCatching { it.release() } }
        player = null
        file = null
    }

    private fun watch() {
        main.removeCallbacksAndMessages(null)
        main.post(object : Runnable {
            override fun run() {
                val p = player ?: return
                if (!isPlaying) return
                val end = segmentEnd
                if (end != null && p.currentPosition >= end) {
                    if (loop) p.seekTo(segmentStart.toLong(), MediaPlayer.SEEK_CLOSEST)
                    else { p.pause(); return }
                }
                main.postDelayed(this, 20)
            }
        })
    }

    private fun onEnd() {
        if (loop) playSegment(segmentStart, segmentEnd, true)
    }
}

/**
 * "Both at once" — the model line and the learner's take mixed into ONE
 * stereo track, each skipped to its own first word, so they start together
 * on a single clock (iOS starts two players at one device time; one mixed
 * buffer is the same promise with nothing to drift). The learner stays at
 * full level slightly right, the model quieter slightly left, so the pair
 * separates on earphones without either becoming a background texture.
 */
object DuetPlayer {
    /** iOS `duetTargetVolume` / `duetPan`. */
    const val TARGET_VOLUME = 0.4f
    const val PAN = 0.35f

    private var track: AudioTrack? = null

    fun stop() {
        track?.let { runCatching { it.stop() }; runCatching { it.release() } }
        track = null
    }

    val isPlaying: Boolean get() = track?.playState == AudioTrack.PLAYSTATE_PLAYING

    /** Mix and play; false when either side is empty. */
    fun play(target: WavPcm, targetLeadMs: Int, take: WavPcm, takeLeadMs: Int): Boolean {
        stop()
        val rate = target.sampleRate
        val t = target.samples.drop(target.sampleRate.toLong(), targetLeadMs)
        val l = AudioDecode.resample(take, rate).samples.drop(rate.toLong(), takeLeadMs)
        if (t.isEmpty() || l.isEmpty()) return false
        val n = maxOf(t.size, l.size)
        val stereo = ShortArray(n * 2)
        // Pan: negative = left. Each side keeps full level on its own side.
        fun gains(vol: Float, pan: Float) = vol * minOf(1f, 1f - pan) to vol * minOf(1f, 1f + pan)
        val (tl, tr) = gains(TARGET_VOLUME, -PAN)
        val (ll, lr) = gains(1f, PAN)
        for (i in 0 until n) {
            val a = if (i < t.size) t[i].toFloat() else 0f
            val b = if (i < l.size) l[i].toFloat() else 0f
            stereo[2 * i] = (a * tl + b * ll).toInt().coerceIn(-32768, 32767).toShort()
            stereo[2 * i + 1] = (a * tr + b * lr).toInt().coerceIn(-32768, 32767).toShort()
        }
        val tr2 = runCatching {
            AudioTrack.Builder()
                .setAudioAttributes(AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build())
                .setAudioFormat(AudioFormat.Builder()
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                    .setSampleRate(rate)
                    .setChannelMask(AudioFormat.CHANNEL_OUT_STEREO).build())
                .setTransferMode(AudioTrack.MODE_STATIC)
                .setBufferSizeInBytes(stereo.size * 2)
                .build()
        }.getOrNull() ?: return false
        tr2.write(stereo, 0, stereo.size)
        tr2.play()
        track = tr2
        Analytics.capture("audio_played", mapOf("source" to "shadow_duet"))
        return true
    }

    private fun ShortArray.drop(rate: Long, ms: Int): ShortArray {
        val from = (rate * ms / 1000).toInt().coerceIn(0, size)
        return copyOfRange(from, size)
    }
}
