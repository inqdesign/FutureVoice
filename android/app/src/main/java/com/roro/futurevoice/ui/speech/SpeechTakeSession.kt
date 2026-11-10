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

    /** Called by the screen right before a take: how the script is laid out
     *  (null: no video this take) — iOS `prepareVideo`. */
    fun prepareVideo(record: com.roro.futurevoice.data.SpeechPrompterRecord?) { prompterBase = record }

    private val isFailed get() = _phase.value is Phase.Failed
    private val isCountdown get() = _phase.value is Phase.Countdown

    // MARK: - Record

    suspend fun start() {
        if (_phase.value != Phase.Ready && !isFailed) return
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
                pieces += readPiece(piece, scriptSpan(_cursor.value), clock)
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
        tail?.let { pieces += readPiece(it, scriptSpan(_track.value.words.size), duration) }
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

        // The pieces were read during the take; only the tail is left. Any
        // piece that failed sends the whole file instead, so a hole is never
        // scored as skipped words.
        val readStart = System.currentTimeMillis()
        val texts = mutableListOf<String>()
        var prons = mutableListOf<PronunciationResult>()
        var assessed = listOf<SpeechDelivery.Piece>()
        var readBackFixed = 0
        for (p in reads) {
            val piece = p.await()
            if (piece == null) { texts.clear(); prons.clear(); assessed = emptyList(); break }
            texts += piece.text
            if (piece.readBackReplaced) readBackFixed++
            piece.pron?.let {
                prons += it
                assessed = assessed + SpeechDelivery.Piece(piece.reference, it, piece.startMs)
            }
        }
        val transcript: String
        val audioGrounded: Boolean
        val path: String
        if (reads.isNotEmpty() && texts.size == reads.size && texts.joinToString("").isNotBlank()) {
            val joiner = if (LanguageCatalog.writesSpaces(script.language)) " " else ""
            transcript = texts.map { it.trim() }.filter { it.isNotEmpty() }.joinToString(joiner)
            audioGrounded = true; path = "pieces"
        } else {
            // A take longer than one assessment is cut into windows here and
            // each is read and assessed on its own, BESIDE the whole read, so
            // the sounds are still heard and the wait is the slower of the two
            // (iOS 247383e9).
            val language = script.language
            val long = if (duration > PronunciationAssessor.MAX_SECONDS)
                scope.async(Dispatchers.IO) { assessInWindows(audio, language) } else null
            val reading = SpeechReader.read(audio, liveText, script.language)
            transcript = reading.text; audioGrounded = reading.audioGrounded; path = "whole"
            prons = mutableListOf()
            assessed = emptyList()
            if (long != null) {
                assessed = long.await()
                prons = assessed.map { it.result }.toMutableList()
            } else if (reading.audioGrounded) {
                PronunciationAssessor.assess(context, audio, transcript, script.language, "speech")
                    .result?.let {
                        prons = mutableListOf(it)
                        assessed = listOf(SpeechDelivery.Piece(transcript, it))
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
            val reference = withTimeoutOrNull(45_000) { referenceTask?.await() }
            val reading = reference?.let { reading(assessed, it, script.body, metrics, delivered) }
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
        val joiner = if (LanguageCatalog.writesSpaces(_script.value.language)) " " else ""
        // A line break where a paragraph ends, so `SpeechDelivery` knows a
        // paragraph's pause from a sentence's.
        val text = StringBuilder()
        for (i in lo until hi) {
            if (i > lo) text.append(if (words[i].paragraph != words[i - 1].paragraph && joiner.isNotEmpty()) "\n" else joiner)
            text.append(words[i].text)
        }
        return text.toString()
    }

    /**
     * One piece of the take: its words, and how they were pronounced. The
     * script sentences the prompter walked are the reference — what the
     * learner was READING, judged for how it sounded; the two readers run
     * side by side. Without one (the prompter never moved) the read-back is
     * the reference and the assessment waits for it. Either way the result
     * never waits on this piece: it runs while the next is still spoken.
     */
    private fun readPiece(file: File, reference: String, endedAt: Double): Deferred<Piece?> {
        val language = _script.value.language
        return scope.async(Dispatchers.IO) {
            // Counted back from the take's clock by the file's own length, so
            // the time the words are placed at never adds up across pieces.
            val seconds = WavPcm.read(file)?.let { it.samples.size.toDouble() / it.sampleRate } ?: 0.0
            val startMs = ((endedAt - seconds) * 1000).toInt()
            try {
                if (reference.isNotEmpty()) {
                    coroutineScope {
                        val read = async { SpeechReader.readPiece(file, language) }
                        val pron = async { PronunciationAssessor.assess(context, file, reference, language, "speech") }
                        val readBack = read.await()
                        val result = pron.await().result
                        pieceText(readBack, result?.recognized, language)?.let { (text, replaced) ->
                            Piece(text, result, reference, replaced, startMs)
                        }
                    }
                } else {
                    val text = SpeechReader.readPiece(file, language) ?: return@async null
                    val trimmed = text.trim()
                    if (trimmed.isEmpty()) Piece(text, null)
                    else Piece(text, PronunciationAssessor.assess(context, file, trimmed, language, "speech").result,
                        trimmed, startMs = startMs)
                }
            } finally { file.delete() }
        }
    }

    /**
     * A long take's pronunciation when it was read as one file: windows of
     * ~20 s ([PronunciationAssessor.windows]), each read for its own words and
     * assessed, all at once. A window that can't be read or assessed is left
     * out (iOS 247383e9).
     */
    private suspend fun assessInWindows(audio: File, language: String): List<SpeechDelivery.Piece> {
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
                        val text = SpeechReader.readPiece(tmp, language)
                        if (text.isNullOrEmpty()) null
                        else PronunciationAssessor.assess(context, piece, text, language, "speech").result
                            ?.let { SpeechDelivery.Piece(text, it, starts[index]) }
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
    )

    companion object {
        private const val CAMERA_KEY = "speech.cameraOn"
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

        /**
         * A piece's words, from two witnesses (iOS `pieceText`). The read-back
         * is the text the take is scored on, but it can come back short: when
         * Azure heard the piece and the read-back holds under 70% of its words
         * (or nothing), Azure's own text is the piece's text. With no Azure
         * text the read-back stands, null included.
         */
        fun pieceText(readBack: String?, heard: String?, language: String): Pair<String, Boolean>? {
            val read = readBack?.trim().orEmpty()
            val azure = heard?.trim().orEmpty()
            if (azure.isEmpty()) return readBack?.let { it to false }
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
                    metrics: SpeechMetrics, delivery: SpeechDelivery): SpeechReadingScore? {
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
            )
        }

        /** The take's pronunciation from its pieces: the SOUND score weighted
         *  by each piece's judged words, and every faulted word, worst first
         *  (at most 12). Null when no piece was assessed. */
        fun pronunciation(pieces: List<PronunciationResult>): Pair<Int, List<PronunciationResult.Word>>? {
            val weighted = pieces.map { it.soundScore to maxOf(1, it.judgedWords.size) }
            val total = weighted.sumOf { it.second }
            if (total <= 0) return null
            val score = weighted.sumOf { it.first * it.second } / total
            val weak = pieces.flatMap { it.weakWords }.sortedBy { it.accuracy ?: 0 }
            return score to weak.take(12)
        }
    }
}
