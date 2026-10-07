package com.roro.futurevoice.ui

import android.Manifest
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Notes
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.AvTimer
import androidx.compose.material.icons.filled.Bookmark
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.GraphicEq
import androidx.compose.material.icons.filled.Groups
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.MicOff
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material.icons.filled.PlayCircleOutline
import androidx.compose.material.icons.filled.RecordVoiceOver
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Speed
import androidx.compose.material.icons.filled.VolumeOff
import androidx.compose.material.icons.outlined.BookmarkBorder
import androidx.compose.material3.AlertDialog
import com.roro.futurevoice.ui.brand.IosButton as Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import com.roro.futurevoice.R
import com.roro.futurevoice.audio.AudioDecode
import com.roro.futurevoice.audio.AudioOnset
import com.roro.futurevoice.audio.DuetPlayer
import com.roro.futurevoice.audio.Mp3Player
import com.roro.futurevoice.audio.TargetPlayer
import com.roro.futurevoice.audio.WavPcm
import com.roro.futurevoice.audio.WavRecorder
import com.roro.futurevoice.core.InstallSalt
import com.roro.futurevoice.data.AuthRepository
import com.roro.futurevoice.data.BillingGate
import com.roro.futurevoice.data.MicPreference
import com.roro.futurevoice.data.PhraseAudioStore
import com.roro.futurevoice.data.Recency
import com.roro.futurevoice.data.SavedLine
import com.roro.futurevoice.data.SavedLineStore
import com.roro.futurevoice.data.ShadowAttempt
import com.roro.futurevoice.data.ShadowAttemptStore
import com.roro.futurevoice.data.StoreJson
import com.roro.futurevoice.data.WordSplitter
import com.roro.futurevoice.net.EdgeError
import com.roro.futurevoice.net.ElevenLabsClient
import com.roro.futurevoice.net.GeminiClient
import com.roro.futurevoice.talk.ShadowCoachPrompt
import com.roro.futurevoice.talk.ShadowScore
import com.roro.futurevoice.talk.ShadowTiming
import com.roro.futurevoice.talk.ShadowTranscriber
import com.roro.futurevoice.talk.TtsAlignment
import com.roro.futurevoice.talk.WordTiming
import com.roro.futurevoice.talk.WordTimings
import com.roro.futurevoice.ui.brand.IosGlassButton
import com.roro.futurevoice.ui.brand.IosGlassTextButton
import com.roro.futurevoice.ui.brand.iosFill
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.async
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import java.io.File
import java.util.Locale
import kotlin.math.abs

/**
 * Shadow one line — iOS `ShadowDrillView`, element for element.
 *
 * Tap the mic → 3-2-1-0 → the line's words light up on the model's rhythm
 * while the learner says it along (nothing plays — speaker audio would bleed
 * into the mic). The take is recorded, read from the audio
 * (`ShadowTranscriber`), diffed against the line (`ShadowScore`), its beat
 * drawn as dots under the words, and the coach writes three bullets anchored
 * to that diff — AFTER the score is up. Words are tappable: two taps pick a
 * phrase; the trimmer below loops it.
 *
 * Where the timings come from: the model line's from ElevenLabs' alignment,
 * kept from the one synthesis that billed it (`PhraseAudioStore`); a line
 * cached without them is estimated, and an estimate is never graded. The
 * learner's from aligning the take to the model line (`TakeAligner`) — iOS
 * reads them off Apple's recognizer, which Android has no file-timing
 * equivalent of (plan 2.9).
 */
private enum class ShadowPhase { IDLE, LOADING_AUDIO, COUNTDOWN, RECORDING, ANALYZING, RESULT,
    /** Android only: the take was made but nothing could READ it. iOS falls
     *  back to Apple's pass; here nothing is scored on a reading nobody has. */
    READ_FAILED }

/**
 * The coach call outlives the screen: closing it right after a take must not
 * cost the RECORD its bullets (iOS's unstructured Task carries on the same
 * way). What lands after the screen is gone only updates the store.
 */
private val coachScope = kotlinx.coroutines.CoroutineScope(
    kotlinx.coroutines.SupervisorJob() + Dispatchers.Main)

/** iOS `ShadowDrillView.stillSpeakingSeconds` — a breath is 0.5–1.5 s. */
internal const val STILL_SPEAKING_MS = 1_500L
/** The pause that ends an attempt once the line's last words were heard (iOS `endOfLineQuietSeconds`). */
internal const val END_OF_LINE_QUIET_MS = 600L

/** Mic level (the recorder's own 0…1 curve) that counts as someone talking. */
internal const val VOICED_LEVEL = 0.35f

/** iOS `durationFromText` — only ever sizes a SAFETY cutoff, so it errs long. */
private fun durationFromText(wordCount: Int): Int = maxOf(6_000, wordCount * 400)

/** iOS `attemptCutoffMs` — learners run long by a FACTOR, not a constant. */
internal fun attemptCutoffMs(targetMs: Int): Int =
    maxOf(3_000, (targetMs * 1.5).toInt() + 2_500)

/** What the coach writes; empty fields until (or unless) it does. */
private data class ShadowFeedback(
    val pronunciation: String, val pacing: String, val fix: String,
    val matchScore: Int, val rhythmScore: Int?,
) { val overallScore: Int get() = ShadowScore.overallScore(matchScore, rhythmScore) }

@Serializable
private data class CoachPayload(val pronunciation: String = "", val pacing: String = "", val fix: String = "")

/**
 * A finished take, handed in by the capture harness — iOS's harness can't
 * reach a result (no mic in a capture run), so these states are seeded here
 * and checked against the Swift view's code.
 */
data class ShadowSeed(
    val targetTimings: List<WordTiming>,
    val learnerText: String,
    val learnerTimings: List<WordTiming>,
    val learnerDurationMs: Int,
    val coachPending: Boolean = false,
    val pronunciation: String = "",
    val pacing: String = "",
    val fix: String = "",
    val past: List<ShadowAttempt> = emptyList(),
)

