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
class PcmStreamPlayer(val sampleRate: Int = 22_050) {

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

    /** The DAC has started on this line's audio — sound is coming out, not
     *  merely queued. `write` returns as soon as the ring buffer takes the
     *  bytes, a few hundred ms before anything is audible. */
    val hasStartedSounding: Boolean
        get() = runCatching { (track?.playbackHeadPosition ?: 0) > 0 }.getOrDefault(false)

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
        carry = null
        track?.setVolume(volume)
        track?.play()
    }

    /** Blocking write — call from an IO context; back-pressure is the point. */
    suspend fun write(chunk: ByteArray) = withContext(Dispatchers.IO) { writeNow(chunk) }

    /** A byte left over from a chunk of odd length — the first half of a
     *  sample whose second half is the next chunk's first byte. */
    private var carry: Byte? = null

    /**
     * Blocking write on the CALLER's thread. The realtime client calls this
     * from its single audio thread, where ORDER is the point (2026-10-13):
     * through [write], each frame hopped to the IO pool, which freed the
     * audio thread to start the next frame's write before this one was done,
     * so frames reached the track out of order — the voice choppy and
     * "overlapping", worst on Cartesia, whose frames are small and many.
     * A chunk's odd byte is carried to the next one: AudioTrack refuses a
     * 16-bit write of odd length, which dropped the whole chunk.
     */
    fun writeNow(chunk: ByteArray) = synchronized(this) {
        val t = track ?: return@synchronized
        var data = chunk
        carry?.let { data = byteArrayOf(it) + chunk; carry = null }
        if (data.size % 2 == 1) { carry = data[data.size - 1]; data = data.copyOf(data.size - 1) }
        var offset = 0
        while (offset < data.size) {
            val written = t.write(data, offset, data.size - offset)
            if (written <= 0) break
            offset += written
        }
        writtenFrames += data.size / 2
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

    fun stop() = synchronized(this) {
        track?.let {
            runCatching { it.pause() }
            runCatching { it.flush() }
            runCatching { it.stop() }
            runCatching { it.release() }
        }
        track = null
        writtenFrames = 0
        carry = null
    }
}
