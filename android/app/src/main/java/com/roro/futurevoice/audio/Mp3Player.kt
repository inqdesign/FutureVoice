package com.roro.futurevoice.audio

import android.media.AudioAttributes
import android.media.MediaPlayer
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import java.io.File
import kotlin.coroutines.resume

/**
 * Buffered playback path — used when the Edge Function returns a whole MP3
 * (older deploy that ignored `stream`), and for cached lines.
 */
class Mp3Player(private val cacheDir: File) {

    /**
     * Playback gain, 0…1. Unity everywhere EXCEPT the live call, which is the
     * one surface the learner can turn down (`AudioPrefs.talkVoiceVolume`) —
     * on Bluetooth a call plays through the earphone's CALL chain, which the
     * system's headphone-safety cap does not limit, so it can tower over
     * every other sound the app makes. Every other surface plays at unity, as
     * on iOS: a global gain would quietly turn down the shadow reference and
     * the scene audio too, which are not the thing that was too loud.
     */
    @Volatile var volume: Float = 1f

    private var player: MediaPlayer? = null

    /** Playback head, ms — what karaoke follows. 0 when nothing is playing. */
    val positionMs: Int
        get() = player?.let { runCatching { it.currentPosition }.getOrDefault(0) } ?: 0

    /** Total length of what is playing, ms. 0 until prepared. */
    val durationMs: Int
        get() = player?.let { runCatching { it.duration }.getOrDefault(0) } ?: 0

    /** Audible right now — one of the meter's "this second is a call" witnesses. */
    val isPlaying: Boolean
        get() = player?.let { runCatching { it.isPlaying }.getOrDefault(false) } ?: false

    suspend fun play(mp3: ByteArray) {
        val file = withContext(Dispatchers.IO) {
            File.createTempFile("tts-", ".mp3", cacheDir).apply { writeBytes(mp3) }
        }
        try {
            playFile(file)
        } finally {
            withContext(Dispatchers.IO) { file.delete() }
        }
    }

    private suspend fun playFile(file: File) = suspendCancellableCoroutine { cont ->
        stop()
        val mp = MediaPlayer().apply {
            setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build()
            )
            setDataSource(file.absolutePath)
            setOnCompletionListener {
                if (cont.isActive) cont.resume(Unit)
            }
            setOnErrorListener { _, _, _ ->
                if (cont.isActive) cont.resume(Unit)
                true
            }
            setVolume(volume, volume)
            prepare()
            start()
        }
        player = mp
        cont.invokeOnCancellation { stop() }
    }

    fun stop() {
        player?.let {
            runCatching { it.stop() }
            runCatching { it.release() }
        }
        player = null
    }
}