@OptIn(ExperimentalLayoutApi::class, ExperimentalFoundationApi::class)
@Composable
fun ShadowScreen(
    line: String,
    voiceId: String,
    targetLanguage: String,
    onBack: () -> Unit,
    /** The line's origin turn, when it came from a talk. */
    turnId: String? = null,
    /** Position in today's hand, for the header. Null = a one-off line. */
    position: Pair<Int, Int>? = null,
    /** Move to the next line of the hand. Null = this is the last one. */
    onNext: (() -> Unit)? = null,
    /** Capture only. */
    seed: ShadowSeed? = null,
) {
    NavCoverGuard()
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val target = remember { TargetPlayer() }
    val takePlayer = remember { Mp3Player(context.cacheDir, source = "shadow") }
    val recorder = remember { WavRecorder() }
    val attempts = remember { ShadowAttemptStore.shared(context) }
    /** One id per line, so attempts of a line with no turn still group — a
     *  UUID, because iOS decodes `turnId` as one (a backup crosses over). */
    val lineId = remember(turnId, line) {
        turnId ?: java.util.UUID.nameUUIDFromBytes(line.toByteArray()).toString().uppercase()
    }

    var phase by remember { mutableStateOf(ShadowPhase.IDLE) }
    var countdown by remember { mutableIntStateOf(0) }
    var error by remember { mutableStateOf<String?>(null) }
    var outOfCredits by remember { mutableStateOf(false) }
    var heardNothing by remember { mutableStateOf(false) }

    // ---- the model line
    var targetFile by remember { mutableStateOf<File?>(null) }
    var targetDurationMs by remember { mutableIntStateOf(0) }
    var timings by remember { mutableStateOf<List<WordTiming>>(emptyList()) }
    var targetPcm by remember { mutableStateOf<Deferred<WavPcm?>?>(null) }

    // ---- selection
    var selection by remember { mutableStateOf<IntRange?>(null) }
    var anchor by remember { mutableStateOf<Int?>(null) }
    var activeRange by remember { mutableStateOf<IntRange?>(null) }
    var attemptTargetText by remember { mutableStateOf("") }
    var attemptTargetDurationMs by remember { mutableIntStateOf(0) }

    // ---- the result
    var steps by remember { mutableStateOf<List<ShadowScore.DiffStep>>(emptyList()) }
    var rhythm by remember { mutableStateOf<ShadowScore.RhythmAnalysis?>(null) }
    var said by remember { mutableStateOf("") }
    var feedback by remember { mutableStateOf<ShadowFeedback?>(null) }
    var coachPending by remember { mutableStateOf(false) }
    var shownAttemptId by remember { mutableStateOf<String?>(null) }
    var takeRecording by remember { mutableStateOf<String?>(null) }
    var learnerTimings by remember { mutableStateOf<List<WordTiming>>(emptyList()) }
    var lastAttemptDurationMs by remember { mutableIntStateOf(0) }
    var saved by remember { mutableStateOf(false) }
    var past by remember { mutableStateOf<List<ShadowAttempt>>(emptyList()) }
    var reload by remember { mutableIntStateOf(0) }
    var take by remember { mutableStateOf<Job?>(null) }
    var syncStartedAt by remember { mutableLongStateOf(0L) }
    var askingMic by remember { mutableStateOf<CompletableDeferred<Unit>?>(null) }
    /** Redraw clock for the karaoke (30 Hz while something moves). */
    var tick by remember { mutableLongStateOf(0L) }

    val recordingNow = phase == ShadowPhase.RECORDING || phase == ShadowPhase.COUNTDOWN
    androidx.activity.compose.BackHandler(enabled = !recordingNow, onBack = onBack)
    // Mid-take the gesture is held as well: leaving would discard an attempt
    // that is still being made.
    androidx.activity.compose.BackHandler(enabled = recordingNow) {}

    val words: List<String> = remember(timings, line, targetLanguage) {
        if (timings.isNotEmpty()) timings.map { it.word } else WordSplitter.timingWords(line, targetLanguage)
    }
    val spaced = WordSplitter.spaced(targetLanguage)
    val practiceRange = selection?.takeIf { r ->
        timings.isNotEmpty() && r.last < timings.size && !(r.first == 0 && r.last == timings.lastIndex)
    }
    val practiceText = practiceRange?.let { r -> timings.slice(r).joinToString(if (spaced) " " else "") { it.word } } ?: line
    /** First word to last — the span a take's own duration is measured
     *  against (the FILE length carried a silent tail, so a matching take read
     *  0.83× and was called rushed). */
    val practiceDurationMs = when {
        practiceRange != null -> maxOf(0, timings[practiceRange.last].endMs - timings[practiceRange.first].startMs)
        timings.isNotEmpty() -> maxOf(0, timings.last().endMs - timings.first().startMs)
        else -> targetDurationMs
    }

    // ---- word verdicts, folded once per result (never per frame)
    val wordOps: Map<Int, ShadowScore.DiffOp> = remember(steps, activeRange, timings) {
        positionAlignment(steps, activeRange?.let { timings.slice(it).map { t -> t.word } } ?: words, targetLanguage)
    }
    val wordBeats: Map<Int, ShadowScore.RhythmWord> = remember(rhythm, activeRange) {
        val base = activeRange?.first ?: 0
        rhythm?.words?.associateBy { it.targetIndex + base }.orEmpty()
    }

    // ---- prepare the model line
    LaunchedEffect(line, voiceId) {
        if (seed != null) {
            timings = seed.targetTimings
            targetDurationMs = seed.targetTimings.lastOrNull()?.endMs ?: 0
            attemptTargetText = line
            attemptTargetDurationMs = seed.targetTimings.let { t ->
                if (t.isEmpty()) 0 else t.last().endMs - t.first().startMs }
            val a = ShadowScore.analyze(line, seed.learnerText, targetLanguage)
            steps = a.steps
            said = seed.learnerText
            learnerTimings = seed.learnerTimings
            rhythm = ShadowScore.analyzeRhythm(a.steps, seed.targetTimings, seed.learnerTimings, targetLanguage)
            lastAttemptDurationMs = seed.learnerDurationMs
            val overall = ShadowScore.overallScore(a.score, rhythm?.score)
            feedback = ShadowFeedback(
                if (overall >= 90) context.getString(if (rhythm == null)
                    R.string.nailed_it_matched_the_line_almost_word_for_word
                else R.string.nailed_it_matched_the_line_almost_word_for_word_on_the_beat)
                else seed.pronunciation, seed.pacing, seed.fix, a.score, rhythm?.score)
            coachPending = seed.coachPending
            takeRecording = "seed"
            past = seed.past
            phase = ShadowPhase.RESULT
            return@LaunchedEffect
        }
        if (voiceId.isBlank()) {
            // Capture seam (iOS `captureShadow`): evenly spaced timings, no
            // network, a loop region showing.
            val ws = WordSplitter.timingWords(line, targetLanguage)
            timings = ws.mapIndexed { i, w -> WordTiming(w, i * 380, (i + 1) * 380 - 60) }
            targetDurationMs = ws.size * 380
            if (ws.size >= 5) selection = 2..4
            return@LaunchedEffect
        }
        val store = PhraseAudioStore.shared(context)
        var audio = withContext(Dispatchers.IO) { store.data(line, voiceId) }
        var stored = withContext(Dispatchers.IO) { store.timings(line, voiceId) }.orEmpty()
        if (audio == null) {
            // The FIRST synthesis of this line — the one place a shadow open
            // may bill — fetches its timings in the same call.
            phase = ShadowPhase.LOADING_AUDIO
            try {
                val (a, t) = ElevenLabsClient(AuthRepository()).synthesizeWithTimestamps(
                    voiceId = voiceId, text = line, language = targetLanguage,
                    idempotencyKey = InstallSalt.ttsKey(line, voiceId, timestamps = true),
                    purpose = "shadow")
                withContext(Dispatchers.IO) { store.save(a, line, voiceId); store.saveTimings(t, line, voiceId) }
                audio = a; stored = t
            } catch (e: Exception) {
                outOfCredits = e === EdgeError.InsufficientCredits
                // The 402 leads with the plans (the alert's See plans); any
                // other failure says what broke.
                error = context.getString(R.string.couldn_t_load_audio_for_this_line) +
                    if (outOfCredits) "" else " " + (e.message ?: "")
                phase = ShadowPhase.IDLE
                return@LaunchedEffect
            }
        }
        val bytes = audio ?: return@LaunchedEffect
        val file = withContext(Dispatchers.IO) {
            // The key is `tts:<install>:<hash>` — a colon in a path makes
            // MediaPlayer / MediaMetadataRetriever read it as a URI scheme
            // and fail (error 1, a 0.1 s timeline) on every real device line.
            File(context.cacheDir, "shadow-target-${InstallSalt.ttsKey(line, voiceId, false).replace(':', '_')}.mp3")
                .also { it.writeBytes(bytes) }
        }
        val duration = withContext(Dispatchers.IO) { mediaDurationMs(file) }
        targetDurationMs = duration
        // Audio already on disk is NEVER re-billed for timings: stored ones
        // when they describe THIS take, else the estimate (never graded).
        timings = if (TtsAlignment.alignmentMatches(line, stored) && WordTimings.fits(stored, duration) &&
            WordTimings.cutMatches(stored, line, targetLanguage)) stored
        else WordTimings.estimate(line, duration, targetLanguage)
        targetFile = file
        targetPcm = scope.async(Dispatchers.Default) { AudioDecode.decode(bytes) }
        phase = ShadowPhase.IDLE
    }
    LaunchedEffect(lineId) {
        saved = turnId != null && SavedLineStore.shared(context).isSaved(turnId)
    }
    LaunchedEffect(lineId, reload) {
        if (seed != null) return@LaunchedEffect
        past = attempts.load(targetLanguage).filter { it.turnId == lineId }.sortedByDescending { it.createdAt }
    }
    // The karaoke's clock: on while a take runs or the line plays.
    LaunchedEffect(phase) {
        while (isActive) { tick = System.currentTimeMillis(); delay(33) }
    }
    DisposableEffect(Unit) {
        onDispose {
            take?.cancel(); target.release(); takePlayer.stop(); DuetPlayer.stop()
            runCatching { recorder.stop() }
        }
    }

    fun resetResult() {
        feedback = null; heardNothing = false; coachPending = false; shownAttemptId = null
        steps = emptyList(); rhythm = null; learnerTimings = emptyList()
    }

    fun cancelTake() {
        // CANCEL, not stop: ending a take is the auto-stop's job. Mid-attempt
        // this button means "throw this one away" — nothing scored or kept.
        take?.cancel(); take = null
        runCatching { recorder.stop() }
        takeRecording?.let { runCatching { File(it).delete() } }
        takeRecording = null
        said = ""; activeRange = null
        resetResult()
        phase = ShadowPhase.IDLE
        HapticEngine.selection(context)
        com.roro.futurevoice.core.Telemetry.log("shadow_attempt_cancelled")
    }

    suspend fun coach(attempt: ShadowAttempt, scoredText: String, analysis: ShadowScore.Analysis,
                      r: ShadowScore.RhythmAnalysis?, learnerDurMs: Int) {
        val started = System.currentTimeMillis()
        val native = context.getSharedPreferences("futurevoice", 0)
            .getString("futurevoice.nativeLanguage", null) ?: "en"
        val payload = runCatching {
            GeminiClient(AuthRepository()).sendJson(
                system = ShadowCoachPrompt.system(targetLanguage, native),
                messages = listOf(GeminiClient.Message(
                    role = GeminiClient.Message.Role.USER,
                    content = ShadowCoachPrompt.userMessage(attemptTargetText, scoredText,
                        attemptTargetDurationMs, learnerDurMs, analysis.steps, r))),
                serializer = CoachPayload.serializer(),
                // Three native-language bullets — 300 left no room for
                // thinking, and a truncation drops the feedback entirely.
                maxTokens = 1024,
                purpose = "shadow",
            )
        }.getOrNull()
        com.roro.futurevoice.core.Telemetry.log("shadow_coach", mapOf(
            "outcome" to if (payload == null) "failed" else "ok",
            "ms" to (System.currentTimeMillis() - started).toString()))
        if (payload != null) {
            attempts.update(attempt.copy(pronunciation = payload.pronunciation,
                pacing = payload.pacing, fix = payload.fix), targetLanguage)
            reload += 1
        }
        // The learner may have started the next take meanwhile; the record
        // above is theirs either way, the screen is not.
        if (shownAttemptId != attempt.id) return
        coachPending = false
        feedback = feedback?.copy(
            pronunciation = payload?.pronunciation ?: context.getString(
                R.string.coach_comments_couldn_t_load_the_score_and_highlighted_words_ae7868),
            pacing = payload?.pacing.orEmpty(), fix = payload?.fix.orEmpty())
    }

    fun runTake() {
        target.stop(); takePlayer.stop(); DuetPlayer.stop()
        take = scope.launch {
            // One-time "which mic?" — before the countdown, so the answer
            // governs this very take.
            if (MicPreference.shouldAsk(context)) {
                val wait = CompletableDeferred<Unit>()
                askingMic = wait
                wait.await()
            }
            MicPreference.applyInputRoute(context)
            com.roro.futurevoice.core.Telemetry.log("shadow_attempt_started", mapOf(
                "target_measured" to if (timings.any { it.isMeasured }) "1" else "0"))
            // Freeze what this take practices: the phrase, or the line.
            activeRange = practiceRange
            attemptTargetText = practiceText
            attemptTargetDurationMs = practiceDurationMs
            val range = practiceRange
            resetResult()
            said = ""
            takeRecording = null
            val takeFile = File(File(context.filesDir, "shadow-takes"), StoreJson.newId() + ".wav")
            // "3" goes up FIRST, and the mic is set up while it shows (iOS
            // 34eca23a): opening the recorder holds the main thread for a
            // beat, and it used to run before the count began — a blank pause
            // after the tap. The pause before "2" shrinks by whatever the
            // setup took, so the count is as long as ever.
            val countStartedAt = System.currentTimeMillis()
            phase = ShadowPhase.COUNTDOWN
            countdown = 3
            HapticEngine.countdownTick(context)
            delay(30)   // let "3" draw first
            // The mic is up before "2", and anything before "0" is cut from
            // the file afterwards (iOS records from the go beat — the 3-2-1
            // never reaches the scored audio or the take played back).
            // The live recognizer, for ending the attempt on CONTENT (iOS
            // `a4fa2dc6`). Opened BEFORE the recorder: where a device can't
            // feed two mic users, the later one wins, and the scored file
            // must be the one that does.
            var heard = ""
            val live = runCatching {
                com.roro.futurevoice.audio.LiveTranscriber(context).also {
                    it.start(com.roro.futurevoice.data.LanguageCatalog.sttLocale(targetLanguage)) { t -> heard = t }
                }
            }.getOrNull()
            // A take cancelled mid-count (closing the screen) must not leave
            // the recognizer listening. Stopping twice is harmless.
            kotlin.coroutines.coroutineContext[kotlinx.coroutines.Job]?.invokeOnCompletion {
                android.os.Handler(android.os.Looper.getMainLooper()).post { runCatching { live?.stop() } }
            }
            if (runCatching { recorder.start(takeFile) }.isFailure) {
                runCatching { live?.stop() }
                error = context.getString(R.string.microphone_or_speech_permission_denied)
                countdown = 0
                phase = ShadowPhase.IDLE
                return@launch
            }
            delay(maxOf(0L, 700L - (System.currentTimeMillis() - countStartedAt)))
            for (n in 2 downTo 1) {
                countdown = n
                HapticEngine.countdownTick(context)
                delay(700)
            }
            countdown = 0
            val goSeconds = recorder.elapsedSeconds
            HapticEngine.countdownGo(context)
            delay(350)

            syncStartedAt = System.currentTimeMillis()
            phase = ShadowPhase.RECORDING
            val targetMs = if (attemptTargetDurationMs > 0) attemptTargetDurationMs else durationFromText(words.size)
            val earliest = syncStartedAt + maxOf(1_000, targetMs)
            val hardStop = syncStartedAt + attemptCutoffMs(targetMs)
            // Two ways the attempt ends, whichever comes first (iOS
            // `a4fa2dc6`): by CONTENT — the recognizer heard the line's last
            // words and they paused 0.6 s (a room that keeps the level up used
            // to hold attempts open to the ceiling); by SILENCE — past the
            // line's own length, 1.5 s of quiet (a breath runs 0.5–1.5 s).
            var lastVoiced = syncStartedAt
            var liveOn = live != null
            try {
                while (System.currentTimeMillis() < hardStop) {
                    val now = System.currentTimeMillis()
                    if (recorder.level >= VOICED_LEVEL) lastVoiced = now
                    val quiet = now - lastVoiced
                    if (liveOn && quiet >= END_OF_LINE_QUIET_MS &&
                        ShadowScore.heardLineEnd(attemptTargetText, heard, targetLanguage)) break
                    if (now >= earliest && quiet >= STILL_SPEAKING_MS) break
                    // The system gave the mic to the recognizer: keep the take.
                    if (liveOn && recorder.isSilenced(context)) { runCatching { live?.stop() }; liveOn = false }
                    delay(100)
                }
            } finally {
                runCatching { live?.stop() }
            }
            val wallMs = (System.currentTimeMillis() - syncStartedAt).toInt()

            phase = ShadowPhase.ANALYZING
            delay(300)   // tail grace: the last syllable is still arriving
            runCatching { recorder.stop() }
            withContext(Dispatchers.IO) { trimLeading(takeFile, goSeconds) }
            val read = ShadowTranscriber.read(takeFile, targetLanguage)
            if (read.source == ShadowTranscriber.Source.FAILED && read.text.isEmpty() && takeFile.length() > 44L) {
                logTranscript(read, range, timed = false)
                takeRecording = takeFile.absolutePath
                phase = ShadowPhase.READ_FAILED
                return@launch
            }
            val text = read.text
            said = text
            // A take with no speech is not a 0 — it is nothing: not saved,
            // counted or coached.
            if (text.isBlank()) {
                logTranscript(read, range, timed = false)
                heardNothing = true
                takeFile.delete()
                phase = ShadowPhase.RESULT
                com.roro.futurevoice.core.Telemetry.log("shadow_heard_nothing", mapOf("source" to read.source.name.lowercase()))
                return@launch
            }
            val analysis = ShadowScore.analyze(attemptTargetText, text, targetLanguage)
            val targetSlice = range?.let { timings.slice(it) } ?: timings
            val takePcm = withContext(Dispatchers.IO) { WavPcm.read(takeFile) }
            val pcm = targetPcm?.await()
            val learner = withContext(Dispatchers.Default) {
                if (takePcm == null) ShadowTiming.Learner(emptyList(), 0)
                else ShadowTiming.learner(pcm, targetSlice, takePcm, text, analysis.steps, targetLanguage)
            }
            logTranscript(read, range, timed = learner.timings.isNotEmpty())
            val r = ShadowScore.analyzeRhythm(analysis.steps, targetSlice, learner.timings, targetLanguage)
            steps = analysis.steps
            rhythm = r
            learnerTimings = learner.timings
            // The scored words' own span first (it cannot carry anything
            // before the first word), then the take's voiced span, then wall.
            val scoredSpan = learner.timings.firstOrNull()?.let { f ->
                maxOf(0, learner.timings.last().endMs - f.startMs) } ?: 0
            val learnerDurMs = when {
                scoredSpan > 0 -> scoredSpan
                learner.voicedSpanMs > 0 -> minOf(learner.voicedSpanMs, wallMs)
                else -> wallMs
            }
            lastAttemptDurationMs = learnerDurMs

            // Coach only when there is something to coach — judged on the
            // number the learner is JUDGED by, words and beat.
            val overall = ShadowScore.overallScore(analysis.score, r?.score)
            val coachable = overall < 90
            feedback = ShadowFeedback(
                pronunciation = if (coachable) "" else context.getString(if (r == null)
                    R.string.nailed_it_matched_the_line_almost_word_for_word
                else R.string.nailed_it_matched_the_line_almost_word_for_word_on_the_beat),
                pacing = "", fix = "", matchScore = analysis.score, rhythmScore = r?.score)
            coachPending = coachable
            takeRecording = takeFile.absolutePath
            phase = ShadowPhase.RESULT
            HapticEngine.shadowComplete(context, overall)
            com.roro.futurevoice.core.Analytics.capture("shadow_attempted", mapOf("score" to overall))

            // Saved BEFORE the coach call, so an attempt whose bullets never
            // come is still on file with its score and recording.
            val attempt = ShadowAttempt(
                turnId = lineId,
                targetText = attemptTargetText,
                learnerTranscript = text,
                matchScore = analysis.score,
                rhythmScore = r?.score,
                pronunciation = feedback?.pronunciation.orEmpty(),
                phraseFirst = range?.first,
                phraseLast = range?.last,
                recordingFilename = takeFile.absolutePath,
            )
            shownAttemptId = attempt.id
            attempts.add(attempt, targetLanguage)
            com.roro.futurevoice.data.PracticeLog.record(
                context, com.roro.futurevoice.data.PracticeLog.Kind.SHADOW, finished = true)
            reload += 1
            if (coachable) {
                // Its own job: a retry tapped meanwhile must not cancel the
                // record's bullets, only keep them off the new screen.
                coachScope.launch { coach(attempt, text, analysis, r, learnerDurMs) }
            }
        }
    }

    val micPermission = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted -> if (granted) runTake() else error = context.getString(R.string.microphone_or_speech_permission_denied) }

    fun onMicTap() {
        when (phase) {
            ShadowPhase.IDLE, ShadowPhase.RESULT, ShadowPhase.READ_FAILED -> {
                val ok = ContextCompat.checkSelfPermission(
                    context, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
                if (ok) runTake() else micPermission.launch(Manifest.permission.RECORD_AUDIO)
            }
            ShadowPhase.RECORDING -> cancelTake()
            else -> Unit
        }
    }

    fun tapWord(i: Int) {
        if (phase != ShadowPhase.IDLE && phase != ShadowPhase.RESULT && phase != ShadowPhase.READ_FAILED) return
        if (selection?.first == i && selection?.last == i) { selection = null; anchor = null; return }
        if (selection == null) anchor = null
        val a = anchor
        if (a != null) { selection = minOf(a, i)..maxOf(a, i); anchor = null }
        else { anchor = i; selection = i..i }
    }

    fun playTake(path: String) {
        target.pause(); DuetPlayer.stop()
        scope.launch {
            if (!File(path).exists()) { error = context.getString(R.string.recording_isn_t_available); return@launch }
            runCatching { takePlayer.play(File(path)) }
        }
    }

    fun previewTarget() {
        takePlayer.stop(); DuetPlayer.stop()
        val f = targetFile ?: run { error = context.getString(R.string.couldn_t_load_audio_for_this_line); return }
        target.load(f)
        target.playSegment(0, null, loop = false)
    }

    /**
     * The model line and the take AT ONCE, each skipped to its own first
     * word — onsets by EAR (`AudioOnset`), because word timings are missing
     * whenever a take couldn't be aligned and an estimated target starts at
     * 0 while every render opens on silence. A phrase is the one case timings
     * decide: its start is mid-file, not the first sound in it.
     */
    fun playTogether() {
        target.stop(); takePlayer.stop()
        val takePath = takeRecording ?: run { error = context.getString(R.string.recording_isn_t_available); return }
        scope.launch {
            val takePcm = withContext(Dispatchers.IO) { WavPcm.read(File(takePath)) }
            val pcm = targetPcm?.await()
            if (takePcm == null) { error = context.getString(R.string.recording_isn_t_available); return@launch }
            if (pcm == null) { error = context.getString(R.string.couldn_t_load_audio_for_this_line); return@launch }
            val slice = activeRange?.let { timings.slice(it) } ?: timings
            val targetLead = if (activeRange != null) slice.firstOrNull()?.startMs ?: 0
            else AudioOnset.firstVoiceOnset(pcm.samples, pcm.sampleRate)?.let { (it * 1000).toInt() }
                ?: slice.firstOrNull()?.startMs ?: 0
            val takeLead = AudioOnset.firstVoiceOnset(takePcm.samples, takePcm.sampleRate)?.let { (it * 1000).toInt() }
                ?: learnerTimings.firstOrNull()?.startMs ?: 0
            val ok = withContext(Dispatchers.Default) { DuetPlayer.play(pcm, targetLead, takePcm, takeLead) }
            if (!ok) error = context.getString(R.string.couldn_t_play_the_two_takes_together)
        }
    }

    val dark = isSystemInDarkTheme()
    val page = MaterialTheme.colorScheme.surface
    val cell = if (dark) MaterialTheme.colorScheme.surfaceContainerHigh else MaterialTheme.colorScheme.surfaceContainer
    val secondary = MaterialTheme.colorScheme.onSurfaceVariant
    val tertiary = secondary.copy(alpha = 0.6f)
    val timelineAvailable = (phase == ShadowPhase.IDLE || phase == ShadowPhase.RESULT ||
        phase == ShadowPhase.READ_FAILED) && targetFile?.exists() == true

    Box(Modifier.fillMaxSize().background(page)) {
        Column(Modifier.fillMaxSize()) {
            SheetHeader(
                title = stringResource(R.string.shadow) + (position?.let { (i, n) ->
                    "  " + stringResource(R.string.lld_of_lld, i, n) } ?: ""),
                // "Close", not "Done": nothing here gets finished by leaving.
                leading = {
                    IosGlassTextButton(stringResource(R.string.close),
                        onClick = { if (!recordingNow) { target.stop(); onBack() } },
                        modifier = Modifier.alpha(if (recordingNow) 0.4f else 1f))
                },
                trailing = if (turnId != null) ({
                    IosGlassButton(onClick = {
                        scope.launch { saved = SavedLineStore.shared(context).toggle(SavedLine(id = turnId, text = line)) }
                    }, circle = true) {
                        Icon(if (saved) Icons.Filled.Bookmark else Icons.Outlined.BookmarkBorder,
                            contentDescription = stringResource(if (saved) R.string.remove_from_saved_lines else R.string.save_line),
                            tint = MaterialTheme.colorScheme.primary)
                    }
                }) else null,
                modifier = Modifier.statusBarsPadding().padding(horizontal = 16.dp).padding(top = 8.dp, bottom = 4.dp),
            )
            Column(
                Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState())
                    .padding(horizontal = 20.dp).padding(top = 16.dp, bottom = 24.dp),
                verticalArrangement = Arrangement.spacedBy(20.dp),
            ) {
                // ---- target line
                TargetLineSection(line, timings, selection, activeRange, practiceRange != null, rhythm, steps,
                    wordOps, wordBeats, spaced, phase, syncStartedAt, target, tick, ::tapWord)

                // ---- durations (after analysis only)
                if (steps.isNotEmpty() && attemptTargetDurationMs > 0) {
                    val targetSec = attemptTargetDurationMs / 1000.0
                    val yourSec = maxOf(0, lastAttemptDurationMs) / 1000.0
                    val ratio = if (targetSec > 0) yourSec / targetSec else 0.0
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        DurationCell(stringResource(R.string.target), secondsLabel(targetSec), cell, Modifier.weight(1f))
                        DurationCell(stringResource(R.string.you), secondsLabel(yourSec), cell, Modifier.weight(1f))
                        DurationCell(stringResource(R.string.pace), paceLabel(ratio), cell, Modifier.weight(1f),
                            color = paceColor(ratio))
                    }
                }

                if (heardNothing) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        Icon(Icons.Filled.MicOff, null, Modifier.size(16.dp), tint = secondary)
                        Text(stringResource(R.string.didn_t_hear_anything_try_again_closer_to_the_mic),
                            style = MaterialTheme.typography.bodySmall, color = secondary)
                    }
                }

                if (phase == ShadowPhase.READ_FAILED) {
                    Text(stringResource(R.string.couldn_t_score_that_one_your_take_is_still_here),
                        style = MaterialTheme.typography.bodyMedium, color = secondary)
                    takeRecording?.let { path ->
                        BorderedButton(stringResource(R.string.hear_my_attempt), Icons.Filled.RecordVoiceOver,
                            Modifier.fillMaxWidth()) { playTake(path) }
                    }
                }

                // ---- your take
                feedback?.let { fb ->
                    TakeSection(fb, steps, said, takeRecording != null, coachPending,
                        onHearTarget = ::previewTarget,
                        onHearTake = { takeRecording?.let { playTake(it) } },
                        onTogether = ::playTogether)
                }

                // Android's hand: only after a score — moving on before saying
                // it would make the hand a list to click through.
                if (feedback != null && onNext != null) {
                    Button(onClick = onNext, modifier = Modifier.fillMaxWidth()) { Text(stringResource(R.string.next)) }
                }

                // ---- past attempts (the take on screen is the card above)
                val shownPast = past.filter { it.id != shownAttemptId }
                if (shownPast.isNotEmpty()) {
                    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        Row(Modifier.fillMaxWidth()) {
                            Text(stringResource(R.string.past_attempts), style = MaterialTheme.typography.labelMedium, color = secondary)
                            Spacer(Modifier.weight(1f))
                            Text(stringResource(R.string.lld_total, shownPast.size), style = MaterialTheme.typography.labelSmall, color = tertiary)
                        }
                        shownPast.forEach { a ->
                            PastAttemptRow(a, cell, onPlay = { playTake(it) }, onDelete = {
                                scope.launch { attempts.delete(a.id, targetLanguage); reload += 1 }
                            })
                        }
                    }
                }
                Spacer(Modifier.height(if (timelineAvailable) 230.dp else 110.dp))
            }
        }

        // ---- bottom panel
        Column(Modifier.align(Alignment.BottomCenter).fillMaxWidth()) {
            ScrollEdgeFeather(color = page, ramp = 56.dp, solid = 0.dp,
                modifier = Modifier.height(56.dp))
            Box(Modifier.fillMaxWidth().background(page).bottomBarInsets()
                .padding(horizontal = 8.dp).padding(top = 0.dp, bottom = 8.dp),
                contentAlignment = Alignment.Center) {
                val f = targetFile
                if (timelineAvailable && f != null) {
                    ShadowTimeline(audio = f, timings = timings, selection = selection,
                        onSelection = { selection = it; anchor = null }, player = target) {
                        MicButton(phase, practiceRange != null, 60.dp, onTap = { onMicTap() })
                    }
                } else {
                    MicButton(phase, practiceRange != null, 64.dp, onTap = { onMicTap() })
                }
            }
        }

        if (phase == ShadowPhase.COUNTDOWN) {
            Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.5f)),
                contentAlignment = Alignment.Center) {
                Text("$countdown", fontSize = 120.sp, fontWeight = FontWeight.Black, color = Color.White)
            }
        }
    }

    askingMic?.let { wait ->
        MicChoiceSheet(onChoose = { choice ->
            MicPreference.set(context, choice)
            askingMic = null
            wait.complete(Unit)
        })
    }

    error?.let { message ->
        AlertDialog(
            onDismissRequest = { error = null },
            title = { Text(stringResource(R.string.something_went_wrong)) },
            text = { Text(message) },
            confirmButton = { TextButton(onClick = { error = null }) { Text(stringResource(R.string.ok)) } },
            dismissButton = if (outOfCredits) ({
                TextButton(onClick = { error = null; BillingGate.showPaywall.value = true }) {
                    Text(stringResource(R.string.see_plans))
                }
            }) else null,
        )
    }
}

