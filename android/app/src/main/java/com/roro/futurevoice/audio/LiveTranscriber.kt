package com.roro.futurevoice.audio

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.util.Log

/**
 * Continuous live STT for the call loop.
 *
 * Android's `SpeechRecognizer` is one-shot — it endpoints on its own and stops.
 * We don't want its endpointing (ours is in [TurnTaking], driven by real audio
 * energy), so this rotates segments the way iOS does: when a segment finalizes,
 * its text is committed to `chunks` and a new segment starts immediately. The
 * running transcript is committed chunks + the live partial.
 *
 * MUST be constructed and driven from the main thread — `SpeechRecognizer`
 * requires the main looper.
 */
class LiveTranscriber(private val context: Context) {

    private var recognizer: SpeechRecognizer? = null
    private val chunks = mutableListOf<String>()

    @Volatile
    private var partial: String = ""

    @Volatile
    var isRunning: Boolean = false
        private set

    private val fluency = FluencyMeter()
    private var lastRmsAtMs: Long = 0L
    private var onTranscriptChanged: ((String) -> Unit)? = null
    private var locale: String = "en-US"

    /** 0…1 mic level for the waveform UI. */
    @Volatile
    var level: Float = 0f
        private set

    val transcript: String
        get() = (chunks + partial).filter { it.isNotBlank() }.joinToString(" ").trim()

    /**
     * Wall-clock ms when the mic last heard VOICED audio — the endpointing
     * signal. Deliberately NOT "how long since the STT partial last changed":
     * that lags real speech by an unpredictable amount.
     */
    val lastVoicedAtMs: Long? get() = fluency.lastVoicedAt()

    /** Ambient noise estimate the endpointer is working against (telemetry). */
    val ambientNoiseLevel: Float get() = fluency.noiseFloorLevel()

    fun fluencyStats(): FluencyStats = fluency.snapshot()

    fun start(languageCode: String, onTranscript: (String) -> Unit) {
        if (isRunning) return
        if (!SpeechRecognizer.isRecognitionAvailable(context)) {
            throw IllegalStateException("Speech recognition unavailable on this device")
        }
        locale = languageCode
        onTranscriptChanged = onTranscript
        chunks.clear()
        partial = ""
        fluency.reset()
        lastRmsAtMs = System.currentTimeMillis()
        isRunning = true
        beginSegment()
    }

    fun stop(): String {
        isRunning = false
        recognizer?.let {
            runCatching { it.stopListening() }
            runCatching { it.destroy() }
        }
        recognizer = null
        val out = transcript
        onTranscriptChanged = null
        return out
    }

    private fun beginSegment() {
        if (!isRunning) return
        recognizer?.let { runCatching { it.destroy() } }
        val rec = SpeechRecognizer.createSpeechRecognizer(context)
        rec.setRecognitionListener(listener)
        recognizer = rec
        rec.startListening(segmentIntent())
    }

    private fun segmentIntent(): Intent =
        Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(
                RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                RecognizerIntent.LANGUAGE_MODEL_FREE_FORM,
            )
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, locale)
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
            // Push the platform's own endpointing out of the way — turn-taking
            // is ours, measured from mic energy against the three-tier wait.
            // (Many vendors ignore these; the rotation below covers that.)
            putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS, 10_000L)
            putExtra(
                RecognizerIntent.EXTRA_SPEECH_INPUT_POSSIBLY_COMPLETE_SILENCE_LENGTH_MILLIS,
                10_000L,
            )
            putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_MINIMUM_LENGTH_MILLIS, 1_000L)
        }

    /** Commit whatever this segment produced and immediately open the next one. */
    private fun rotate(finalText: String?) {
        val committed = finalText?.takeIf { it.isNotBlank() } ?: partial.takeIf { it.isNotBlank() }
        if (committed != null) chunks.add(committed.trim())
        partial = ""
        if (isRunning) {
            beginSegment()
            onTranscriptChanged?.invoke(transcript)
        }
    }

    private val listener = object : RecognitionListener {
        override fun onReadyForSpeech(params: Bundle?) {}
        override fun onBeginningOfSpeech() {}
        override fun onEndOfSpeech() {}
        override fun onBufferReceived(buffer: ByteArray?) {}
        override fun onEvent(eventType: Int, params: Bundle?) {}

        override fun onRmsChanged(rmsdB: Float) {
            val now = System.currentTimeMillis()
            val elapsed = ((now - lastRmsAtMs).coerceIn(0, 500)) / 1000.0
            lastRmsAtMs = now
            val normalized = FluencyMeter.levelFromRmsDb(rmsdB)
            level = normalized
            fluency.feed(normalized, elapsed, now)
        }

        override fun onPartialResults(partialResults: Bundle?) {
            val text = partialResults
                ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                ?.firstOrNull()
                .orEmpty()
            if (text.isNotBlank() && text != partial) {
                partial = text
                onTranscriptChanged?.invoke(transcript)
            }
        }

        override fun onResults(results: Bundle?) {
            val text = results
                ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                ?.firstOrNull()
            rotate(text)
        }

        override fun onError(error: Int) {
            when (error) {
                // Both are "the segment ended without new speech" — rotate and
                // keep listening. Anything else is worth a log but not a stop:
                // dropping the mic mid-call is worse than a lost segment.
                SpeechRecognizer.ERROR_NO_MATCH,
                SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> rotate(null)

                SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> rotate(null)

                else -> {
                    Log.w(TAG, "SpeechRecognizer error $error — restarting segment")
                    rotate(null)
                }
            }
        }
    }

    private companion object {
        const val TAG = "LiveTranscriber"
    }
}
