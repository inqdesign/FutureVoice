package com.roro.futurevoice.talk

import android.util.Base64
import com.roro.futurevoice.data.AuthRepository
import com.roro.futurevoice.net.GeminiClient
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import kotlinx.serialization.Serializable
import java.io.File
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.abs
import kotlin.math.min

/**
 * The words a shadowing take is graded on — the ONE door every score walks
 * through (port of `ShadowTranscriber.swift`).
 *
 * A transcript is not context for a model here; it IS the grade. The diff,
 * the score and the coach all read it, so it comes from the AUDIO rather
 * than from a live recognizer: connected speech ("soak it all in") is
 * exactly what an on-device pass collapses, and the learner was being told
 * they had skipped three words they said perfectly well (iOS `3ffb602`).
 *
 * Android differs from iOS in ONE way: there is no second reader of the
 * WORDS. iOS falls back to Apple's file pass when the audio read fails;
 * Android's `SpeechRecognizer` can read a file since Android 13, but only as
 * a segmented session that returns no word times, so it would add a weaker
 * transcript and nothing else. A failed read is therefore reported as a
 * failure and nothing is scored, rather than being graded on a weaker
 * reading the learner cannot see. The TIMES iOS takes from Apple come from
 * [TakeAligner] here (plan 2.9).
 */
object ShadowTranscriber {

    /** What produced the words, for the telemetry row. */
    enum class Source { AUDIO_GROUNDED, FAILED }

    data class Read(val text: String, val source: Source, val ms: Long)

    /** A take is one short sentence; past this the file is not a take. */
    private const val MAX_BYTES = 3_000_000

    /** The whole read, including the upload. Past this the learner is just
     *  waiting — a healthy call lands in ~2 s. */
    private const val TIMEOUT_MS = 20_000L

    @Serializable
    private data class Payload(val transcript: String? = null)

    /**
     * Read the take. The audio is LEVELLED first (boost only): a quiet take
     * loses its consonants before any model sees it. The learner's own
     * playback keeps the original — the take is theirs, the levelling is for
     * the machine.
     */
    suspend fun read(wav: File, targetLanguage: String): Read = withContext(Dispatchers.IO) {
        val started = System.currentTimeMillis()
        fun elapsed() = System.currentTimeMillis() - started
        val bytes = runCatching { levelled(wav) }.getOrNull()
            ?: return@withContext Read("", Source.FAILED, elapsed())
        if (bytes.isEmpty() || bytes.size > MAX_BYTES) {
            return@withContext Read("", Source.FAILED, elapsed())
        }
        val text = runCatching {
            withTimeout(TIMEOUT_MS) {
                GeminiClient(AuthRepository()).sendJson(
                    system = ShadowTranscribePrompt.build(targetLanguage),
                    messages = listOf(GeminiClient.Message(
                        role = GeminiClient.Message.Role.USER,
                        content = "Transcribe the attached audio.",
                        inlineAudio = GeminiClient.InlineAudio(
                            mimeType = "audio/wav",
                            base64Data = Base64.encodeToString(bytes, Base64.NO_WRAP)))),
                    serializer = Payload.serializer(),
                    maxTokens = 1024,
                    purpose = "transcribe",
                    // Perception, not reasoning: thought tokens on a six-word
                    // line are wait time the learner sits through (iOS).
                    fastThinking = true,
                )
            }.transcript?.trim().orEmpty()
        }.getOrElse { e ->
            if (e is TimeoutCancellationException) "" else ""
        }
        if (text.isEmpty()) Read("", Source.FAILED, elapsed())
        else Read(text, Source.AUDIO_GROUNDED, elapsed())
    }

    /**
     * The same WAV with its peak brought up toward -3 dBFS. Boost ONLY: a
     * take that was loud enough is returned untouched, and nothing is ever
     * turned down, so this can never take detail away.
     */
    private fun levelled(wav: File): ByteArray {
        val raw = wav.readBytes()
        if (raw.size <= 44) return raw
        val samples = ByteBuffer.wrap(raw, 44, raw.size - 44).order(ByteOrder.LITTLE_ENDIAN)
        var peak = 0
        while (samples.remaining() >= 2) {
            val v = abs(samples.short.toInt())
            if (v > peak) peak = v
        }
        // Silence, or already at a good level — hand back what we have.
        val target = (32767 * 0.707).toInt()   // -3 dBFS
        if (peak == 0 || peak >= target) return raw
        // Capped at +30 dB, as on iOS (`peakNormalizedWAV`).
        val gain = min(target.toDouble() / peak, 31.62)
        val out = raw.copyOf()
        val buf = ByteBuffer.wrap(out, 44, out.size - 44).order(ByteOrder.LITTLE_ENDIAN)
        var i = 44
        while (i + 1 < out.size) {
            val v = buf.getShort(i)
            val scaled = (v * gain).toInt().coerceIn(-32768, 32767)
            buf.putShort(i, scaled.toShort())
            i += 2
        }
        return out
    }

    /** Seconds of audio in a 16-bit mono WAV, for the pace figure. */
    fun durationMs(wav: File, sampleRate: Int): Int = runCatching {
        RandomAccessFile(wav, "r").use { ((it.length() - 44) / 2 * 1000 / sampleRate).toInt() }
    }.getOrDefault(0)
}