private fun logTranscript(read: ShadowTranscriber.Read, range: IntRange?, timed: Boolean) {
    com.roro.futurevoice.core.Telemetry.log("shadow_transcript", mapOf(
        "source" to read.source.name.lowercase(),
        "audio_ms" to read.ms.toString(),
        "partial" to if (range != null) "1" else "0",
        "timed" to if (timed) "1" else "0",
        "timing" to "take_align"))
}

/** Cut everything before the go beat out of the take (the countdown). */
private fun trimLeading(file: File, seconds: Double) {
    if (seconds <= 0) return
    val pcm = WavPcm.read(file) ?: return
    val from = (seconds * pcm.sampleRate).toInt().coerceIn(0, pcm.samples.size)
    file.writeBytes(WavPcm.wav(pcm.samples.copyOfRange(from, pcm.samples.size), pcm.sampleRate))
}

private fun mediaDurationMs(file: File): Int = runCatching {
    val r = android.media.MediaMetadataRetriever()
    try {
        r.setDataSource(file.absolutePath)
        r.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_DURATION)?.toInt() ?: 0
    } finally { r.release() }
}.getOrDefault(0)

/** Each target word's diff op — iOS `positionAlignment`: if the token
 *  stream and the word spans don't account for each other, nothing. */
private fun positionAlignment(
    steps: List<ShadowScore.DiffStep>, words: List<String>, language: String,
): Map<Int, ShadowScore.DiffOp> {
    if (steps.isEmpty()) return emptyMap()
    val spans = ShadowScore.tokenSpans(words, language)
    val ops = ShadowScore.targetOps(steps)
    if (spans.sumOf { it.count() } != ops.size) return emptyMap()
    val out = HashMap<Int, ShadowScore.DiffOp>()
    spans.forEachIndexed { i, span ->
        val slice = span.mapNotNull { ops.getOrNull(it) }
        out[i] = when {
            slice.isEmpty() -> ShadowScore.DiffOp.MATCH
            slice.contains(ShadowScore.DiffOp.SUB) -> ShadowScore.DiffOp.SUB
            slice.all { it == ShadowScore.DiffOp.DEL } -> ShadowScore.DiffOp.DEL
            slice.contains(ShadowScore.DiffOp.DEL) -> ShadowScore.DiffOp.SUB
            else -> ShadowScore.DiffOp.MATCH
        }
    }
    return out
}

