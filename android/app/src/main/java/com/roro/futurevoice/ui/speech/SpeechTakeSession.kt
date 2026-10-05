package com.roro.futurevoice.ui.speech

import android.content.Context
import com.roro.futurevoice.R
import com.roro.futurevoice.audio.LiveTranscriber
import com.roro.futurevoice.audio.SpeechCapture
import com.roro.futurevoice.core.Analytics
import com.roro.futurevoice.data.ActivityEventLog
import com.roro.futurevoice.data.CefrLevel
import com.roro.futurevoice.data.LanguageCatalog
import com.roro.futurevoice.data.MicPreference
import com.roro.futurevoice.data.SpeechScript
import com.roro.futurevoice.data.SpeechStore
import com.roro.futurevoice.data.SpeechTake
import com.roro.futurevoice.data.StoreJson
import com.roro.futurevoice.net.SpeechCoach
import com.roro.futurevoice.net.SpeechReader
import com.roro.futurevoice.talk.SpeechAnalyzer
import com.roro.futurevoice.talk.SpeechPrompterTrack
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

/**
 * One take under the prompter, from the countdown to a saved, scored take —
 * iOS `SpeechTakeSession`. The screen draws [phase], [cursor] and the level;
 * everything else is here.
 */
class SpeechTakeSession(
    private val context: Context,
    script: SpeechScript,
    private val native: String,
    private val level: CefrLevel,
) {
    sealed interface Phase {
        data object Ready : Phase
        data class Countdown(val n: Int) : Phase
        data object Recording : Phase
        data object Analyzing : Phase
        data class Done(val take: SpeechTake) : Phase
        data class Failed(val message: String) : Phase
    }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val prefs = context.getSharedPreferences("futurevoice", Context.MODE_PRIVATE)

    private val _script = MutableStateFlow(script)
    val script: StateFlow<SpeechScript> = _script
    private val _track = MutableStateFlow(SpeechPrompterTrack(script.body, script.language))
    val track: StateFlow<SpeechPrompterTrack> = _track

    private val _phase = MutableStateFlow<Phase>(Phase.Ready)
    val phase: StateFlow<Phase> = _phase
    /** The first display word not yet read. */
    private val _cursor = MutableStateFlow(0)
    val cursor: StateFlow<Int> = _cursor
    /** Whole seconds into the take. */
    private val _elapsed = MutableStateFlow(0)
    val elapsed: StateFlow<Int> = _elapsed

    private val _cameraOn = MutableStateFlow(prefs.getBoolean(CAMERA_KEY, true))
    val cameraOn: StateFlow<Boolean> = _cameraOn
    /** Every take starts following the voice; a switch lasts this visit only
     *  (iOS `01afc3f0`). */
    private val _followVoice = MutableStateFlow(true)
    val followVoice: StateFlow<Boolean> = _followVoice
    private val _speed = MutableStateFlow(prefs.getFloat(SPEED_KEY, 1f))
    val speed: StateFlow<Float> = _speed

    /** The reader is pressing to hold the steady scroll. */
    @Volatile var holding = false

    val camera = SpeechCamera(context)
    val composer = SpeechVideoComposer()
    private var capture: SpeechCapture? = null
    private var live: LiveTranscriber? = null
    @Volatile private var lastPartialAtMs = 0L
    private var ticker: Job? = null
    private var startedAtMs = 0L
    private var clock = 0.0
    private var position = 0.0
    private var wav: File? = null
    private var recordingVideo = false
    private var pieces = mutableListOf<Deferred<String?>>()
    private var lastChunkAt = 0.0
    private var follows = 0
    private var partials = 0
    private var liveDropped = false

    init {
        camera.frameHandler = { bmp, rotation, width -> composer.append(bmp, rotation, width) }
        camera.wantsFrames = { recordingVideo }
    }

    val micLevel: Float get() = capture?.level ?: 0f

    fun setCameraOn(on: Boolean) {
        _cameraOn.value = on
        prefs.edit().putBoolean(CAMERA_KEY, on).apply()
        if (!on) camera.stop()
    }

    fun setFollowVoice(on: Boolean) { _followVoice.value = on }

    fun setSpeed(value: Float) {
        _speed.value = value
        prefs.edit().putFloat(SPEED_KEY, value).apply()
    }

    private val isFailed get() = _phase.value is Phase.Failed
    private val isCountdown get() = _phase.value is Phase.Countdown

    // MARK: - Record

    suspend fun start() {
        if (_phase.value != Phase.Ready && !isFailed) return
        _cursor.value = 0; position = 0.0; _elapsed.value = 0; clock = 0.0
        // "3" goes up FIRST and the mic is set up while it shows (iOS
        // `34eca23a`); the wait before "2" shrinks by what the setup took.
        val countStartedAt = System.currentTimeMillis()
        _phase.value = Phase.Countdown(3)
        delay(30)
        val language = _script.value.language
        try {
            MicPreference.applyInputRoute(context)
            // The recognizer FIRST: where a device can't feed two mic users,
            // the later one wins, and the take must be the one that does.
            liveDropped = false
            lastPartialAtMs = 0L
            follows = 0; partials = 0
            live = runCatching {
                LiveTranscriber(context).also { t ->
                    t.start(LanguageCatalog.sttLocale(language)) { text -> heard(text) }
                }
            }.getOrNull()
        } catch (_: Exception) {
            stopLive()
            _phase.value = Phase.Failed(context.getString(R.string.the_microphone_couldn_t_start_try_again))
            return
        }
        val setupTook = System.currentTimeMillis() - countStartedAt
        delay(maxOf(0L, 700 - setupTook))
        for (n in listOf(2, 1)) {
            if (!isCountdown) return
            _phase.value = Phase.Countdown(n)
            delay(700)
            if (!isCountdown) return
        }
        val out = File(context.cacheDir, "speech-take-${System.nanoTime()}.wav")
        wav = out
        val cap = SpeechCapture(context)
        cap.onSilenced = {
            // The system gave the mic to the recognizer: keep the TAKE, drop
            // the recognizer for the rest of it. Following then runs on the
            // voice level alone.
            if (!liveDropped) { liveDropped = true; stopLive() }
        }
        try {
            cap.start(out, File(context.cacheDir, "speech-pieces"))
        } catch (_: Exception) {
            stopLive()
            _phase.value = Phase.Failed(context.getString(R.string.the_microphone_couldn_t_start_try_again))
            return
        }
        capture = cap
        pieces = mutableListOf()
        lastChunkAt = 0.0
        recordingVideo = _cameraOn.value && camera.running.value && composer.isPrepared
        if (recordingVideo) composer.begin(context.cacheDir)
        startedAtMs = System.currentTimeMillis()
        _phase.value = Phase.Recording
        runTicker()
    }

    /** The script was edited from the prompter: read the new text from the
     *  top. Only between takes. */
    fun replaceScript(updated: SpeechScript) {
        if (_phase.value != Phase.Ready && !isFailed) return
        _script.value = updated
        _track.value = SpeechPrompterTrack(updated.body, updated.language)
        reset()
    }

    private fun heard(text: String) {
        lastPartialAtMs = System.currentTimeMillis()
        if (_phase.value != Phase.Recording || !_followVoice.value) return
        partials++
        val t = _track.value
        val next = t.advance(_cursor.value, text)
        if (next != _cursor.value) {
            follows++
            _cursor.value = minOf(next, t.words.size)
            position = _cursor.value.toDouble()
        }
    }

    private fun runTicker() {
        ticker?.cancel()
        ticker = scope.launch {
            while (isActive) {
                delay(100)
                if (_phase.value != Phase.Recording) return@launch
                tick()
            }
        }
    }

    private fun tick() {
        clock = (System.currentTimeMillis() - startedAtMs) / 1000.0
        val whole = clock.toInt()
        if (whole != _elapsed.value) _elapsed.value = whole
        val t = _track.value
        val language = _script.value.language
        if (!_followVoice.value && !holding) {
            position += t.wordsPerSecond(language) * _speed.value * 0.1
            _cursor.value = minOf(t.words.size, position.toInt())
        }
        val quietFor = capture?.lastVoicedAtMs?.let { (System.currentTimeMillis() - it) / 1000.0 } ?: clock

        // Cut a piece for the reader at a pause, never mid-word.
        if (clock - lastChunkAt >= CHUNK_SECONDS && quietFor >= 0.35) {
            capture?.rotatePiece()?.let { piece ->
                lastChunkAt = clock
                pieces += readPiece(piece)
            }
        }
        // Held: the reader stopped the text on purpose; nothing ends now.
        if (holding) return
        // Finished = the LAST word was heard, then a second of quiet; ON the
        // last word, three (a breath before it must not end the take —
        // iOS `a20a4030`).
        val lastHeard = _cursor.value >= t.words.size
        val onLast = _cursor.value >= t.words.size - 1
        if (((lastHeard && quietFor > 1.0) || (onLast && quietFor > 3.0)) && clock > 3) {
            scope.launch { stop() }
            return
        }
        // A take nobody ends still ends.
        if (clock > _script.value.targetSeconds * 3 + 60) scope.launch { stop() }
    }

    /** Whether a voice was heard a moment ago — the prompter keeps flowing
     *  while someone speaks. Two witnesses, either is enough. */
    fun voiceActive(): Boolean {
        val now = System.currentTimeMillis()
        capture?.lastVoicedAtMs?.let { if (now - it < 1200) return true }
        if (lastPartialAtMs > 0 && now - lastPartialAtMs < 1500) return true
        return false
    }

    // MARK: - Stop and score

    suspend fun stop() {
        if (_phase.value != Phase.Recording) return
        _phase.value = Phase.Analyzing
        ticker?.cancel()
        val stoppedAt = System.currentTimeMillis()
        val duration = clock
        val cap = capture
        capture = null
        val tail = cap?.stop()
        val liveText = stopLive()
        tail?.let { pieces += readPiece(it) }
        val reads = pieces.toList()
        pieces = mutableListOf()
        val fromCamera = recordingVideo
        recordingVideo = false
        val voiceStart = cap?.startNanos ?: 0L
        val videoStop = scope.async(Dispatchers.IO) {
            if (!fromCamera) null else composer.finish()?.let { r -> r.file to (voiceStart - r.firstFrameNanos) }
        }

        val recorded = wav
        if (recorded == null || !recorded.exists()) {
            _phase.value = Phase.Failed(context.getString(R.string.the_recording_couldn_t_be_saved_try_again))
            return
        }
        val script = _script.value
        val store = SpeechStore.shared(context)
        val id = StoreJson.newId()
        val audioName = "take-$id.wav"
        val audio = SpeechStore.mediaFile(context, audioName)
        val moved = withContext(Dispatchers.IO) {
            recorded.renameTo(audio) || runCatching { recorded.copyTo(audio, true); recorded.delete(); true }.getOrDefault(false)
        }
        if (!moved) {
            _phase.value = Phase.Failed(context.getString(R.string.the_recording_couldn_t_be_saved_try_again))
            return
        }
        val envelope = withContext(Dispatchers.Default) { SpeechAnalyzer.envelope(audio) }
        if (envelope == null || envelope.speakingSeconds <= 1.5) {
            audio.delete()
            scope.launch { videoStop.await()?.first?.delete() }
            _phase.value = Phase.Failed(context.getString(R.string.we_didn_t_hear_you_check_the_microphone_and_try_again))
            return
        }

        // The pieces were read during the take; only the tail is left. Any
        // piece that failed sends the whole file instead, so a hole is never
        // scored as skipped words.
        val readStart = System.currentTimeMillis()
        val texts = mutableListOf<String>()
        for (p in reads) {
            val text = p.await()
            if (text == null) { texts.clear(); break }
            texts += text
        }
        val transcript: String
        val audioGrounded: Boolean
        val path: String
        if (reads.isNotEmpty() && texts.size == reads.size && texts.joinToString("").isNotBlank()) {
            val joiner = if (LanguageCatalog.writesSpaces(script.language)) " " else ""
            transcript = texts.map { it.trim() }.filter { it.isNotEmpty() }.joinToString(joiner)
            audioGrounded = true; path = "pieces"
        } else {
            val reading = SpeechReader.read(audio, liveText, script.language)
            transcript = reading.text; audioGrounded = reading.audioGrounded; path = "whole"
        }
        val readMs = System.currentTimeMillis() - readStart
        // The diff is O(script × transcript) — off the main thread.
        val metrics = withContext(Dispatchers.Default) {
            SpeechAnalyzer.analyze(script.body, transcript, script.language, envelope)
        }
        val take = SpeechTake(
            id = id, scriptId = script.id, createdAt = System.currentTimeMillis(),
            durationSeconds = duration, audioFilename = audioName, videoFilename = null,
            transcript = transcript, metrics = metrics, coaching = null,
        )
        store.save(take)
        // A saved take is what a Speech block in the routine asks for.
        ActivityEventLog.record(context, ActivityEventLog.Kind.SPEECH)
        val resultMs = System.currentTimeMillis() - stoppedAt
        // Flagged BEFORE the result shows, so it opens on "Preparing your
        // video…" rather than flashing the audio player first.
        if (fromCamera) store.markVideoPending(id, true)
        _phase.value = Phase.Done(take)

        val videoTask = scope.async(Dispatchers.IO) {
            try {
                val (raw, leadIn) = videoStop.await() ?: return@async false
                val name = "take-$id.mp4"
                val merged = SpeechMediaMerger.merge(raw, audio, SpeechStore.mediaFile(context, name), leadIn)
                raw.delete()
                if (!merged) return@async false
                update(id) { it.copy(videoFilename = name) }
                true
            } finally {
                withContext(Dispatchers.Main) { store.markVideoPending(id, false) }
            }
        }

        val coachStart = System.currentTimeMillis()
        SpeechCoach.review(script, transcript, metrics, native, level)?.let { c ->
            update(id) { it.copy(coaching = c) }
        }
        val coachMs = System.currentTimeMillis() - coachStart
        val hasVideo = videoTask.await()
        Analytics.capture("speech_take", mapOf(
            "built_in" to script.isBuiltIn, "genre" to script.genre.raw,
            "seconds" to duration.toInt(), "overall" to metrics.overall, "accuracy" to metrics.accuracy,
            "camera" to hasVideo, "follow" to _followVoice.value, "audio_grounded" to audioGrounded,
            "read_path" to path, "cursor_end" to _cursor.value, "words" to _track.value.words.size,
            "follows" to follows, "partials" to partials, "pieces" to reads.size,
            "live_dropped" to liveDropped,
            "read_ms" to readMs, "result_ms" to resultMs, "coach_ms" to coachMs,
        ))
    }

    private fun readPiece(file: File): Deferred<String?> {
        val language = _script.value.language
        return scope.async(Dispatchers.IO) {
            try { SpeechReader.readPiece(file, language) } finally { file.delete() }
        }
    }

    /** Applies a change to the stored take and to the one on screen. */
    private suspend fun update(id: String, change: (SpeechTake) -> SpeechTake) = withContext(Dispatchers.Main) {
        val next = SpeechStore.shared(context).update(id, change) ?: return@withContext
        val shown = _phase.value
        if (shown is Phase.Done && shown.take.id == id) _phase.value = Phase.Done(next)
    }

    private fun stopLive(): String {
        val t = live ?: return ""
        live = null
        return runCatching { t.stop() }.getOrDefault("")
    }

    /** Back to the start of the script, ready for another take. */
    fun reset() {
        _cursor.value = 0; position = 0.0; _elapsed.value = 0; clock = 0.0
        _phase.value = Phase.Ready
    }

    /** Leaving: nothing in progress is kept. */
    fun tearDown() {
        if (_phase.value == Phase.Recording) {
            Analytics.capture("speech_take_cancelled", followFacts() + mapOf("seconds" to clock.toInt(), "closed" to true))
        }
        discardRecording()
        camera.stop()
        scope.cancel()
    }

    private fun discardRecording() {
        ticker?.cancel()
        if (_phase.value != Phase.Recording && !isCountdown) return
        capture?.let { cap ->
            cap.stop()?.delete()
        }
        capture = null
        wav?.delete()
        stopLive()
        pieces.forEach { it.cancel() }
        pieces = mutableListOf()
        if (recordingVideo) { recordingVideo = false; Thread { composer.cancel() }.start() }
    }

    /** Cancel: this take is dropped and the script is back at the top. */
    fun cancelTake() {
        if (_phase.value == Phase.Recording) {
            Analytics.capture("speech_take_cancelled", followFacts() + mapOf("seconds" to clock.toInt()))
        }
        discardRecording()
        reset()
    }

    /** Again: this take is dropped and a fresh one counts in right away. */
    fun restartTake() {
        cancelTake()
        scope.launch { start() }
    }

    fun launch(block: suspend () -> Unit) { scope.launch { block() } }

    private fun followFacts(): Map<String, Any?> = mapOf(
        "words" to _track.value.words.size, "cursor_end" to _cursor.value, "follows" to follows,
        "partials" to partials, "language" to _script.value.language, "follow" to _followVoice.value,
    )

    /** Captures only: a take caught mid-read, without a mic. */
    fun preview(cursor: Int) {
        _cursor.value = cursor
        _cameraOn.value = false
        _elapsed.value = 21
        _phase.value = Phase.Recording
    }

    companion object {
        private const val CAMERA_KEY = "speech.cameraOn"
        private const val SPEED_KEY = "speech.speed"
        const val CHUNK_SECONDS = 12.0
    }
}
