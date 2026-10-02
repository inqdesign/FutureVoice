package com.roro.futurevoice.capture

import android.content.Context
import android.content.Intent
import android.media.AudioFormat
import android.os.Build
import android.os.Bundle
import android.os.ParcelFileDescriptor
import android.speech.RecognitionListener
import android.speech.RecognitionPart
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import com.roro.futurevoice.audio.WavPcm
import com.roro.futurevoice.data.LanguageCatalog
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import java.io.File
import kotlin.coroutines.resume

/**
 * PROBE ONLY (capture build): the platform recognizer run over a recording
 * already on disk — the measurement behind plan 2.9's choice of take timing.
 *
 * Android 13 added `EXTRA_AUDIO_SOURCE` (feed the recognizer a file
 * descriptor) and Android 14 `EXTRA_REQUEST_WORD_TIMING`, whose
 * `RecognitionPart`s should carry each word's onset. Measured 2026-10-02 on
 * the Pixel 9 emulator (API 36, Google recognizer): a plain request returns
 * an EMPTY result; a segmented session returns the words, perfectly
 * ("soak it all in right we could grab…", 0.6 s) but no parts; the on-device
 * recognizer refuses until a language pack is downloaded (error 13). So no
 * recognizer the app can reach returns word times for a file, and the app
 * measures the learner with `TakeAligner` instead. `probe-asr` reruns this.
 */
object FileRecognizer {

    /** One recognized word and when it started, ms from the file's start. */
    data class Part(val text: String, val startMs: Int)

    data class Result(
        val text: String,
        /** Empty when the recognizer returned words but no times. */
        val parts: List<Part>,
        /** Which recognizer answered ("on_device" / "default"). */
        val engine: String,
        val ms: Long,
    )

    /** The API floor: file input is 33, word timing 34. */
    val supported: Boolean get() = Build.VERSION.SDK_INT >= 34

    /**
     * Recognize [wav]. Tries the on-device recognizer first (offline, no
     * upload), then the default one. [timeoutMs] bounds each attempt: a
     * recognizer that never calls back must not hold the score.
     */
    suspend fun recognize(
        context: Context,
        wav: File,
        language: String,
        timeoutMs: Long = 12_000,
        hints: List<String> = emptyList(),
    ): Result? {
        if (!supported) return null
        val pcm = withContext(Dispatchers.IO) { WavPcm.read(wav) } ?: return null
        if (pcm.samples.isEmpty()) return null
        val raw = withContext(Dispatchers.IO) {
            File(context.cacheDir, "filerec-${System.nanoTime()}.pcm").also { it.writeBytes(pcm.pcmBytes()) }
        }
        try {
            val engines = buildList {
                if (SpeechRecognizer.isOnDeviceRecognitionAvailable(context)) add(true)
                if (SpeechRecognizer.isRecognitionAvailable(context)) add(false)
            }
            for (onDevice in engines) {
                val r = withTimeoutOrNull(timeoutMs) {
                    once(context, raw, pcm.sampleRate, language, Feed(onDevice), hints)
                } ?: continue
                if (r.text.isNotBlank()) return r
            }
            return null
        } finally {
            raw.delete()
        }
    }

    /** How the audio reaches the recognizer — exposed for the probe. */
    data class Feed(
        val onDevice: Boolean,
        /** null = the file itself; else a pipe written at this × real time. */
        val pace: Double? = null,
        val segmented: Boolean = false,
    )