/**
 * One target word's colour. Live take → karaoke by the take's clock; the
 * line playing → karaoke by the playhead (this OUTRANKS the result, or "Hear
 * target" after a take had no moving highlight); a result → content
 * accuracy (orange = said differently, dimmed = skipped); else waiting.
 */
@Composable
private fun wordColor(
    i: Int, wt: WordTiming, nowMs: Int?, recording: Boolean, activeRange: IntRange?,
    hasDiff: Boolean, ops: Map<Int, ShadowScore.DiffOp>,
): Color {
    val secondary = MaterialTheme.colorScheme.onSurfaceVariant
    if (nowMs != null) {
        if (recording && activeRange != null && i !in activeRange) return secondary
        return when {
            nowMs >= wt.endMs -> MaterialTheme.colorScheme.onSurface
            nowMs >= wt.startMs -> MaterialTheme.colorScheme.primary
            else -> secondary
        }
    }
    if (hasDiff) {
        if (activeRange != null && i !in activeRange) return secondary
        return when (ops[i - (activeRange?.first ?: 0)]) {
            ShadowScore.DiffOp.SUB -> orange()
            ShadowScore.DiffOp.DEL -> secondary
            else -> MaterialTheme.colorScheme.onSurface
        }
    }
    return secondary
}

/**
 * The rhythm verdict ON the line: a dot under each word the take was timed
 * on, where the learner started — under the centre on the beat, pushed right
 * if late, left if early — in the score's colour scale, with a trace back to
 * the beat when off it. Nothing under a word unmeasured or skipped. The row
 * is always reserved, so the line doesn't jump when a result lands.
 */
