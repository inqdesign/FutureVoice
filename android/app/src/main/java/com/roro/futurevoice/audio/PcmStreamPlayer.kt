package com.roro.futurevoice.audio

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext

/**
 * Plays the streamed TTS as it arrives — the Android sibling of the iOS
 * scheduled-buffer player.
 *
 * Format is fixed by the Edge Function: 16-bit LE mono PCM at 22.05 kHz
 * (`X-Audio-Format: pcm_22050`). See `docs/contracts/behavior.md` §1.
 */
class PcmStreamPlayer(private val sampleRate: Int = 22_050) {

    private var track: AudioTrack? = null
    private var writtenFrames: Int = 0

    /**
     * Playback gain, 0…1 — the learner's own ceiling on the fluent self
     * (`AudioPrefs.talkVoiceVolume`). This is the call's MAIN path, so
     * setting it only on the mp3 fallback would leave the slider doing
     * nothing on almost every turn.
     */
    @Volatile var volume: Float = 1f
        set(value) { field = value.coerceIn(0f, 1f); track?.setVolume(field) }

    val isPlaying: Boolean get() = track?.playState == AudioTrack.PLAYSTATE_PLAYING

    fun start() {
        stop()
        val minBuffer = AudioTrack.getMinBufferSize(
            sampleRate,
            AudioFormat.CHANNEL_OUT_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
        )
        // A generous ring buffer: the network, not the DAC, is the jittery part.
        val bufferSize = maxOf(minBuffer, sampleRate) // ~0.5s of 16-bit mono
        track = AudioTrack.Builder()
            .setAudioAttributes(
                AudioAttributes.Builder()
                    // MEDIA, not VOICE_COMMUNICATION: the latter routes to the
                    // earpiece receiver on most devices. iOS respects headphones
                    // rather than force-routing, and MEDIA is the Android
                    // equivalent — speaker or connected headset, full volume.
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build()
            )
            .setAudioFormat(
                AudioFormat.Builder()
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                    .setSampleRate(sampleRate)
                    .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                    .build()
            )
            .setBufferSizeInBytes(bufferSize)
            .setTransferMode(AudioTrack.MODE_STREAM)
            .build()
        writtenFrames = 0
        track?.setVolume(volume)
        track?.play()
    }

    /** Blocking write — call from an IO context; back-pressure is the point. */
    suspend fun write(chunk: ByteArray) = withContext(Dispatchers.IO) {
        val t = track ?: return@withContext
        var offset = 0
        while (offset < chunk.size) {
            val written = t.write(chunk, offset, chunk.size - offset)
            if (written <= 0) break
            offset += written
        }
        writtenFrames += chunk.size / 2
    }

    /** Waits for the DAC to actually finish the audio already handed to it. */
    suspend fun drain() {
        val t = track ?: return
        while (t.playState == AudioTrack.PLAYSTATE_PLAYING &&
            t.playbackHeadPosition < writtenFrames
        ) {
            delay(30)
        }
    }

    fun stop() {
        track?.let {
            runCatching { it.pause() }
            runCatching { it.flush() }
            runCatching { it.stop() }
            runCatching { it.release() }
        }
        track = null
        writtenFrames = 0
    }
}
