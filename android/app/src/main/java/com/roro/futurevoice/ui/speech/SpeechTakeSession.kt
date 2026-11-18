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
import com.roro.futurevoice.data.PronunciationLedger
import com.roro.futurevoice.data.SpeechLibrary
import com.roro.futurevoice.data.SpeechScript
import com.roro.futurevoice.data.SpeechStore
import com.roro.futurevoice.data.SpeechTake
import com.roro.futurevoice.data.StoreJson
import com.roro.futurevoice.net.SpeechCoach
import com.roro.futurevoice.net.SpeechReader
import com.roro.futurevoice.talk.SpeechAnalyzer
import com.roro.futurevoice.talk.PronunciationAssessor
import com.roro.futurevoice.talk.PronunciationResult
import com.roro.futurevoice.talk.SpeechPrompterTrack
import com.roro.futurevoice.talk.SpeechDelivery
import com.roro.futurevoice.talk.SpeechReading
import com.roro.futurevoice.talk.SpeechReadingScore
import com.roro.futurevoice.talk.SpeechReference
import com.roro.futurevoice.talk.SpeechReferenceService
import com.roro.futurevoice.audio.WavPcm
import com.roro.futurevoice.data.SpeechMetrics
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
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
    /** The take's script layout; the movement is filled in when it ends. */
    private var prompterBase: com.roro.futurevoice.data.SpeechPrompterRecord? = null
    private var capture: SpeechCapture? = null
    private var live: LiveTranscriber? = null
    @Volatile private var lastPartialAtMs = 0L
    private var ticker: Job? = null
    private var startedAtMs = 0L
    private var clock = 0.0
    /** Set as the take starts ([ceilingSeconds]), read on every tick. */
    private var takeCeiling = Double.POSITIVE_INFINITY
    private var position = 0.0
    private var wav: File? = null
    private var recordingVideo = false
    private var pieces = mutableListOf<Deferred<Piece?>>()
    private var lastChunkAt = 0.0
    /** The prompter cursor at the last cut: the script from here to the
     *  cursor at the next cut is that piece's reference ([scriptSpan]). */
    private var lastCutCursor = 0
    private var follows = 0
    private var partials = 0
    private var liveDropped = false

    /** The native reference reading, fetched as the screen opens so it is
     *  there when the take ends (Season 2 scoring only). */
    private val referenceTask: Deferred<SpeechReference?>? =
        if (SpeechReading.isActive(context, script.language))
            scope.async { SpeechReferenceService.fetch(context, script.body, script.language) }
        else null
    /** The listening reading's words with its sounds: THE reference since iOS
     *  cddddcc0, and a sound it says off the dictionary is never charged
     *  ([SpeechReading.fluentLowSounds]). */
    private val fluentTask: Deferred<com.roro.futurevoice.talk.SpeechListenAudio?>? =
        if (SpeechReading.isActive(context, script.language))
            scope.async { com.roro.futurevoice.talk.SpeechListenService.reading(context, script) }
        else null

    init {
        // Fluent pace: the listening reading's word times laid onto the
        // prompter's words, once the reading has loaded — only when it lines
        // up word for word with the prompter.
        fluentTask?.let { task ->
            scope.launch {
                val reading = task.await() ?: return@launch
                val starts = com.roro.futurevoice.talk.SpeechListenText.display(script.body, reading.words)
                    .map { it.time?.first }
                if (starts.size != _track.value.words.size || starts.none { it != null }) return@launch
                guideStarts = starts
                _fluentPaceAvailable.value = true
            }
        }
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

    /** Karaoke (iOS cddddcc0, founder): the prompter moves at the FLUENT
     *  reading's tempo from the reader's first word, and [guide] is the word
     *  they should be saying now. Off by default (a beginner reads at their own
     *  pace); per visit, like [followVoice]. The score is the same either way. */
    private val _fluentPace = MutableStateFlow(false)
    val fluentPace: StateFlow<Boolean> = _fluentPace
    fun setFluentPace(on: Boolean) { _fluentPace.value = on }
    /** The word the fluent reading is on, while [fluentPace] runs. */
    private val _guide = MutableStateFlow<Int?>(null)
    val guide: StateFlow<Int?> = _guide
    /** The fluent reading has been laid onto the prompter's words. */
    private val _fluentPaceAvailable = MutableStateFlow(false)
    val fluentPaceAvailable: StateFlow<Boolean> = _fluentPaceAvailable
    /** Each prompter word's start in the fluent reading, seconds. */
    private var guideStarts: List<Double?> = emptyList()
    /** The take's clock minus the fluent reading's, set at the first word. */
    private var guideOrigin: Double? = null

    /** Listening first (iOS, 2026-11-17, founder): the fluent reading played on
     *  the take screen before a take, the prompter rising with it and the
     *  word being read highlighted ([guide]). Paused, the script stays put;
     *  a take, or the reading's end, puts it back at the top. */
    enum class ListenState { OFF, PLAYING, PAUSED }
    private val _listenState = MutableStateFlow(ListenState.OFF)
    val listenState: StateFlow<ListenState> = _listenState
    private val _listenLoading = MutableStateFlow(false)
    val listenLoading: StateFlow<Boolean> = _listenLoading
    internal val listen = SpeechListenModel()
    private var listenTicker: Job? = null

    /** Play or pause the fluent reading. The first tap fetches its audio. */
    suspend fun toggleListen() {
        if (_phase.value != Phase.Ready || !_fluentPaceAvailable.value || _listenLoading.value) return
        if (_listenState.value == ListenState.PLAYING) { pauseListen(); return }
        if (listen.phase == SpeechListenModel.Phase.IDLE) {
            _listenLoading.value = true
            listen.load(context, _script.value)
            _listenLoading.value = false
        }
        if (listen.phase != SpeechListenModel.Phase.READY || _phase.value != Phase.Ready) return
        if (_listenState.value == ListenState.OFF) _guide.value = 0
        listen.toggle()
        _listenState.value = ListenState.PLAYING
        listenTicker?.cancel()
        listenTicker = scope.launch {
            while (true) {
                delay(50)
                if (_listenState.value != ListenState.PLAYING) return@launch
                if (!listen.player.isPlaying) {
                    // Read to the end: back to the top.
                    stopListen()
                    return@launch
                }
                val t = listen.player.currentTime
                val at = guideStarts.indexOfLast { (it ?: Double.POSITIVE_INFINITY) <= t }.coerceAtLeast(0)
                if (at != _guide.value) _guide.value = at
            }
        }
    }

    /** Keeps the place (a sheet opening over the screen, or a second tap). */
    fun pauseListen() {
        if (_listenState.value != ListenState.PLAYING) return
        listenTicker?.cancel()
        listen.player.pause()
        _listenState.value = ListenState.PAUSED
    }

    fun stopListen() {
        listenTicker?.cancel()
        if (_listenState.value == ListenState.OFF) return
        listen.stop()
        _listenState.value = ListenState.OFF
        _guide.value = null
    }

    fun setSpeed(value: Float) {
        _speed.value = value
        prefs.edit().putFloat(SPEED_KEY, value).apply()
    }

    /** Called by the screen right before a take: how the script is laid out
     *  (null: no video this take) — iOS `prepareVideo`. */
    fun prepareVideo(record: com.roro.futurevoice.data.SpeechPrompterRecord?) { prompterBase = record }

    private val isFailed get() = _phase.value is Phase.Failed
    private val isCountdown get() = _phase.value is Phase.Countdown

    // MARK: - Record

    suspend fun start() {
        if (_phase.value != Phase.Ready && !isFailed) return
        stopListen()
        _cursor.value = 0; position = 0.0; _elapsed.value = 0; clock = 0.0
        _script.value.let { takeCeiling = ceilingSeconds(it.targetSeconds, it.body, it.language) }
        // "3" goes up FIRST and the mic is set up while it shows (iOS
        // `34eca23a`); the wait before "2" shrinks by what the setup took.
        val countStartedAt = System.currentTimeMillis()
        _phase.value = Phase.Countdown(3)
        delay(30)
        val language = _script.value.language
        try {
            MicPreference.applyInputRoute(context)
            // The recognizer hears the TAKE's own audio (fed from the capture
            // below, iOS's one-tap shape): it never opens the mic, so nothing
            // silences it and it plays no earcon. On Android < 13 it still
            // opens the mic itself, so it starts FIRST: where a device can't
            // feed two mic users, the later one wins, and the take must be
            // the one that does.
            liveDropped = false
            lastPartialAtMs = 0L
            follows = 0; partials = 0
            live = runCatching {
                LiveTranscriber(context).also { t ->
                    t.start(LanguageCatalog.sttLocale(language), fed = true) { text -> heard(text) }
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
            android.util.Log.w("SpeechTake", "capture silenced by the system — dropping the recognizer")
            if (!liveDropped) { liveDropped = true; stopLive() }
        }
        live?.takeIf { it.acceptsFeed }?.let { t -> cap.tap = { buf, n -> t.feed(buf, n) } }
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
        lastCutCursor = 0
        recordingVideo = _cameraOn.value && camera.running.value && prompterBase != null
        if (recordingVideo) composer.begin(context.cacheDir)
        startedAtMs = System.currentTimeMillis()
        _guide.value = null
        guideOrigin = null
        _phase.value = Phase.Recording
        runTicker()
    }

    /** The script was edited from the prompter: read the new text from the
     *  top. Only between takes. */
    fun replaceScript(updated: SpeechScript) {
        if (_phase.value != Phase.Ready && !isFailed) return
        stopListen()
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
        // The fluent clock starts at the reader's first word: lined up on the
        // word they reached, so it never begins behind them.
        if (_fluentPace.value && guideOrigin == null && next > 0 && guideStarts.isNotEmpty()) {
            val reached = minOf(next, guideStarts.size) - 1
            guideStarts.subList(0, reached + 1).lastOrNull { it != null }?.let { at ->
                guideOrigin = (System.currentTimeMillis() - startedAtMs) / 1000.0 - at
            }
        }
        if (com.roro.futurevoice.BuildConfig.DEBUG) android.util.Log.d("SpeechTake", "heard#$partials cursor=${_cursor.value}->$next \"${text.takeLast(60)}\"")
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
        // Karaoke: the word the fluent reading is on at this moment.
        val origin = guideOrigin
        if (_fluentPace.value && origin != null) {
            val now = clock - origin
            val at = guideStarts.indexOfLast { (it ?: Double.POSITIVE_INFINITY) <= now }.takeIf { it >= 0 }
            if (at != _guide.value) _guide.value = at
        }
        if (!_followVoice.value && !holding) {
            position += t.wordsPerSecond(language) * _speed.value * 0.1
            _cursor.value = minOf(t.words.size, position.toInt())
        }
        // How long nobody has been heard — by EITHER witness, the level
        // meter or the recognizer (iOS 2026-11-03). The meter alone read a
        // whole take as silence (a phone propped up for the camera, an arm's
        // length away): every piece was cut at exactly 12.0 s, mid-word, and
        // the take ended the instant the prompter reached the second-to-last
        // word, so the last words were never recorded and the result said the
        // last sentence was skipped. `voiceActive` already takes both.
        val quietFor = quietSeconds() ?: clock

        // Cut a piece for the reader at a pause, never mid-word — and at a
        // sentence end while one comes within CHUNK_HARD_SECONDS, so the
        // piece's reference is whole script sentences (iOS 14706881).
        if (clock - lastChunkAt >= CHUNK_SECONDS && quietFor >= 0.35 &&
            (atSentenceEnd() || clock - lastChunkAt >= CHUNK_HARD_SECONDS)) {
            capture?.rotatePiece()?.let { piece ->
                lastChunkAt = clock
                pieces += readPiece(piece, scriptSpan(_cursor.value), _cursor.value, clock)
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
        if (clock > takeCeiling) scope.launch { stop() }
    }

    /** Seconds since anyone was last heard, by the level meter or by the
     *  recognizer producing new words — whichever is more recent. Null until
     *  either has heard anything. */
    private fun quietSeconds(): Double? {
        val now = System.currentTimeMillis()
        val heard = listOfNotNull(capture?.lastVoicedAtMs, lastPartialAtMs.takeIf { it > 0 })
        return heard.maxOrNull()?.let { (now - it) / 1000.0 }
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
        val meterVoiced = cap?.meterVoicedSeconds ?: 0.0
        val tail = cap?.stop()
        val liveText = stopLive()
        tail?.let { pieces += readPiece(it, scriptSpan(_track.value.words.size), _track.value.words.size, duration) }
        val reads = pieces.toList()
        pieces = mutableListOf()
        val fromCamera = recordingVideo
        recordingVideo = false
        val voiceStart = cap?.startNanos ?: 0L
        val videoStop = scope.async(Dispatchers.IO) {
            // (movie, how long the picture started before the voice, the
            // script's movement)
            if (!fromCamera) null else composer.finish()?.let { r -> Triple(r.file, voiceStart - r.firstFrameNanos, r.offsets) }
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

        // A challenge is read to the END (iOS 2026-11-18, founder: "stopped
        // halfway, it can't go up; don't even score it"). Once the words are
        // back, a take that didn't read the whole script is not scored, saved
        // or entered: the learner is asked to read it again.
        suspend fun readTooLittle(transcript: String): Boolean {
            if (!script.isChallenge) return false
            val share = withContext(Dispatchers.Default) {
                com.roro.futurevoice.data.SpeechChallenges.readShare(script.body, transcript, script.language)
            }
            if (share >= com.roro.futurevoice.data.SpeechChallenges.FULL_READING) return false
            audio.delete()
            scope.launch { videoStop.await()?.first?.delete() }
            Analytics.capture("speech_take_unfinished", mapOf(
                "seconds" to duration.toInt(), "coverage" to Math.round(share * 100).toInt(),
                "cursor_end" to _cursor.value, "words" to _track.value.words.size, "camera" to fromCamera,
            ))
            _phase.value = Phase.Failed(context.getString(R.string.speech_read_to_the_end_for_a_score))
            return true
        }

        // The pieces were read during the take; only the tail is left. Any
        // piece that failed sends the whole file instead, so a hole is never
        // scored as skipped words.
        val readStart = System.currentTimeMillis()
        val texts = mutableListOf<String>()
        var prons = mutableListOf<PronunciationResult>()
        var assessed = listOf<SpeechDelivery.Piece>()
        var readBackFixed = 0
        var restoredWords = 0
        var placedPieces = 0
        var unassessed = false
        for (p in reads) {
            val piece = p.await()
            if (piece == null) { texts.clear(); prons.clear(); assessed = emptyList(); break }
            texts += piece.text
            if (piece.readBackReplaced) readBackFixed++
            restoredWords += piece.restoredWords
            if (piece.placed) placedPieces++
            // The tail cut at the stop is often a fraction of a second; judged
            // against the prompter's last span it scored 0 (iOS, 2026-11-18).
            if (piece.seconds < MIN_ASSESSED_SECONDS) continue
            val pron = piece.pron
            if (pron != null) {
                prons += pron
                assessed = assessed + SpeechDelivery.Piece(piece.reference, pron, piece.startMs)
            } else unassessed = true
        }
        val transcript: String
        val audioGrounded: Boolean
        val path: String
        if (reads.isNotEmpty() && texts.size == reads.size && texts.joinToString("").isNotBlank()) {
            val joiner = if (LanguageCatalog.writesSpaces(script.language)) " " else ""
            transcript = texts.map { it.trim() }.filter { it.isNotEmpty() }.joinToString(joiner)
            audioGrounded = true; path = if (unassessed) "pieces_windows" else "pieces"
            if (readTooLittle(transcript)) return
            // A reader who never pauses is never cut, and a piece over Azure's
            // 30 s is not assessed: the whole file is assessed in windows
            // instead, as a whole read is (iOS, 2026-11-18).
            if (unassessed) {
                val windows = assessInWindows(audio, _track.value.words, script.language)
                if (windows.isNotEmpty()) {
                    assessed = windows
                    prons = windows.map { it.result }.toMutableList()
                }
            }
        } else {
            // A take longer than one assessment is cut into windows here and
            // each is read and assessed on its own, BESIDE the whole read, so
            // the sounds are still heard and the wait is the slower of the two
            // (iOS 247383e9).
            val language = script.language
            val words = _track.value.words
            val long = if (duration > PronunciationAssessor.MAX_SECONDS)
                scope.async(Dispatchers.IO) { assessInWindows(audio, words, language) } else null
            val reading = SpeechReader.read(audio, liveText, script.language)
            transcript = reading.text; audioGrounded = reading.audioGrounded; path = "whole"
            if (readTooLittle(transcript)) { long?.cancel(); return }
            prons = mutableListOf()
            assessed = emptyList()
            if (long != null) {
                assessed = long.await()
                prons = assessed.map { it.result }.toMutableList()
            } else if (reading.audioGrounded) {
                // Judged against the script span the words were read from, as
                // a piece is; the reader's own words only off the script.
                val reference = com.roro.futurevoice.talk.ShadowScore.scriptRange(
                    transcript, words.map { it.text }, language, null)
                    ?.let { spanText(words, it, language) } ?: transcript
                PronunciationAssessor.assess(context, audio, reference, script.language, "speech")
                    .result?.let {
                        prons = mutableListOf(it)
                        assessed = listOf(SpeechDelivery.Piece(reference, it))
                    }
            }
        }
        val readMs = System.currentTimeMillis() - readStart
        // The diff is O(script × transcript) — off the main thread.
        // One number for the take's sounds: each piece's sound score weighted
        // by how many words it judged. Its own row on the result, and a
        // quarter of `overall` (iOS 2026-11-04).
        val pronunciation = pronunciation(prons)
        // How it was delivered (`SpeechDelivery`): recorded on every take, and
        // with Season 2's scoring on, what four of its five parts are.
        val deliveryPieces = assessed
        val delivery = scope.async(Dispatchers.Default) {
            SpeechDelivery.measure(deliveryPieces, script.language, audio)
        }
        var metrics = withContext(Dispatchers.Default) {
            SpeechAnalyzer.analyze(script.body, transcript, script.language, envelope, pronunciation?.first)
        }
        // Season 2: compared with a native reading of this script in the
        // reader's gender. Without the reference (offline, the server not
        // ready) the take keeps the scoring it already has.
        if (SpeechReading.isActive(context, script.language)) {
            val delivered = delivery.await()
            // THE reference is the one reading the learner hears (karaoke: its
            // tempo, rhythm and pauses are the target), in whatever voice the
            // challenge was given (iOS cddddcc0). A script with no such reading
            // (the learner's own) keeps the pair.
            val fluent = withTimeoutOrNull(20_000) { fluentTask?.await() }
            val single = fluent?.let { SpeechReference(2, it.words, it.words) }
            val paired = if (single == null) withTimeoutOrNull(45_000) { referenceTask?.await() } else null
            var reading = (single ?: paired)?.let { reading(assessed, it, script.body, metrics, delivered, fluent?.words) }
            if (reading != null && fluent != null) reading = reading.copy(gender = fluent.gender, reference = "listen")
            if (reading != null) {
                metrics = metrics.copy(reading = reading, overall = reading.total, scoring = SpeechReading.VERSION)
            }
        }
        val take = SpeechTake(
            id = id, scriptId = script.id, createdAt = System.currentTimeMillis(),
            durationSeconds = duration, audioFilename = audioName, videoFilename = null,
            transcript = transcript, metrics = metrics, coaching = null,
            pronunciationWords = pronunciation?.second,
            assessments = prons.ifEmpty { null },
            assessmentStartsMs = if (assessed.size == prons.size && prons.isNotEmpty()) assessed.map { it.startMs } else null,
        )
        store.save(take)
        PronunciationLedger.shared(context).record(prons, id, "speech", script.language)
        // A saved take is what a Speech block in the routine asks for.
        ActivityEventLog.record(context, ActivityEventLog.Kind.SPEECH)
        // A challenge's board takes only what the camera recorded; the score
        // goes up, the video and the voice never do.
        if (script.isChallenge) {
            com.roro.futurevoice.data.SpeechChallenges.shared(context).enter(take, script, recordedOnCamera = fromCamera)
        }
        val resultMs = System.currentTimeMillis() - stoppedAt
        // Flagged BEFORE the result shows, so it opens on "Preparing your
        // video…" rather than flashing the audio player first.
        if (fromCamera) store.markVideoPending(id, true)
        _phase.value = Phase.Done(take)

        val videoTask = scope.async(Dispatchers.IO) {
            try {
                val (raw, leadIn, offsets) = videoStop.await() ?: return@async false
                val name = "take-$id.mp4"
                val merged = SpeechMediaMerger.merge(raw, audio, SpeechStore.mediaFile(context, name), leadIn)
                raw.delete()
                if (!merged) return@async false
                val record = prompterRecord(prompterBase, offsets, leadIn / 1e9,
                    context.resources.displayMetrics.density,
                    _track.value.words.map { it.text }, script.language, deliveryPieces)
                update(id) { it.copy(videoFilename = name, prompter = record) }
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
        val delivered = delivery.await()
        Analytics.capture("speech_take", mapOf(
            "built_in" to script.isBuiltIn, "challenge" to script.isChallenge, "genre" to script.genre.raw,
            "seconds" to duration.toInt(), "overall" to metrics.overall, "accuracy" to metrics.accuracy,
            "camera" to hasVideo, "follow" to _followVoice.value, "audio_grounded" to audioGrounded,
            "read_path" to path, "cursor_end" to _cursor.value, "words" to _track.value.words.size,
            "follows" to follows, "partials" to partials, "pieces" to reads.size,
            // How many pieces came back with a phoneme assessment, and the
            // take's number — the only record of whether the reader answers.
            "pron_pieces" to prons.size,
            "pron" to (metrics.pronunciation ?: -1),
            // How it was delivered: where readers stand against the Season 2
            // calibration. -1 = not measured.
            "prosody" to (delivered.prosody ?: -1),
            "fluency" to (delivered.fluency ?: -1),
            "weak_sounds" to (delivered.weakSounds ?: -1),
            "mid_pauses" to (delivered.midPauses ?: -1),
            "mid_boundaries" to (delivered.midBoundaries ?: -1),
            "wpm" to (delivered.wordsPerMinute ?: -1),
            "monotone_words" to delivered.monotoneWords,
            "pitch_range" to (delivered.pitchRange ?: -1.0),
            "pitch_sd" to (delivered.pitchSD ?: -1.0),
            "scoring" to (metrics.scoring ?: 0),
            // Pieces whose read-back lost words Azure heard ([pieceText]).
            "readback_fixed" to readBackFixed,
            // Script words the read-back missed and Azure heard clearly.
            "readback_restored" to restoredWords,
            "placed_pieces" to placedPieces,
            "meter_voiced" to meterVoiced.toInt(),
            "live_dropped" to liveDropped,
            "read_ms" to readMs, "result_ms" to resultMs, "coach_ms" to coachMs,
        ))
    }

    /** Whether the word the reader just finished closes a sentence. */
    private fun atSentenceEnd(): Boolean {
        val cursor = _cursor.value
        return cursor > lastCutCursor && _track.value.endsSentence(cursor - 1)
    }

    /**
     * The script the prompter walked since the last cut — this piece's
     * reference — and moves the mark. Two words of overlap at the start: a
     * prompter a word AHEAD of the voice would otherwise open the next
     * piece's audio on words its reference no longer has; a word already said
     * in the previous piece is an omission here, which the marks ignore.
     * Empty when the prompter did not move, and the reader's own words stand in.
     */
    private fun scriptSpan(upTo: Int): String {
        val words = _track.value.words
        val hi = minOf(upTo, words.size)
        if (hi <= lastCutCursor) return ""
        val lo = maxOf(0, lastCutCursor - 2)
        lastCutCursor = hi
        return spanText(words, lo until hi, _script.value.language)
    }

    /**
     * One piece of the take: its words, and how they were pronounced. The
     * piece is read first, and its own words say which part of the script it
     * holds ([ShadowScore.scriptRange]): that span is what its sounds are
     * judged against. Words that are not the script's are judged against
     * themselves. Only a piece nobody could read falls back to [cursorSpan],
     * where the prompter stood — the cursor is where the SCREEN was, and a
     * cursor behind the voice had a piece judged against the sentence before
     * the one it held (iOS 2026-11-17). The assessment waits for the
     * read-back, which happens while the next piece is still spoken.
     */
    private fun readPiece(file: File, cursorSpan: String, cursor: Int, endedAt: Double): Deferred<Piece?> {
        val language = _script.value.language
        val words = _track.value.words
        return scope.async(Dispatchers.IO) {
            // Counted back from the take's clock by the file's own length, so
            // the time the words are placed at never adds up across pieces.
            val seconds = WavPcm.read(file)?.let { it.samples.size.toDouble() / it.sampleRate } ?: 0.0
            val startMs = ((endedAt - seconds) * 1000).toInt()
            try {
                judge(file, words, language, cursorSpan, cursor, startMs, seconds)
            } finally { file.delete() }
        }
    }


    /**
     * One piece, read and judged (iOS `judge`): read first, placed in the
     * script by its own words, and assessed against that span. Also how a
     * window of a take read as one file is judged ([assessInWindows]).
     */
    private suspend fun judge(file: File, words: List<com.roro.futurevoice.talk.SpeechPrompterTrack.Word>,
                              language: String, cursorSpan: String, cursor: Int?, startMs: Int,
                              seconds: Double): Piece? {
        val readBack = SpeechReader.readPiece(file, language)
        val said = readBack?.trim().orEmpty()
        var reference = cursorSpan
        var placed = false
        if (said.isNotEmpty()) {
            val range = com.roro.futurevoice.talk.ShadowScore.scriptRange(said, words.map { it.text }, language, cursor)
            if (range != null) {
                reference = spanText(words, range, language)
                placed = true
            } else {
                reference = said
            }
        }
        if (reference.isEmpty()) return readBack?.let { Piece(it, null, seconds = seconds) }
        val result = PronunciationAssessor.assess(context, file, reference, language, "speech").result
        val insertions = result?.words?.count { it.isInsertion } ?: 0
        return pieceText(readBack, result?.recognized, language, insertions)?.let { (text, replaced) ->
            // Only against a script span the piece was placed on, and only
            // when Azure's alignment held (iOS 0c738bf4).
            val (restoredText, restored) =
                if (!replaced && placed && result != null && insertions <= MAX_INSERTIONS_TO_TRUST)
                    com.roro.futurevoice.talk.ShadowScore.restoringClearWords(text, reference, result.words, language)
                else text to 0
            Piece(restoredText, result, reference, replaced, startMs, placed, restored, seconds)
        }
    }

    /**
     * A long take's pronunciation when it was read as one file: windows of
     * ~20 s ([PronunciationAssessor.windows]), each judged as a live piece is
     * ([judge]): placed in the script and assessed against that span, all at
     * once. Until iOS 2026-11-18 a window was assessed against its own
     * read-back, which read the same reader's sounds ~7 points better than
     * pieces did. A window that can't be read or assessed is left out.
     */
    private suspend fun assessInWindows(audio: File, words: List<com.roro.futurevoice.talk.SpeechPrompterTrack.Word>,
                                        language: String): List<SpeechDelivery.Piece> {
        if (!PronunciationAssessor.supports(language)) return emptyList()
        val wav = withContext(Dispatchers.IO) { PronunciationAssessor.wav16kMono(audio) } ?: return emptyList()
        val windows = PronunciationAssessor.windows(wav)
        // The windows cut the file end to end: 16-bit, 16 kHz, a 44-byte header.
        var bytes = 0
        val starts = windows.map { window -> (bytes / 32).also { bytes += maxOf(0, window.size - 44) } }
        return coroutineScope {
            windows.mapIndexed { index, piece ->
                async(Dispatchers.IO) {
                    val tmp = File(context.cacheDir, "pron-${java.util.UUID.randomUUID()}.wav")
                    if (runCatching { tmp.writeBytes(piece) }.isFailure) return@async null
                    try {
                        judge(tmp, words, language, "", null, starts[index], 0.0)
                            ?.let { j -> j.pron?.let { SpeechDelivery.Piece(j.reference, it, starts[index]) } }
                    } finally { tmp.delete() }
                }
            }.awaitAll().filterNotNull()
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
        stopListen()
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

    /** One piece of the take: its words and how they were pronounced
     *  (null when the piece held no speech or the server did not answer). */
    data class Piece(
        val text: String,
        val pron: PronunciationResult?,
        /** What the piece was judged against: `SpeechDelivery` lines Azure's words up with it. */
        val reference: String = "",
        /** The read-back lost words Azure heard, and Azure's hearing stands in ([pieceText]). */
        val readBackReplaced: Boolean = false,
        /** Where this piece begins in the take. */
        val startMs: Int = 0,
        /** The script span came from the piece's own words, not the prompter's cursor. */
        val placed: Boolean = false,
        /** Script words put back where Azure heard them clearly ([ShadowScore.restoringClearWords]). */
        val restoredWords: Int = 0,
        /** How long the piece's audio is. */
        val seconds: Double = 0.0,
    )

    companion object {
        private const val CAMERA_KEY = "speech.cameraOn"
        /** A piece shorter than this holds no sentence to judge. */
        const val MIN_ASSESSED_SECONDS = 1.5
        private const val SPEED_KEY = "speech.speed"
        const val CHUNK_SECONDS = 12.0
        /** A piece is cut at a SENTENCE END once it is CHUNK_SECONDS long, and
         *  at the next pause whatever the word once it is this long (the
         *  assessment endpoint takes ≤30 s). */
        const val CHUNK_HARD_SECONDS = 22.0

        /** When a take nobody ended gives up: three times the script's length
         *  plus a minute. The length is read off the text as well, because a
         *  tutor, goal-prep or news script is saved with targetSeconds 0, and
         *  those takes were cut at exactly 60 s, mid sentence. */
        fun ceilingSeconds(targetSeconds: Int, body: String, language: String): Double =
            maxOf(targetSeconds, SpeechLibrary.estimatedSeconds(body, language)) * 3.0 + 60

        const val MAX_INSERTIONS_TO_TRUST = 3

        /** The script's words in [range] as one text. */
        fun spanText(words: List<com.roro.futurevoice.talk.SpeechPrompterTrack.Word>, range: IntRange, language: String): String {
            val joiner = if (LanguageCatalog.writesSpaces(language)) " " else ""
            // A line break where a paragraph ends, so `SpeechDelivery` knows a
            // paragraph's pause from a sentence's.
            val text = StringBuilder()
            for (i in range) {
                if (i > range.first) text.append(if (words[i].paragraph != words[i - 1].paragraph && joiner.isNotEmpty()) "\n" else joiner)
                text.append(words[i].text)
            }
            return text.toString()
        }

        /**
         * A piece's words, from two witnesses (iOS `pieceText`). The read-back
         * is the text the take is scored on, but it can come back short: when
         * Azure heard the piece and the read-back holds under 70% of its words
         * (or nothing), Azure's own text is the piece's text. With no Azure
         * text the read-back stands, null included.
         */
        fun pieceText(readBack: String?, heard: String?, language: String, insertions: Int = 0): Pair<String, Boolean>? {
            val read = readBack?.trim().orEmpty()
            val azure = heard?.trim().orEmpty()
            if (azure.isEmpty()) return readBack?.let { it to false }
            // Azure's text is a transcript only when its script span covered
            // the audio: for audio the span lacks, it writes words out of the
            // span ("fifty-one to ninety" came back "2025"), tagged Insertion
            // (0 on covered readings, 6 to 20 on uncovered ones). Nobody read
            // the piece: null sends the whole file to the reader. iOS 2026-11-17.
            if (insertions > MAX_INSERTIONS_TO_TRUST) return if (read.isEmpty()) null else (readBack ?: read) to false
            fun size(s: String): Int =
                if (LanguageCatalog.writesSpaces(language)) s.split(Regex("\\s+")).count { it.isNotEmpty() }
                else s.count { !it.isWhitespace() && !com.roro.futurevoice.talk.SpeechPrompterTrack.isPunctuation(it) }
            if (read.isEmpty() || size(read) < 0.7 * size(azure)) return azure to true
            return (readBack ?: read) to false
        }

        /**
         * The take's record of its script, once the video is cut: the merge
         * cut any picture before the voice, so the script's movement starts
         * there too, and the word times (the voice's clock) lose whatever was
         * cut from the voice — iOS `85fca8ba`, `8704a191`.
         * @param offsetsPx the script's position every 0.1 s from the first
         *   frame, in pixels; kept in dp, to the half, as iOS keeps points.
         * @param leadIn seconds the picture started before the voice.
         */
        fun prompterRecord(base: com.roro.futurevoice.data.SpeechPrompterRecord?, offsetsPx: List<Float>, leadIn: Double,
                           density: Float, words: List<String>, language: String,
                           pieces: List<SpeechDelivery.Piece>): com.roro.futurevoice.data.SpeechPrompterRecord? {
            base ?: return null
            val step = com.roro.futurevoice.data.SpeechPrompterRecord.STEP
            val cut = Math.round(maxOf(0.0, leadIn) / step).toInt()
            val offsets = offsetsPx.drop(cut).map { Math.round(it / density * 2.0) / 2.0 }
            val cutFromVoice = (maxOf(0.0, -leadIn) * 1000).toInt()
            val times = SpeechPrompterTrack.wordTimes(words, language, pieces)
            return base.copy(offsets = offsets,
                wordStarts = times?.first?.map { it - cutFromVoice },
                wordEnds = times?.second?.map { it - cutFromVoice })
        }

        /** A take's Season 2 score from its assessed pieces (each piece's words
         *  timed from its own start, so no pause is measured across pieces)
         *  and the reference in the reader's gender, told by the voice's pitch. */
        fun reading(pieces: List<SpeechDelivery.Piece>, reference: SpeechReference, script: String,
                    metrics: SpeechMetrics, delivery: SpeechDelivery,
                    fluent: List<SpeechReference.Word>? = null): SpeechReadingScore? {
            val scriptTokens = SpeechDelivery.referenceTokens(script)
            val tokens = scriptTokens.map { it.core }
            val take = pieces.flatMap { piece ->
                val words = piece.result.words.filter { !it.isOmission && it.durationMs > 0 }
                words.mapIndexed { i, w ->
                    SpeechReading.TimedWord(w.word, w.offsetMs, w.offsetMs + w.durationMs, i == words.lastIndex)
                }
            }
            val gender = if ((delivery.pitchMedianHz ?: 0.0) > SpeechReading.FEMALE_ABOVE_HZ) "female" else "male"
            val ref = reference.words(gender).map { SpeechReading.TimedWord(it.w, it.s, it.e, false) }
            return SpeechReading.score(
                take = SpeechReading.timeline(take, tokens),
                reference = SpeechReading.timeline(ref, tokens),
                script = tokens, stops = scriptTokens.map { it.stop },
                slips = metrics.slips, scriptTokens = metrics.scriptTokens, missed = metrics.missed,
                soundAccuracy = delivery.soundAccuracy, weakest = delivery.weakest,
                coverage = metrics.coverage ?: 1.0, gender = gender,
                weakSounds = if (pieces.isEmpty()) null
                    else SpeechReading.weakSounds(pieces.map { it.result }, script, fluent).values.sumOf { it.size },
            )
        }

        /** The take's pronunciation from its pieces: the SOUND score weighted
         *  by each piece's judged words, and every faulted word, worst first
         *  (at most 12). Null when no piece was assessed. */
        fun pronunciation(pieces: List<PronunciationResult>): Pair<Int, List<PronunciationResult.Word>>? {
            // A piece with no word judged says nothing about the sounds.
            val weighted = pieces.filter { it.judgedWords.isNotEmpty() }.map { it.soundScore to it.judgedWords.size }
            val total = weighted.sumOf { it.second }
            if (total <= 0) return null
            val score = weighted.sumOf { it.first * it.second } / total
            val weak = pieces.flatMap { it.weakWords }.sortedBy { it.accuracy ?: 0 }
            return score to weak.take(12)
        }
    }
}