@Composable
private fun BeatMark(w: ShadowScore.RhythmWord?) {
    Box(Modifier.height(6.dp).fillMaxWidth(), contentAlignment = Alignment.Center) {
        if (w != null && w.isMeasured) {
            // 300 ms — the edge of "slightly off" — is 18 dp.
            val offset = (w.deviationMs * 0.06f).coerceIn(-24f, 24f).dp
            val color = rhythmColor(w.deviationMs)
            val onBeat = ShadowScore.rhythmGrade(w.deviationMs) == 2
            if (!onBeat) {
                Box(Modifier.offset(x = offset / 2).width(abs(offset.value).dp).height(1.dp)
                    .background(color.copy(alpha = 0.5f)))
            }
            Box(Modifier.offset(x = offset).size(5.dp).clip(CircleShape)
                .background(if (onBeat) color.copy(alpha = 0.55f) else color))
        }
    }
}

@Composable
private fun DurationCell(label: String, value: String, fill: Color, modifier: Modifier,
                         color: Color = MaterialTheme.colorScheme.onSurface) {
    Column(modifier.clip(RoundedCornerShape(10.dp)).background(fill)
        .padding(vertical = 10.dp, horizontal = 14.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(label, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(value, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.SemiBold, color = color)
    }
}

/** iOS `.buttonStyle(.bordered)`: a grey capsule, accent label. */
@Composable
private fun BorderedButton(label: String, icon: ImageVector, modifier: Modifier, onClick: () -> Unit) {
    Row(modifier.height(40.dp).clip(RoundedCornerShape(20.dp)).background(iosFill()).clickable(onClick = onClick)
        .padding(horizontal = 12.dp), verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.Center) {
        Icon(icon, null, Modifier.size(18.dp), tint = MaterialTheme.colorScheme.primary)
        Spacer(Modifier.width(6.dp))
        Text(label, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.primary,
            maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

@Composable
private fun Bullet(icon: ImageVector, label: String, text: String) {
    Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Icon(icon, null, Modifier.width(20.dp).size(18.dp), tint = MaterialTheme.colorScheme.primary)
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(label, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Text(text, style = MaterialTheme.typography.bodyLarge)
        }
    }
}

/** The one control: record / cancel / retry, by phase. An X mid-take — a
 *  tap DISCARDS it; ending it is the auto-stop's job. */
@Composable
private fun MicButton(phase: ShadowPhase, phrase: Boolean, diameter: androidx.compose.ui.unit.Dp, onTap: () -> Unit) {
    val recording = phase == ShadowPhase.RECORDING
    val enabled = phase == ShadowPhase.IDLE || phase == ShadowPhase.RESULT ||
        phase == ShadowPhase.READ_FAILED || recording
    val pulse = rememberInfiniteTransition(label = "mic")
    val scale by pulse.animateFloat(1f, if (recording) 1.06f else 1f,
        infiniteRepeatable(tween(900), RepeatMode.Reverse), label = "pulse")
    val fill = if (recording) Color(0xFFFF3B30) else MaterialTheme.colorScheme.primary
    Box(Modifier.padding(diameter * 0.03f).scale(scale).size(diameter).clip(CircleShape)
        .background(if (enabled) fill else fill.copy(alpha = 0.4f))
        .clickable(enabled = enabled, onClick = onTap), contentAlignment = Alignment.Center) {
        Icon(when (phase) {
            ShadowPhase.RECORDING -> Icons.Filled.Close
            ShadowPhase.ANALYZING -> Icons.Filled.MoreHoriz
            ShadowPhase.RESULT, ShadowPhase.READ_FAILED -> Icons.Filled.Refresh
            else -> Icons.Filled.Mic
        }, contentDescription = stringResource(when (phase) {
            ShadowPhase.IDLE -> if (phrase) R.string.tap_to_shadow_the_selected_phrase else R.string.tap_to_sync_shadow
            ShadowPhase.LOADING_AUDIO -> R.string.loading
            ShadowPhase.COUNTDOWN -> R.string.speak_when_0_hits
            ShadowPhase.RECORDING -> R.string.follow_the_highlight_tap_to_cancel
            ShadowPhase.ANALYZING -> R.string.comparing
            else -> if (phrase) R.string.tap_to_shadow_the_selected_phrase else R.string.tap_to_try_again
        }), tint = MaterialTheme.colorScheme.surface, modifier = Modifier.size(diameter * 0.375f))
    }
}

@Composable
private fun PastAttemptRow(a: ShadowAttempt, fill: Color, onPlay: (String) -> Unit, onDelete: () -> Unit) {
    var menu by remember { mutableStateOf(false) }
    val secondary = MaterialTheme.colorScheme.onSurfaceVariant
    Box {
        Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp)).background(fill)
            .combinedClickable(onClick = {}, onLongClick = { menu = true })
            .padding(horizontal = 12.dp, vertical = 8.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Column(Modifier.width(56.dp), horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text("${a.overallScore}", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold,
                    color = scoreColor(a.overallScore))
                Text(Recency.label(a.createdAt), style = MaterialTheme.typography.labelSmall, color = secondary)
            }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                // A phrase take, scored on part of the line — say which part,
                // or its score reads as the line's.
                if (a.isPartial) Text(a.targetText, style = MaterialTheme.typography.labelSmall,
                    color = secondary.copy(alpha = 0.6f), maxLines = 1, overflow = TextOverflow.Ellipsis)
                if (a.learnerTranscript.isEmpty()) Text(stringResource(R.string.silent),
                    style = MaterialTheme.typography.bodySmall, color = secondary)
                else Text(a.learnerTranscript, style = MaterialTheme.typography.bodySmall, maxLines = 2,
                    overflow = TextOverflow.Ellipsis)
                // The one bullet worth keeping: what to try next time.
                if (a.fix.isNotEmpty()) Text(a.fix, style = MaterialTheme.typography.labelMedium, color = secondary,
                    maxLines = 2, overflow = TextOverflow.Ellipsis)
            }
            val path = a.recordingFilename?.takeIf { File(it).exists() }
            Icon(if (path != null) Icons.Filled.PlayCircleOutline else Icons.Filled.VolumeOff,
                contentDescription = stringResource(R.string.hear_my_attempt),
                tint = if (path != null) MaterialTheme.colorScheme.primary else secondary.copy(alpha = 0.4f),
                modifier = Modifier.size(28.dp).clip(CircleShape)
                    .clickable(enabled = path != null) { path?.let(onPlay) })
        }
        com.roro.futurevoice.ui.brand.IosDropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
            com.roro.futurevoice.ui.brand.IosDropdownMenuItem(text = { Text(stringResource(R.string.delete), color = Color(0xFFFF3B30)) },
                onClick = { menu = false; onDelete() })
        }
    }
}

