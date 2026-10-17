package com.roro.futurevoice.audio

import java.io.File
import java.util.UUID
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

/**
 * Cleans the voice-clone recording on the phone before it is uploaded
 * (iOS `VoiceDenoiser`, 2026-10-15).
 *
 * The server used to do this with the previous provider's audio isolation;
 * Cartesia has no denoiser. The founder compared candidates by ear on
 * his own take and picked DeepFilterNet3 capped at 30 dB: the cap leaves a
 * little of the room in and keeps the texture of the voice, which is what the
 * clone is judged on.
 *
 * DeepFilterNet runs from `native/denoise` in the iOS repo — the same Rust
 * library iOS links, built for Android as `libfvdenoise.so`
 * (`native/denoise/build-android.sh`). Free, offline, ~1 s for a minute.
 *
 * The take ON DISK is never touched: the saved sample keeps the original, and
 * every re-clone cleans it again. Any failure — the library missing on this
 * ABI included — returns null and the caller uploads the take as it was.
 */
object VoiceDenoiser {
    /** How far the noise may be pushed down. Chosen by ear, see above. */
    const val ATTENUATION_LIMIT_DB = 30f

    /** The rate the model runs at (`fv_denoise_sample_rate`). */
    const val SAMPLE_RATE = 48_000

    /** Loaded once; a missing or unloadable library means "no cleaning",
     *  never a crash in the clone flow. */
    private val loaded: Boolean by lazy {
        try {
            System.loadLibrary("fvdenoise"); true
        } catch (t: Throwable) {
            android.util.Log.w("VoiceDenoiser", "fvdenoise unavailable: $t"); false
        }
    }

    /** 48 kHz mono float in, the same length out — or null on any failure. */
    @JvmStatic
    external fun nativeDenoise48k(input: FloatArray, attenLimDb: Float): FloatArray?

    /** A cleaned copy of the WAV at [file] (48 kHz mono 16-bit), or null. */
    fun cleaned(file: File): File? {
        if (!loaded) return null
        return try {
            val pcm = WavPcm.read(file) ?: return null
            if (pcm.samples.isEmpty()) return null
            val input = resample(FloatArray(pcm.samples.size) { pcm.samples[it] / 32768f },
                pcm.sampleRate, SAMPLE_RATE)
            val out = nativeDenoise48k(input, ATTENUATION_LIMIT_DB) ?: return null
            if (out.size != input.size) return null
            val shorts = ShortArray(out.size) {
                (out[it] * 32767f).toInt().coerceIn(-32768, 32767).toShort()
            }
            val dest = File(file.parentFile, "clone-clean-${UUID.randomUUID()}.wav")
            dest.writeBytes(WavPcm.wav(shorts, SAMPLE_RATE))
            dest
        } catch (t: Throwable) {
            null
        }
    }

    /**
     * Band-limited (Hann-windowed sinc) resample — the role
     * `AVAudioConverter` plays on iOS. Linear interpolation would leave the
     * images of a 16 kHz take above 8 kHz for the denoiser to read as noise.
     */
    fun resample(input: FloatArray, from: Int, to: Int): FloatArray {
        if (from == to || input.isEmpty() || from <= 0 || to <= 0) return input
        val ratio = to.toDouble() / from
        val n = (input.size * ratio).toLong().toInt()
        // Cutoff at the lower Nyquist, a little inside it.
        val cutoff = 0.95 * min(1.0, ratio)
        val halfTaps = 16
        val radius = halfTaps / cutoff
        val out = FloatArray(n)
        for (i in 0 until n) {
            val x = i / ratio
            val lo = max(0, floor(x - radius).toInt() + 1)
            val hi = min(input.size - 1, floor(x + radius).toInt())
            var acc = 0.0
            var norm = 0.0
            for (k in lo..hi) {
                val d = x - k
                val t = d * cutoff
                val sinc = if (t == 0.0) 1.0 else sin(PI * t) / (PI * t)
                val w = 0.5 * (1 + cos(PI * d / radius))
                val h = sinc * w
                acc += input[k] * h
                norm += h
            }
            out[i] = if (norm != 0.0) (acc / norm).toFloat() else 0f
        }
        return out
    }

    /**
     * The upload a clone is made from (iOS `AppState.regenerateVoiceClone`):
     * the take levelled, cleaned here, levelled again (removing noise lowers
     * the peak). A failed cleaning uploads the levelled take as it was. Reports
     * `voice_clone_denoise` like iOS. Returns the file to upload; [source] is
     * never modified.
     */
    fun prepareForClone(source: File): File {
        val levelled = SampleQuality.peakNormalized(source)
        val snr = SampleQuality.analyze(levelled)?.estimatedSnrDb
        val cleaned = cleaned(levelled)
        val upload = cleaned?.let { SampleQuality.peakNormalized(it) } ?: levelled
        // Intermediates nobody else reads; the caller deletes the upload.
        if (cleaned != null && upload != cleaned) cleaned.delete()
        if (cleaned != null && levelled != source) levelled.delete()
        com.roro.futurevoice.core.Analytics.capture("voice_clone_denoise", mapOf(
            "applied" to (cleaned != null),
            "on_device" to true,
            "snr_db" to (snr?.toInt() ?: -1),
        ))
        return upload
    }
}
