package com.roro.futurevoice.audio

import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.util.Log
import java.io.IOException
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.TimeUnit
import kotlin.concurrent.thread
import kotlin.math.log10
import kotlin.math.max
import kotlin.math.sqrt

/**
 * Continuous live STT — the running transcript of what is being said, with
 * the mic level and "last voiced" moment beside it.
 *
 * TWO WAYS TO HEAR, and the first is the one that matters (2026-10-14):
 *
 *  - **Fed (API 33+).** The recognizer never opens the microphone. Its audio
 *    comes through a pipe (`EXTRA_AUDIO_SOURCE`), in ONE segmented session
 *    (`EXTRA_SEGMENTED_SESSION`) that runs until the pipe closes, so it never
 *    endpoints and is never restarted. The PCM is either the caller's own
 *    recording ([start] with `fed = true`, then [feed] from its capture loop —
 *    the Speech take and shadowing, where the recording is what gets scored)
 *    or a mic this class opens itself (dictation).
 *  - **Rotation (API < 33 only).** The recognizer opens the mic, endpoints on
 *    its own, and a new session is started on every result or error.
 *
 * Why fed: reported on a Galaxy A34 — "a ding-dong in the middle of a 3 s
 * take, and the script doesn't follow me". Logcat showed both are one bug.
 * Google's recognition service (the default recognizer on that phone and on
 * the Pixel emulator) plays an earcon whenever it OPENS the mic
 * (`raw/open`) and whenever a session fails (`raw/failure`, `raw/no_input`).
 * And the take's own recorder, opened after the recognizer, was the later
 * mic user, so Android's concurrent-capture policy SILENCED the recognizer
 * (`AF::RecordTrack: setSilenced … (silenced)`): it heard nothing, gave up
 * after 5 s with NO_SPEECH_DETECTED (failure beep), the rotation reopened it
 * (open beep — the ding-dong), and not one partial ever reached the
 * prompter, so follow-the-voice had nothing to follow. iOS has neither
 * problem: one audio engine taps the mic once and hands the same buffers to
 * the recorder and to SFSpeechRecognizer, which makes no sound. Feeding the
 * recognizer is the Android shape of exactly that: one mic user, no
 * mic-open earcon, no session that ends in a timeout.
 *
 * MUST be constructed and driven from the main thread — `SpeechRecognizer`
 * requires the main looper. [feed] may be called from any thread.
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
    private val main = Handler(Looper.getMainLooper())

    // Fed path.
    private var piped = false
    private var feedFromCaller = false
    /** Bumped per pipe session, so a late callback from a replaced session
     *  is never read as the current one's. */
    private var generation = 0
    @Volatile private var queue: ArrayBlockingQueue<ByteArray>? = null
    private var writer: Thread? = null
    private var micThread: Thread? = null
    @Volatile private var micRecord: AudioRecord? = null
    private var sessionRestarts = 0
    private var readEnd: ParcelFileDescriptor? = null

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

    /**
     * True when the recognizer takes its audio from [feed] — the caller then
     * must feed it, and must NOT expect the recognizer to open the mic. False
     * on an Android that can't (< 13): the recognizer opens the mic itself,
     * exactly as before, and [feed] is a no-op.
     */
    val acceptsFeed: Boolean get() = isRunning && piped && feedFromCaller

    /**
     * @param fed the caller records the audio itself and hands every buffer to
     *   [feed] (16 kHz mono 16-bit). Otherwise this opens the mic on its own.
     */
    fun start(languageCode: String, fed: Boolean = false, onTranscript: (String) -> Unit) {
        if (isRunning) return
        if (!SpeechRecognizer.isRecognitionAvailable(context)) {
            throw IllegalStateException("Speech recognition unavailable on this device")
        }
        locale = languageCode
        onTranscriptChanged = onTranscript
        chunks.clear()
        partial = ""
        fluency.reset()
        level = 0f
        lastRmsAtMs = System.currentTimeMillis()
        sessionRestarts = 0
        isRunning = true
        piped = Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU
        feedFromCaller = fed
        if (piped) {
            if (!fed && !startOwnMic()) {
                // The mic couldn't be opened here — let the recognizer try.
                piped = false
            }
        }
        if (piped) beginPipeSession() else beginSegment()
    }

    fun stop(): String {
        isRunning = false
        generation++
        stopOwnMic()
        if (piped) {
            // End of input, not a cancel: the pipe closes, the recognizer
            // reads EOF and ends the session on its own. A cancelled session
            // is what Google's recognizer answers with an earcon
            // (`raw/no_input`), so the recognizer is only released once the
            // session has had time to end. Callbacks from it are already
            // ignored (the generation moved on).
            queue?.let { q -> if (!q.offer(EOF)) { q.poll(); q.offer(EOF) } }
            queue = null
            writer = null
            val rec = recognizer
            val read = readEnd
            recognizer = null
            readEnd = null
            main.postDelayed({
                rec?.let { runCatching { it.destroy() } }
                read?.let { runCatching { it.close() } }
            }, RELEASE_AFTER_EOF_MS)
        } else {
            recognizer?.let {
                runCatching { it.stopListening() }
                runCatching { it.destroy() }
            }
            recognizer = null
        }
        val out = transcript
        onTranscriptChanged = null
        return out
    }

    /** One buffer of the caller's recording (16 kHz mono PCM16). Never
     *  blocks: a recognizer that falls behind loses audio, the take never. */
    fun feed(samples: ShortArray, count: Int) {
        if (!feedFromCaller) return
        push(samples, count)
    }

    private fun push(samples: ShortArray, count: Int) {
        val q = queue ?: return
        if (count <= 0) return
        val bytes = ByteArray(count * 2)
        for (i in 0 until count) {
            val v = samples[i].toInt()
            bytes[2 * i] = (v and 0xff).toByte()
            bytes[2 * i + 1] = ((v shr 8) and 0xff).toByte()
        }
        if (!q.offer(bytes)) {
            q.poll(); q.offer(bytes)   // keep the newest
        }
        // Level from the PCM itself — iOS's dBFS curve, the same one
        // `SpeechCapture` and `WavRecorder` draw.
        var sum = 0.0
        for (i in 0 until count) { val v = samples[i] / 32768.0; sum += v * v }
        val db = 20 * log10(max(sqrt(sum / count), 1e-7))
        val l = (((db + 50) / 50).toFloat()).coerceIn(0f, 1f)
        level = l
        fluency.feed(l, count / SAMPLE_RATE.toDouble(), System.currentTimeMillis())
    }

    // MARK: - Fed path

    @SuppressLint("MissingPermission")   // every caller asks before starting
    private fun startOwnMic(): Boolean {
        val rec = runCatching {
            val minBuf = AudioRecord.getMinBufferSize(SAMPLE_RATE,
                AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
            AudioRecord(MediaRecorder.AudioSource.VOICE_RECOGNITION, SAMPLE_RATE,
                AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT, maxOf(minBuf, 8192))
        }.getOrNull() ?: return false
        if (rec.state != AudioRecord.STATE_INITIALIZED) { rec.release(); return false }
        micRecord = rec
        micThread = thread(name = "LiveTranscriberMic") {
            val buf = ShortArray(1600)   // 100 ms
            runCatching { rec.startRecording() }
            while (micRecord === rec) {
                val n = rec.read(buf, 0, buf.size)
                if (n > 0) push(buf, n) else if (n < 0) break
            }
            runCatching { rec.stop() }
            rec.release()
        }
        return true
    }

    private fun stopOwnMic() {
        val t = micThread
        micRecord = null
        micThread = null
        t?.join(500)
        level = 0f
    }

    private fun beginPipeSession() {
        if (!isRunning) return
        val gen = ++generation
        recognizer?.let { runCatching { it.destroy() } }
        recognizer = null
        readEnd?.let { runCatching { it.close() } }
        readEnd = null
        // The previous session's writer ends on its own pipe.
        queue?.offer(EOF)
        val (read, write) = runCatching { ParcelFileDescriptor.createPipe() }.getOrNull()
            ?: run { piped = false; stopOwnMic(); beginSegment(); return }
        val q = ArrayBlockingQueue<ByteArray>(QUEUE_BUFFERS)
        queue = q
        writer = thread(name = "LiveTranscriberPipe") {
            try {
                ParcelFileDescriptor.AutoCloseOutputStream(write).use { out ->
                    while (true) {
                        // A replaced or stopped session's writer ends here.
                        val b = q.poll(500, TimeUnit.MILLISECONDS)
                            ?: if (queue !== q) break else continue
                        if (b === EOF) break
                        out.write(b)
                    }
                }
            } catch (_: IOException) {
                // The recognizer closed its end (session over) — nothing to do;
                // a session the caller still wants is restarted from onError /
                // onEndOfSegmentedSession.
            } catch (_: InterruptedException) {
            }
        }
        val rec = SpeechRecognizer.createSpeechRecognizer(context)
        rec.setRecognitionListener(PipeListener(gen))
        recognizer = rec
        val intent = baseIntent().apply {
            putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE, read)
            putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_CHANNEL_COUNT, 1)
            putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_ENCODING, AudioFormat.ENCODING_PCM_16BIT)
            putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_SAMPLING_RATE, SAMPLE_RATE)
            // One session for the whole take: segments come back at pauses,
            // and the session ends only when the pipe does.
            putExtra(RecognizerIntent.EXTRA_SEGMENTED_SESSION, RecognizerIntent.EXTRA_AUDIO_SOURCE)
        }
        runCatching { rec.startListening(intent) }
            .onFailure { Log.w(TAG, "pipe session refused: $it") }
        // Held until this session is replaced or stopped: startListening
        // parcels the descriptor asynchronously, once the service is bound,
        // and a descriptor closed before then fails the session (measured).
        readEnd = read
    }

    /** A pipe session ended while the caller still listens — open another.
     *  Silent (no mic is opened), but bounded so a recognizer that refuses
     *  every session can't spin. */
    private fun restartPipe(why: String) {
        if (!isRunning || !piped) return
        sessionRestarts++
        Log.w(TAG, "pipe session ended ($why) — reopening #$sessionRestarts")
        if (sessionRestarts > MAX_PIPE_RESTARTS) {
            Log.w(TAG, "giving up on the recognizer for this take")
            return
        }
        main.postDelayed({ if (isRunning && piped) beginPipeSession() }, 150)
    }

    private fun commit(text: String?) {
        val committed = text?.takeIf { it.isNotBlank() } ?: partial.takeIf { it.isNotBlank() }
        if (committed != null) chunks.add(committed.trim())
        partial = ""
        onTranscriptChanged?.invoke(transcript)
    }

    private inner class PipeListener(val gen: Int) : RecognitionListener {
        private val current get() = gen == generation && isRunning
        override fun onReadyForSpeech(params: Bundle?) {}
        override fun onBeginningOfSpeech() {}
        override fun onEndOfSpeech() {}
        override fun onBufferReceived(buffer: ByteArray?) {}
        override fun onEvent(eventType: Int, params: Bundle?) {}
        // The level is measured on the PCM in [push].
        override fun onRmsChanged(rmsdB: Float) {}

        override fun onPartialResults(partialResults: Bundle?) {
            if (!current) return
            val text = partialResults
                ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                ?.firstOrNull()
                .orEmpty()
            if (text.isNotBlank() && text != partial) {
                partial = text
                onTranscriptChanged?.invoke(transcript)
            }
        }

        override fun onSegmentResults(segmentResults: Bundle) {
            if (!current) return
            commit(segmentResults.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull())
        }

        override fun onResults(results: Bundle?) {
            if (!current) return
            commit(results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull())
            restartPipe("results")
        }

        override fun onEndOfSegmentedSession() {
            if (!current) return
            if (partial.isNotBlank()) commit(null)
            restartPipe("end of session")
        }

        override fun onError(error: Int) {
            if (!current) return
            if (partial.isNotBlank()) commit(null)
            restartPipe("error $error")
        }
    }

    // MARK: - Rotation path (Android < 13)

    private fun beginSegment() {
        if (!isRunning) return
        recognizer?.let { runCatching { it.destroy() } }
        val rec = SpeechRecognizer.createSpeechRecognizer(context)
        rec.setRecognitionListener(listener)
        recognizer = rec
        rec.startListening(segmentIntent())
    }

    private fun baseIntent(): Intent =
        Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(
                RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                RecognizerIntent.LANGUAGE_MODEL_FREE_FORM,
            )
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, locale)
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
        }

    private fun segmentIntent(): Intent =
        baseIntent().apply {
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
        const val SAMPLE_RATE = 16_000
        /** ~20 s of 100 ms buffers; past that the oldest audio is dropped. */
        const val QUEUE_BUFFERS = 200
        const val MAX_PIPE_RESTARTS = 20
        /** How long a stopped session gets to end on EOF before release. */
        const val RELEASE_AFTER_EOF_MS = 3_000L
        val EOF = ByteArray(0)
    }
}