/** The TARGET line scored against the take — not a transcript of it. */
private fun diffText(steps: List<ShadowScore.DiffStep>, wrong: Color, missed: Color, kept: Color) =
    buildAnnotatedString {
        steps.forEachIndexed { i, step ->
            if (i > 0) append(" ")
            when (step.op) {
                ShadowScore.DiffOp.MATCH -> { pushStyle(SpanStyle(color = kept)); append(step.target.orEmpty()); pop() }
                ShadowScore.DiffOp.SUB -> { pushStyle(SpanStyle(color = wrong)); append(step.target.orEmpty()); pop() }
                ShadowScore.DiffOp.DEL -> {
                    pushStyle(SpanStyle(color = missed, textDecoration = TextDecoration.LineThrough))
                    append(step.target.orEmpty()); pop()
                }
                ShadowScore.DiffOp.INS -> { pushStyle(SpanStyle(color = wrong)); append("(+${step.learner.orEmpty()})"); pop() }
            }
        }
    }

private fun secondsLabel(s: Double) = String.format(Locale.US, "%.1fs", s)
private fun paceLabel(r: Double) = if (r <= 0) "—" else String.format(Locale.US, "%.2fx", r)

@Composable private fun green() = if (isSystemInDarkTheme()) Color(0xFF30D158) else Color(0xFF34C759)
@Composable private fun orange() = if (isSystemInDarkTheme()) Color(0xFFFF9F0A) else Color(0xFFFF9500)
@Composable private fun red() = if (isSystemInDarkTheme()) Color(0xFFFF453A) else Color(0xFFFF3B30)