    suspend fun once(
        context: Context, raw: File, rate: Int, language: String, feed: Feed,
        hints: List<String> = emptyList(),
    ): Result? = withContext(Dispatchers.Main) {
        val started = System.currentTimeMillis()
        val engine = if (feed.onDevice) "on_device" else "default"
        val recognizer = runCatching {
            if (feed.onDevice) SpeechRecognizer.createOnDeviceSpeechRecognizer(context)
            else SpeechRecognizer.createSpeechRecognizer(context)
        }.getOrNull() ?: return@withContext null
        var writer: Thread? = null
        val pfd: ParcelFileDescriptor = if (feed.pace == null) {
            ParcelFileDescriptor.open(raw, ParcelFileDescriptor.MODE_READ_ONLY)
        } else {
            val (read, write) = ParcelFileDescriptor.createPipe()
            val bytesPerSecond = rate * 2
            val chunk = bytesPerSecond / 20   // 50 ms
            writer = Thread {
                runCatching {
                    ParcelFileDescriptor.AutoCloseOutputStream(write).use { out ->
                        val all = raw.readBytes()
                        var i = 0
                        while (i < all.size) {
                            val n = minOf(chunk, all.size - i)
                            out.write(all, i, n); i += n
                            Thread.sleep((50 / feed.pace).toLong())
                        }
                    }
                }
            }.also { it.start() }
            read
        }
        val heard = StringBuilder()
        val parts = mutableListOf<Part>()
        fun collect(b: Bundle?, tag: String): String {
            val text = b?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull().orEmpty()
            val got = b?.getParcelableArrayList(SpeechRecognizer.RECOGNITION_PARTS, RecognitionPart::class.java)
                .orEmpty().map { Part(it.formattedText ?: it.rawText, it.timestampMillis.toInt()) }
            android.util.Log.i("FileRecognizer", "$tag engine=$engine text='$text' parts=${got.size} " +
                "keys=${b?.keySet()}")
            if (feed.segmented) { if (text.isNotBlank()) { if (heard.isNotEmpty()) heard.append(' '); heard.append(text) }; parts += got }
            return text
        }
        try {
            suspendCancellableCoroutine<Result?> { cont ->
                fun done(r: Result?) { if (cont.isActive) cont.resume(r) }
                recognizer.setRecognitionListener(object : RecognitionListener {
                    override fun onReadyForSpeech(params: Bundle?) {}
                    override fun onBeginningOfSpeech() {}
                    override fun onRmsChanged(rmsdB: Float) {}
                    override fun onBufferReceived(buffer: ByteArray?) {}
                    override fun onEndOfSpeech() {}
                    override fun onPartialResults(partialResults: Bundle?) {}
                    override fun onEvent(eventType: Int, params: Bundle?) {}
                    override fun onSegmentResults(segmentResults: Bundle) { collect(segmentResults, "segment") }
                    override fun onEndOfSegmentedSession() {
                        done(Result(heard.toString(), parts.toList(), engine,
                            System.currentTimeMillis() - started))
                    }
                    override fun onError(error: Int) {
                        android.util.Log.i("FileRecognizer", "error=$error engine=$engine")
                        done(null)
                    }
                    override fun onResults(results: Bundle?) {
                        val b = results
                        val text = b?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull().orEmpty()
                        val got = b?.getParcelableArrayList(SpeechRecognizer.RECOGNITION_PARTS,
                            RecognitionPart::class.java).orEmpty()
                            .map { Part(it.formattedText ?: it.rawText, it.timestampMillis.toInt()) }
                        android.util.Log.i("FileRecognizer", "results engine=$engine text='$text' " +
                            "parts=${got.size} keys=${b?.keySet()}")
                        done(Result(text, got, engine, System.currentTimeMillis() - started))
                    }
                })
                val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                    putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                    putExtra(RecognizerIntent.EXTRA_LANGUAGE, LanguageCatalog.sttLocale(language))
                    putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, false)
                    putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
                    putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE, pfd)
                    putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_CHANNEL_COUNT, 1)
                    putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_ENCODING, AudioFormat.ENCODING_PCM_16BIT)
                    putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_SAMPLING_RATE, rate)
                    putExtra(RecognizerIntent.EXTRA_REQUEST_WORD_TIMING, true)
                    putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, feed.onDevice)
                    if (feed.segmented) putExtra(RecognizerIntent.EXTRA_SEGMENTED_SESSION,
                        RecognizerIntent.EXTRA_AUDIO_SOURCE)
                    if (hints.isNotEmpty()) {
                        putExtra(RecognizerIntent.EXTRA_BIASING_STRINGS, ArrayList(hints.take(100)))
                    }
                }
                cont.invokeOnCancellation { runCatching { recognizer.cancel() } }
                runCatching { recognizer.startListening(intent) }.onFailure { done(null) }
            }
        } finally {
            runCatching { recognizer.destroy() }
            runCatching { pfd.close() }
            writer?.interrupt()
        }
    }
}