/** Pace within 85–125 % reads healthy (iOS `paceColor`). */
@Composable
private fun paceColor(r: Double): Color = when {
    r in 0.85..1.25 -> green()
    r in 0.7..1.5 -> orange()
    r == 0.0 -> MaterialTheme.colorScheme.onSurfaceVariant
    else -> red()
}

/** iOS `scoreColor`: 80+ green, 50–79 the accent, below that orange. */
@Composable
private fun scoreColor(score: Int): Color = when {
    score >= 80 -> green()
    score >= 50 -> MaterialTheme.colorScheme.primary
    else -> orange()
}

@Composable
private fun rhythmColor(deviationMs: Int): Color = when (ShadowScore.rhythmGrade(deviationMs)) {
    2 -> green()
    1 -> orange()
    else -> red()
}

/** The line itself: header, karaoke words, beat dots. Its own function so
 *  the screen body stays small enough for the JIT. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun TargetLineSection(
    line: String, timings: List<WordTiming>, selection: IntRange?, activeRange: IntRange?,
    phraseSelected: Boolean, rhythm: ShadowScore.RhythmAnalysis?, steps: List<ShadowScore.DiffStep>,
    wordOps: Map<Int, ShadowScore.DiffOp>, wordBeats: Map<Int, ShadowScore.RhythmWord>, spaced: Boolean,
    phase: ShadowPhase, syncStartedAt: Long, target: TargetPlayer, tick: Long, tapWord: (Int) -> Unit,
) {
    val secondary = MaterialTheme.colorScheme.onSurfaceVariant
    val tertiary = secondary.copy(alpha = 0.6f)
    val practiceRange = if (phraseSelected) selection else null
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text(stringResource(R.string.target_line), style = MaterialTheme.typography.labelMedium,
                color = secondary)
            Spacer(Modifier.weight(1f))
            val r = rhythm
            when {
                r != null -> {
                    // How many words the score stands on, when
                    // not all of them — the only place it lives.
                    val total = activeRange?.count() ?: timings.size
                    val judged = r.words.count { it.isMeasured }
                    Row(verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        if (judged < total) Text("$judged/$total",
                            style = MaterialTheme.typography.labelSmall, color = tertiary)
                        Icon(Icons.Filled.AvTimer, null, Modifier.size(14.dp), tint = scoreColor(r.score))
                        Text("${r.score}", style = MaterialTheme.typography.labelMedium,
                            fontWeight = FontWeight.SemiBold, color = scoreColor(r.score))
                    }
                }
                timings.isEmpty() -> Text(stringResource(R.string.no_timings),
                    style = MaterialTheme.typography.labelSmall, color = tertiary)
                practiceRange != null -> Text(stringResource(R.string.practicing_the_selected_phrase),
                    style = MaterialTheme.typography.labelSmall, color = tertiary)
                else -> Text(stringResource(R.string.tap_words_to_pick_a_phrase),
                    style = MaterialTheme.typography.labelSmall, color = tertiary)
            }
        }
        if (timings.isEmpty()) {
            Text(line, style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.SemiBold)
        } else {
            if (tick < 0) return@Column   // read: the karaoke redraws on the clock
            val nowMs: Int? = when {
                phase == ShadowPhase.RECORDING && syncStartedAt > 0 ->
                    (System.currentTimeMillis() - syncStartedAt).toInt() +
                        (activeRange?.let { timings[it.first].startMs } ?: 0)
                target.isPlaying -> target.positionMs
                else -> null
            }
            FlowRow(horizontalArrangement = Arrangement.spacedBy(if (spaced) 1.dp else 0.dp),
                verticalArrangement = Arrangement.spacedBy(4.dp)) {
                timings.forEachIndexed { i, wt ->
                    val selected = selection?.contains(i) == true
                    // As wide as the WORD: the dot row may not
                    // push words apart ("I" and "to" gapped). MAX, not
                    // MIN: a CJK word's min intrinsic width is ONE
                    // character, which stacked なるほど into a column.
                    Column(horizontalAlignment = Alignment.CenterHorizontally,
                        modifier = Modifier.width(androidx.compose.foundation.layout.IntrinsicSize.Max).clickable(
                            interactionSource = remember { androidx.compose.foundation.interaction.MutableInteractionSource() },
                            indication = null) { tapWord(i) }) {
                        Text(wt.word,
                            style = MaterialTheme.typography.headlineSmall,
                            fontWeight = FontWeight.SemiBold,
                            color = wordColor(i, wt, nowMs, recording = phase == ShadowPhase.RECORDING,
                                activeRange = activeRange, hasDiff = steps.isNotEmpty(), ops = wordOps),
                            modifier = Modifier.clip(RoundedCornerShape(4.dp))
                                .background(if (selected) MaterialTheme.colorScheme.primary.copy(alpha = 0.22f) else Color.Transparent)
                                .padding(horizontal = if (spaced) 2.dp else 0.dp, vertical = 1.dp))
                        BeatMark(wordBeats[i])
                    }
                }
            }
        }
    }
}

/** "Your take": the headline score, the diff, the three playback buttons,
 *  the coach. */
@Composable
private fun TakeSection(
    fb: ShadowFeedback, steps: List<ShadowScore.DiffStep>, said: String, hasTake: Boolean, coachPending: Boolean,
    onHearTarget: () -> Unit, onHearTake: () -> Unit, onTogether: () -> Unit,
) {
    val secondary = MaterialTheme.colorScheme.onSurfaceVariant
    val tertiary = secondary.copy(alpha = 0.6f)
    Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text(stringResource(R.string.your_take), style = MaterialTheme.typography.labelMedium, color = secondary)
            Spacer(Modifier.weight(1f))
            // Words AND beat — and when the beat could not be
            // measured the badge says so, rather than quietly
            // changing what the number means.
            if (fb.rhythmScore == null) Text(stringResource(R.string.words_only),
                style = MaterialTheme.typography.labelSmall, color = tertiary)
            Spacer(Modifier.width(6.dp))
            Icon(Icons.Filled.Speed, null, Modifier.size(16.dp), tint = scoreColor(fb.overallScore))
            Text(" ${fb.overallScore}", style = MaterialTheme.typography.labelLarge,
                fontWeight = FontWeight.SemiBold, color = scoreColor(fb.overallScore))
        }
        if (steps.isNotEmpty()) {
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Icon(Icons.AutoMirrored.Filled.Notes, null, Modifier.width(20.dp).size(18.dp),
                    tint = MaterialTheme.colorScheme.primary)
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(stringResource(R.string.your_match), style = MaterialTheme.typography.labelMedium, color = secondary)
                    Text(diffText(steps, wrong = orange(), missed = secondary, kept = MaterialTheme.colorScheme.onSurface),
                        style = MaterialTheme.typography.bodyLarge)
                    if (said.isNotBlank()) {
                        Text(stringResource(R.string.what_i_heard), style = MaterialTheme.typography.labelMedium,
                            color = secondary, modifier = Modifier.padding(top = 4.dp))
                        Text(said, style = MaterialTheme.typography.bodyMedium, color = secondary)
                    }
                }
            }
        }
        if (hasTake) {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    BorderedButton(stringResource(R.string.hear_target), Icons.Filled.PlayCircleOutline,
                        Modifier.weight(1f)) { onHearTarget() }
                    BorderedButton(stringResource(R.string.hear_my_attempt), Icons.Filled.RecordVoiceOver,
                        Modifier.weight(1f)) { onHearTake() }
                }
                // Its own row: hearing the two over each other is
                // the thing worth doing here.
                BorderedButton(stringResource(R.string.both_at_once), Icons.Filled.Groups,
                    Modifier.fillMaxWidth()) { onTogether() }
                Text(stringResource(R.string.your_take_over_the_line_both_starting_on_their_first_word_he_891e29),
                    style = MaterialTheme.typography.labelSmall, color = tertiary)
            }
        }
        if (coachPending) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp)
                Text(stringResource(R.string.writing_feedback), style = MaterialTheme.typography.bodySmall,
                    color = secondary)
            }
        }
        if (fb.pronunciation.isNotEmpty()) Bullet(Icons.Filled.GraphicEq, stringResource(R.string.pronunciation), fb.pronunciation)
        if (fb.pacing.isNotEmpty()) Bullet(Icons.Filled.AvTimer, stringResource(R.string.pacing), fb.pacing)
        if (fb.fix.isNotEmpty()) Bullet(Icons.Filled.AutoAwesome, stringResource(R.string.try_this), fb.fix)
    }
}
