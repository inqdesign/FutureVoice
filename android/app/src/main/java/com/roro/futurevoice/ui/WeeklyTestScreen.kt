package com.roro.futurevoice.ui

import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.draw.drawBehind
import androidx.compose.foundation.layout.PaddingValues
import android.Manifest
import com.roro.futurevoice.ui.brand.ContinuousShape
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowCircleUp
import androidx.compose.material.icons.filled.Autorenew
import androidx.compose.material.icons.filled.Cancel
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.EditNote
import androidx.compose.material.icons.filled.EventNote
import androidx.compose.material.icons.outlined.Lightbulb
import androidx.compose.material.icons.filled.FormatQuote
import androidx.compose.material.icons.filled.Hearing
import androidx.compose.material.icons.filled.MenuBook
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.RecordVoiceOver
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material.icons.filled.Translate
import androidx.compose.material.icons.filled.ViewAgenda
import androidx.compose.material.icons.filled.VolumeUp
import com.roro.futurevoice.ui.brand.IosButton as Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledIconButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.MaterialTheme
import com.roro.futurevoice.ui.brand.IosOutlinedButton as OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import com.roro.futurevoice.R
import com.roro.futurevoice.audio.Mp3Player
import com.roro.futurevoice.audio.SoundEffects
import com.roro.futurevoice.audio.WavRecorder
import com.roro.futurevoice.capture.flags.PracticeCaptureFlags
import com.roro.futurevoice.capture.flags.WeeklyTestCaptureFlags
import com.roro.futurevoice.core.Analytics
import com.roro.futurevoice.core.InstallSalt
import com.roro.futurevoice.data.AuthRepository
import com.roro.futurevoice.data.CefrLevel
import com.roro.futurevoice.data.DrillReminder
import com.roro.futurevoice.data.LanguageCatalog
import com.roro.futurevoice.data.PhraseAudioStore
import com.roro.futurevoice.data.SessionStore
import com.roro.futurevoice.data.ShadowAttempt
import com.roro.futurevoice.data.ShadowAttemptStore
import com.roro.futurevoice.data.StoreEvents
import com.roro.futurevoice.data.StoreJson
import com.roro.futurevoice.data.WeeklyTest
import com.roro.futurevoice.data.WeeklyTestEngine
import com.roro.futurevoice.data.WeeklyTestItem
import com.roro.futurevoice.data.WeeklyTestSchedule
import com.roro.futurevoice.data.WeeklyTestSettings
import com.roro.futurevoice.data.WeeklyTestStore
import com.roro.futurevoice.data.WordSplitter
import com.roro.futurevoice.data.cachedSynthesis
import com.roro.futurevoice.net.WordLore
import com.roro.futurevoice.talk.CarryoverDetector
import com.roro.futurevoice.talk.ShadowScore
import com.roro.futurevoice.talk.ShadowTranscriber
import com.roro.futurevoice.ui.brand.AppSurfaces
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

private val RIGHT_GREEN = Color(0xFF34C759)
private val IOS_GRAY = Color(0xFF8E8E93)
private val WRONG_RED = Color(0xFFFF3B30)

/** The speak item's own little machine. */
private enum class SpeakPhase { IDLE, RECORDING, READING, HEARD_NOTHING, MIC_OFF }

private sealed interface TestPhase {
    data object Loading : TestPhase
    data object Thin : TestPhase
    data class Playing(val test: WeeklyTest) : TestPhase
    data class Result(val test: WeeklyTest) : TestPhase
}

/** Longest a spoken take may run before it stops itself. */
private const val MAX_RECORD_MS = 12_000L

/**
 * The weekly test — one screen, three states: building, playing, result (iOS
 * `WeeklyTestView`). One item at a time: a caption saying what to do, the
 * prompt, the answer area, and a bottom bar that grades and moves on. Every
 * answer gets a sound and a haptic the moment it lands.
 *
 * Answers are saved as they happen, so closing mid-test resumes where it
 * stopped; a finished test writes itself into the review loop once.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun WeeklyTestScreen(
    language: String,
    level: CefrLevel,
    onClose: () -> Unit,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val player = remember { Mp3Player(context.cacheDir, source = "weekly_test") }
    val recorder = remember { WavRecorder() }
    val lore = remember { WordLore(AuthRepository()) }
    val store = remember { WeeklyTestStore.shared(context) }
    val native = remember {
        context.getSharedPreferences("futurevoice", 0).getString("futurevoice.nativeLanguage", null) ?: "en"
    }

    var phase by remember { mutableStateOf<TestPhase>(TestPhase.Loading) }
    var current by remember { mutableStateOf<WeeklyTestItem?>(null) }
    var chosen by remember { mutableStateOf<String?>(null) }
    /** build/listen: indices into `item.options`, in the order laid. */
    val laid = remember { mutableStateListOf<Int>() }
    /** Where the next tile goes: an insertion index into `laid`. */
    var cursor by remember { mutableIntStateOf(0) }
    /** null until graded. */
    var outcome by remember { mutableStateOf<Boolean?>(null) }
    var streak by remember { mutableIntStateOf(0) }
    var wrongRun by remember { mutableIntStateOf(0) }
    var moodSince by remember { mutableLongStateOf(System.currentTimeMillis()) }
    /** A second go at this test's misses, played here and never saved. */
    var retry by remember { mutableStateOf<WeeklyTest?>(null) }

    var speakPhase by remember { mutableStateOf(SpeakPhase.IDLE) }
    var speakTranscript by remember { mutableStateOf<String?>(null) }
    var speakScore by remember { mutableStateOf<Int?>(null) }
    var recordingFile by remember { mutableStateOf<File?>(null) }
    var autoStop by remember { mutableStateOf<Job?>(null) }
    var playing by remember { mutableStateOf(false) }
    var playJob by remember { mutableStateOf<Job?>(null) }
    var loadingLineAudio by remember { mutableStateOf(false) }
    /** rewrite: what the learner said or typed, and whether they asked for
     *  the hint. */
    var rewriteText by remember { mutableStateOf("") }
    var showHint by remember { mutableStateOf(false) }

    val mood = when (outcome) {
        null -> WeeklyTestHost.Mood.WAITING
        true -> WeeklyTestHost.Mood.HAPPY
        false -> if (wrongRun >= 2) WeeklyTestHost.Mood.ANGRY else WeeklyTestHost.Mood.SAD
    }
    LaunchedEffect(mood) { moodSince = System.currentTimeMillis() }

    DisposableEffect(Unit) {
        SoundEffects.prepare(context)
        onDispose {
            player.stop()
            autoStop?.cancel()
            runCatching { recorder.stop() }
        }
    }

    fun resume(test: WeeklyTest) {
        var run = 0
        for (a in test.answers.reversed()) { if (!a.correct) break; run++ }
        streak = run
        current = test.nextItem
        chosen = null; laid.clear(); cursor = 0; outcome = null
        phase = TestPhase.Playing(test)
    }

    fun settle(correct: Boolean, given: String, test: WeeklyTest, item: WeeklyTestItem, score: Int? = null) {
        outcome = correct
        streak = if (correct) streak + 1 else 0
        wrongRun = if (correct) 0 else wrongRun + 1
        val t = test.copy(
            answers = test.answers + com.roro.futurevoice.data.WeeklyTestAnswer(
                itemId = item.id, given = given, correct = correct,
                at = System.currentTimeMillis(), score = score),
            bestStreak = maxOf(test.bestStreak, streak))
        if (retry != null) retry = t else scope.launch { store.save(t) }
        phase = TestPhase.Playing(t)
        SoundEffects.play(context, if (correct) SoundEffects.Cue.RIGHT else SoundEffects.Cue.WRONG)
        if (correct) HapticEngine.drillCorrect(context) else HapticEngine.drillIncorrect(context)
    }

    fun finish(test: WeeklyTest) {
        val now = System.currentTimeMillis()
        if (retry != null) {
            // Practice only: nothing saved, nothing written to the loop.
            val t = test.copy(finishedAt = now)
            retry = t; current = null; phase = TestPhase.Result(t)
            SoundEffects.play(context, SoundEffects.Cue.DONE); HapticEngine.success(context)
            return
        }
        var t = test.copy(finishedAt = test.finishedAt ?: now)
        val firstTime = t.appliedAt == null
        if (firstTime) t = t.copy(appliedAt = now)
        current = null
        phase = TestPhase.Result(t)
        if (firstTime) {
            Analytics.capture("weekly_test_finished",
                mapOf("score" to t.score, "total" to t.total, "best_streak" to t.bestStreak))
            SoundEffects.play(context, SoundEffects.Cue.DONE); HapticEngine.success(context)
        }
        scope.launch {
            if (firstTime) WeeklyTestEngine.apply(context, t)
            store.save(t)
            DrillReminder.reschedule(context)
            StoreEvents.bump()
        }
    }

    fun advance(test: WeeklyTest) {
        player.stop(); playJob?.cancel(); playing = false
        chosen = null; laid.clear(); cursor = 0; outcome = null
        rewriteText = ""; showHint = false
        speakPhase = SpeakPhase.IDLE; speakTranscript = null; speakScore = null; recordingFile = null
        val next = test.nextItem
        if (next != null) current = next else finish(test)
    }

    fun choose(option: String, item: WeeklyTestItem) {
        val p = phase as? TestPhase.Playing ?: return
        if (outcome != null) return
        chosen = option
        SoundEffects.play(context, SoundEffects.Cue.TAP)
        settle(WeeklyTestEngine.isCorrect(item, option), option, p.test, item)
    }

    fun checkBuild(item: WeeklyTestItem, test: WeeklyTest) {
        val tiles = laid.map { item.options[it] }
        settle(WeeklyTestEngine.isCorrect(item, tiles, test.targetLanguage),
            WeeklyTestEngine.sentence(tiles, test.targetLanguage), test, item)
    }

    fun checkRewrite(item: WeeklyTestItem, test: WeeklyTest) {
        val given = rewriteText.trim()
        val right = if (item.kind == WeeklyTestItem.Kind.TRANSLATE)
            WeeklyTestEngine.isCorrectTranslate(item, given, test.targetLanguage)
            else WeeklyTestEngine.isCorrectRewrite(item, given, test.targetLanguage)
        settle(right, given, test, item)
    }

    suspend fun buildNew() {
        phase = TestPhase.Loading
        val tests = store.load(language)
        val opening = WeeklyTestSettings.schedule(context).currentOpening()
        // Off the main thread: gathering reads every store and rebuilds every
        // talk book's word chapter, and with a few hundred talks that froze
        // the screen long enough for an ANR (seen in the capture build).
        var test = withContext(Dispatchers.Default) {
            val material = WeeklyTestEngine.gather(context, language, level, native)
            WeeklyTestEngine.build(material, WeeklyTestStore.latestWeekly(tests), language, level,
                recentTests = tests) { word ->
                WeeklyTestCaptureFlags.glosses?.let { return@build it[word] }
                PracticeCaptureFlags.lookup { lore.entry(word, native, language) }
                    ?.senses?.firstOrNull()?.meaning
            }
        }
        if (test == null) {
            WeeklyTestSettings.markThin(context, opening)
            phase = TestPhase.Thin
            return
        }
        WeeklyTestSettings.clearThin(context)
        // A capture run can't reach the model that writes translate items.
        if (WeeklyTestCaptureFlags.kind == WeeklyTestItem.Kind.TRANSLATE &&
            test!!.items.none { it.kind == WeeklyTestItem.Kind.TRANSLATE }) {
            WeeklyTestEngine.translateItem(
                "나 이 스타트업에서 2년째 일하고 있어.",
                answer = "I've been working at this startup for two years.",
                must = listOf(listOf("I've been working", "I have been working"), listOf("for two years")),
                avoid = listOf("am working since", "since two years"),
                point = "현재완료 진행형 + for", tip = "과거부터 지금까지 이어지는 일은 have been -ing와 for를 써요.",
                slip = WeeklyTestEngine.Slip(was = "I am working in a startup since three years",
                    now = "I've been working at a startup for three years", why = "", cardId = null),
                target = "en")?.let { sample -> test = test!!.copy(items = listOf(sample) + test!!.items) }
        }
        WeeklyTestCaptureFlags.kind?.let { k ->
            val i = test!!.items.indexOfFirst { it.kind == k }
            if (i > 0) test = test!!.copy(items = test!!.items.toMutableList().also {
                java.util.Collections.swap(it, 0, i) })
        }
        test = test!!.copy(startedAt = System.currentTimeMillis())
        store.save(test!!)
        Analytics.capture("weekly_test_started", mapOf("items" to test!!.total))
        resume(test!!)
        // Capture: pre-answer the first item.
        val right = WeeklyTestCaptureFlags.answer
        val item = current
        if (right != null && item != null) {
            if (item.kind == WeeklyTestItem.Kind.BUILD || item.kind == WeeklyTestItem.Kind.LISTEN ||
                item.kind == WeeklyTestItem.Kind.GRAMMAR) {
                val answer = WordSplitter.words(item.answer, language).map(WeeklyTestEngine::tileKey)
                val order = ArrayList<Int>()
                for (key in answer) {
                    item.options.indices.firstOrNull {
                        WeeklyTestEngine.tileKey(item.options[it]) == key && it !in order
                    }?.let(order::add)
                }
                if (!right && order.size > 1) java.util.Collections.swap(order, 0, order.lastIndex)
                laid.addAll(order); cursor = laid.size
                checkBuild(item, test!!)
            } else if (item.kind == WeeklyTestItem.Kind.REWRITE || item.kind == WeeklyTestItem.Kind.TRANSLATE) {
                showHint = !right
                rewriteText = if (right) item.answer
                    else if (item.kind == WeeklyTestItem.Kind.TRANSLATE) item.focus.orEmpty() else item.prompt
                checkRewrite(item, test!!)
            } else {
                val pick = if (right) item.answer
                    else item.options.firstOrNull { !WeeklyTestEngine.isCorrect(item, it) } ?: item.answer
                choose(pick, item)
            }
        }
    }

    suspend fun start() {
        val tests = store.load(language)
        val schedule = WeeklyTestSettings.schedule(context)
        // A capture run asks for a specific kind: always deal a fresh paper.
        if (WeeklyTestCaptureFlags.kind != null) { buildNew(); return }
        when (val s = schedule.state(tests, { WeeklyTestSettings.isThin(context, it) })) {
            is WeeklyTestSchedule.State.InProgress -> {
                val cleaned = WeeklyTestEngine.pruned(s.test,
                    WeeklyTestEngine.rewriteLookup(context, s.test.targetLanguage))
                if (cleaned != null) { store.save(cleaned); resume(cleaned) } else resume(s.test)
            }
            is WeeklyTestSchedule.State.Done -> phase = TestPhase.Result(s.test)
            else -> buildNew()
        }
    }

    LaunchedEffect(Unit) { start() }

    fun startRetry(test: WeeklyTest) {
        scope.launch {
            val paper = WeeklyTestEngine.retryPaper(test,
                rewrite = WeeklyTestEngine.rewriteLookup(context, test.targetLanguage)) ?: return@launch
            retry = paper
            wrongRun = 0
            resume(paper)
        }
    }

    // ── Audio

    fun playFile(file: File) {
        player.stop(); playJob?.cancel()
        playJob = scope.launch {
            playing = true
            runCatching { player.play(file) }
            playing = false
        }
    }

    fun playBytes(bytes: ByteArray) {
        player.stop(); playJob?.cancel()
        playJob = scope.launch {
            playing = true
            runCatching { player.play(bytes) }
            playing = false
        }
    }

    /** The turn with this id and its recording, if a talk still has them. */
    suspend fun turnAudio(turnId: String): Pair<String, File>? = withContext(Dispatchers.IO) {
        for (s in SessionStore.shared(context).load(language)) {
            val turn = s.turns.firstOrNull { it.id == turnId } ?: continue
            val file = WeeklyTestEngine.turnAudio(context, turn) ?: return@withContext null
            return@withContext turn.transcript to file
        }
        null
    }

    /** A listen item plays the turn's own recording: the text IS the turn. */
    fun playListen(item: WeeklyTestItem) {
        if (playing) { player.stop(); playJob?.cancel(); playing = false; return }
        val id = item.turnId ?: return
        scope.launch { turnAudio(id)?.second?.let(::playFile) }
    }

    /** A speak item's line, exactly and only that line: its own saved audio
     *  when the turn IS the line, else the phrase cache, else one synthesis
     *  the cache keeps. A cut sentence never plays the turn's file (iOS
     *  `88ad4c3`) — its audio has the neighbouring sentences in it. */
    fun hearLine(item: WeeklyTestItem) {
        if (playing) { player.stop(); playJob?.cancel(); playing = false; return }
        val voiceId = PhraseAudioStore.shared(context).ownVoiceLineage.firstOrNull() ?: return
        scope.launch {
            item.turnId?.let { turnAudio(it) }?.let { (text, file) ->
                if (CarryoverDetector.normalized(text) == CarryoverDetector.normalized(item.answer)) {
                    playFile(file); return@launch
                }
            }
            loadingLineAudio = true
            val audio = runCatching {
                cachedSynthesis(context, voiceId = voiceId, text = item.answer,
                    idempotencyKey = InstallSalt.ttsKey(item.answer, voiceId, timestamps = false),
                    purpose = "shadow")
            }.onFailure { e ->
                // Out of allowance (or a parked voice): the plans (iOS
                // `parkedPaywall`); offline stays silent.
                if (e === com.roro.futurevoice.net.EdgeError.InsufficientCredits)
                    com.roro.futurevoice.data.BillingGate.showPaywall.value = true
            }.getOrNull()
            loadingLineAudio = false
            // Offline or out of allowance: the line is still on screen to read.
            audio?.let(::playBytes)
        }
    }

    // ── Speak

    suspend fun finishRecording(item: WeeklyTestItem, test: WeeklyTest) {
        autoStop?.cancel()
        // A stop tap lands mid-syllable; a clipped tail reads as a dropped word.
        delay(300)
        withContext(Dispatchers.IO) { runCatching { recorder.stop() } }
        val file = recordingFile
        speakPhase = SpeakPhase.READING
        val heard = if (file == null) "" else
            ShadowTranscriber.read(file, test.targetLanguage).text.trim()
        if (heard.isEmpty()) {
            withContext(Dispatchers.IO) { file?.delete() }
            recordingFile = null
            speakPhase = SpeakPhase.HEARD_NOTHING
            return
        }
        val score = ShadowScore.analyze(item.answer, heard, test.targetLanguage).score
        speakTranscript = heard
        speakScore = score
        speakPhase = SpeakPhase.IDLE
        // The take is a real shadow attempt of that line, seen by the talk
        // book's Shadow chapter like any other.
        val turnId = item.turnId
        if (turnId != null && file != null) {
            ShadowAttemptStore.shared(context).add(ShadowAttempt(
                turnId = turnId, targetText = item.answer, learnerTranscript = heard,
                recordingFilename = file.absolutePath, matchScore = score, rhythmScore = null,
            ), test.targetLanguage)
        } else withContext(Dispatchers.IO) { file?.delete() }
        com.roro.futurevoice.data.PracticeLog.record(context,
            com.roro.futurevoice.data.PracticeLog.Kind.SHADOW, finished = true)
        settle(score >= WeeklyTestEngine.SPEAK_PASS_SCORE, heard, test, item, score)
    }

    fun beginRecording(item: WeeklyTestItem, test: WeeklyTest) {
        player.stop(); playJob?.cancel(); playing = false
        val file = File(File(context.filesDir, "shadow-takes"), StoreJson.newId() + ".wav")
        file.parentFile?.mkdirs()
        if (runCatching { recorder.start(file) }.isFailure) { speakPhase = SpeakPhase.MIC_OFF; return }
        recordingFile = file
        speakPhase = SpeakPhase.RECORDING
        HapticEngine.countdownGo(context)
        autoStop?.cancel()
        autoStop = scope.launch {
            delay(MAX_RECORD_MS)
            if (speakPhase == SpeakPhase.RECORDING) finishRecording(item, test)
        }
    }

    var afterPermission by remember { mutableStateOf<(() -> Unit)?>(null) }
    val micPermission = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted ->
        val next = afterPermission
        afterPermission = null
        if (granted) next?.invoke() else speakPhase = SpeakPhase.MIC_OFF
    }

    fun toggleRecording(item: WeeklyTestItem) {
        val p = phase as? TestPhase.Playing ?: return
        if (outcome != null) return
        when (speakPhase) {
            SpeakPhase.RECORDING -> scope.launch { finishRecording(item, p.test) }
            SpeakPhase.READING -> Unit
            else -> {
                val ok = ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) ==
                    PackageManager.PERMISSION_GRANTED
                if (ok) beginRecording(item, p.test) else {
                    afterPermission = { beginRecording(item, p.test) }
                    micPermission.launch(Manifest.permission.RECORD_AUDIO)
                }
            }
        }
    }

    // ── Tiles

    fun lay(index: Int) {
        if (outcome != null) return
        val at = cursor.coerceIn(0, laid.size)
        laid.add(at, index)
        cursor = at + 1
        SoundEffects.play(context, SoundEffects.Cue.TAP); HapticEngine.selection(context)
    }

    /** First tap on a placed tile moves the cursor after it; a second tap on
     *  the tile the cursor already follows takes it out. */
    fun tapPlaced(position: Int) {
        if (outcome != null || position !in laid.indices) return
        if (cursor == position + 1) {
            laid.removeAt(position)
            cursor = if (position < laid.size) position else laid.size
        } else cursor = position + 1
        SoundEffects.play(context, SoundEffects.Cue.TAP); HapticEngine.selection(context)
    }

    val recording = speakPhase == SpeakPhase.RECORDING
    androidx.activity.compose.BackHandler(enabled = recording) { }

    Scaffold(
        containerColor = AppSurfaces.ground,
        topBar = {
            CenterAlignedTopAppBar(
                colors = AppSurfaces.topBarColors(),
                title = {
                    Text(stringResource(R.string.weekly_test),
                        style = MaterialTheme.typography.titleMedium)
                },
                actions = {
                    TextButton(onClick = onClose, enabled = !recording) { Text(stringResource(R.string.done)) }
                },
            )
        },
        bottomBar = {
            val p = phase as? TestPhase.Playing
            val item = current
            if (p != null && item != null) {
                val rewrite = item.kind == WeeklyTestItem.Kind.REWRITE ||
                    item.kind == WeeklyTestItem.Kind.TRANSLATE
                BottomBar(item, outcome, isLast = p.test.nextItem == null,
                    canCheck = if (rewrite) rewriteText.isNotBlank() else laid.isNotEmpty(),
                    onCheck = { if (rewrite) checkRewrite(item, p.test) else checkBuild(item, p.test) },
                    onContinue = { advance(p.test) })
            }
        },
    ) { padding ->
        Box(Modifier.fillMaxSize().padding(padding)) {
            when (val ph = phase) {
                TestPhase.Loading -> Column(Modifier.fillMaxSize(),
                    verticalArrangement = Arrangement.Center,
                    horizontalAlignment = Alignment.CenterHorizontally) {
                    WeeklyTestCharacter(WeeklyTestHost.Mood.THINKING, moodSince)
                    Spacer(Modifier.height(16.dp))
                    Text(stringResource(R.string.making_your_test),
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                TestPhase.Thin -> ThinState { scope.launch { buildNew() } }
                is TestPhase.Result -> WeeklyTestResult(ph.test, isRetry = retry != null,
                    language = language, onRetry = { startRetry(ph.test) })
                is TestPhase.Playing -> {
                    val item = current
                    if (item == null) Box(Modifier.fillMaxSize(), Alignment.Center) { CircularProgressIndicator() }
                    else Column(Modifier.fillMaxSize()) {
                        Box(Modifier.fillMaxWidth().padding(top = 14.dp, bottom = 6.dp), Alignment.Center) {
                            WeeklyTestCharacter(mood, moodSince)
                        }
                        Column(Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState())
                            .padding(horizontal = 20.dp, vertical = 16.dp),
                            verticalArrangement = Arrangement.spacedBy(20.dp)) {
                            Row(verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                                Caption(item.kind, ph.test.targetLanguage, native)
                                if (item.isRetake == true) {
                                    Text(stringResource(R.string.again),
                                        style = MaterialTheme.typography.labelSmall,
                                        fontWeight = FontWeight.SemiBold,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                        modifier = Modifier.background(
                                            MaterialTheme.colorScheme.surfaceContainerHighest,
                                            RoundedCornerShape(50)).padding(horizontal = 7.dp, vertical = 3.dp))
                                }
                                Spacer(Modifier.weight(1f))
                                Text("${minOf(ph.test.answers.size + 1, ph.test.total)}/${ph.test.total}",
                                    style = MaterialTheme.typography.labelLarge,
                                    fontWeight = FontWeight.SemiBold,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                            Prompt(item, ph.test.targetLanguage, chosen, outcome, playing, loadingLineAudio,
                                showHint = showHint, onShowHint = { showHint = true },
                                speakBusy = speakPhase == SpeakPhase.RECORDING || speakPhase == SpeakPhase.READING,
                                canHear = PhraseAudioStore.shared(context).ownVoiceLineage.isNotEmpty(),
                                onPlay = { playListen(item) }, onHear = { hearLine(item) })
                            when (item.kind) {
                                WeeklyTestItem.Kind.MEANING, WeeklyTestItem.Kind.GAP, WeeklyTestItem.Kind.UPGRADE ->
                                    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                                        item.options.forEach { option ->
                                            OptionButton(option, item, chosen, outcome) { choose(option, item) }
                                        }
                                    }
                                WeeklyTestItem.Kind.BUILD, WeeklyTestItem.Kind.LISTEN, WeeklyTestItem.Kind.GRAMMAR ->
                                    BuildArea(item, ph.test.targetLanguage, laid, cursor, outcome,
                                        onLay = ::lay, onTapPlaced = ::tapPlaced,
                                        onTapEnd = { if (outcome == null) cursor = laid.size })
                                WeeklyTestItem.Kind.REWRITE, WeeklyTestItem.Kind.TRANSLATE ->
                                    RewriteArea(rewriteText, ph.test.targetLanguage, outcome,
                                        placeholder = stringResource(
                                            if (item.kind == WeeklyTestItem.Kind.TRANSLATE) R.string.wt_say_or_type_it
                                            else R.string.wt_say_or_type_right_way),
                                        onText = { rewriteText = it })
                                WeeklyTestItem.Kind.SPEAK ->
                                    SpeakArea(speakPhase, outcome, speakTranscript, speakScore,
                                        level = recorder.level,
                                        onToggle = { toggleRecording(item) },
                                        onSkip = {
                                            if (outcome == null) settle(false, "", ph.test, item)
                                        })
                            }
                        }
                    }
                }
            }
        }
    }
}

// ── Pieces

@Composable
private fun ThinState(onTryAgain: () -> Unit) {
    Column(Modifier.fillMaxSize().padding(32.dp), verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally) {
        Icon(Icons.Filled.EventNote, contentDescription = null,
            modifier = Modifier.size(44.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
        Spacer(Modifier.height(12.dp))
        Text(stringResource(R.string.a_talk_or_two_first),
            style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
        Spacer(Modifier.height(6.dp))
        Text(stringResource(R.string.the_test_is_made_from_your_week_s_talks_after_the_next_one_i_0a9c48),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = androidx.compose.ui.text.style.TextAlign.Center)
        Spacer(Modifier.height(16.dp))
        OutlinedButton(onClick = onTryAgain) { Text(stringResource(R.string.try_again)) }
    }
}

private fun kindIcon(kind: WeeklyTestItem.Kind): ImageVector = when (kind) {
    WeeklyTestItem.Kind.MEANING -> Icons.Filled.MenuBook
    WeeklyTestItem.Kind.GAP -> Icons.Filled.FormatQuote
    WeeklyTestItem.Kind.BUILD -> Icons.Filled.ViewAgenda
    WeeklyTestItem.Kind.LISTEN -> Icons.Filled.Hearing
    WeeklyTestItem.Kind.SPEAK -> Icons.Filled.RecordVoiceOver
    WeeklyTestItem.Kind.GRAMMAR -> Icons.Filled.Autorenew
    WeeklyTestItem.Kind.UPGRADE -> Icons.Filled.ArrowCircleUp
    WeeklyTestItem.Kind.REWRITE -> Icons.Filled.EditNote
    WeeklyTestItem.Kind.TRANSLATE -> Icons.Filled.Translate
}

@Composable
private fun Caption(kind: WeeklyTestItem.Kind, target: String, native: String) {
    val label = if (kind == WeeklyTestItem.Kind.TRANSLATE)
        stringResource(R.string.wt_say_it_in, LanguageCatalog.ownName(target, native))
    else stringResource(when (kind) {
        WeeklyTestItem.Kind.MEANING -> R.string.which_word_means_this
        WeeklyTestItem.Kind.GAP -> R.string.fill_the_blank
        // "Fix the sentence" (iOS `cf5b08d`): the old "say it the fluent
        // way" collided with the Say it again feature.
        WeeklyTestItem.Kind.BUILD -> R.string.wt_fix_the_sentence
        WeeklyTestItem.Kind.LISTEN -> R.string.listen_and_build_it
        WeeklyTestItem.Kind.SPEAK -> R.string.say_it_out_loud
        WeeklyTestItem.Kind.GRAMMAR -> R.string.wt_mistake_you_keep_making
        WeeklyTestItem.Kind.UPGRADE -> R.string.wt_better_word
        WeeklyTestItem.Kind.REWRITE -> R.string.wt_say_it_right_way
        WeeklyTestItem.Kind.TRANSLATE -> R.string.wt_say_it_right_way // drawn above
    })
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        Icon(kindIcon(kind), contentDescription = null, modifier = Modifier.size(18.dp),
            tint = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(label, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold,
            color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun Prompt(item: WeeklyTestItem, language: String, chosen: String?, outcome: Boolean?, playing: Boolean,
                   loadingLineAudio: Boolean, showHint: Boolean, onShowHint: () -> Unit,
                   speakBusy: Boolean, canHear: Boolean,
                   onPlay: () -> Unit, onHear: () -> Unit) {
    when (item.kind) {
        WeeklyTestItem.Kind.REWRITE -> RewritePrompt(item, language, outcome, showHint, onShowHint)
        WeeklyTestItem.Kind.TRANSLATE -> TranslatePrompt(item, outcome, showHint, onShowHint)
        // iOS .title2 semibold (22 pt).
        WeeklyTestItem.Kind.MEANING -> Text(item.prompt, style = MaterialTheme.typography.headlineSmall,
            fontWeight = FontWeight.SemiBold)
        WeeklyTestItem.Kind.GAP -> {
            // The blank filled by the chosen phrase once one is picked, so the
            // learner reads their answer in place.
            val parts = item.prompt.split(WeeklyTestEngine.BLANK_MARK)
            val accent = MaterialTheme.colorScheme.primary
            val faint = MaterialTheme.colorScheme.outline
            Text(buildAnnotatedString {
                if (parts.size != 2) { append(item.prompt); return@buildAnnotatedString }
                append(parts[0])
                if (chosen != null) {
                    val color = when (outcome) { null -> accent; true -> RIGHT_GREEN; false -> WRONG_RED }
                    withStyle(SpanStyle(color = color, fontWeight = FontWeight.Bold)) { append(chosen) }
                } else withStyle(SpanStyle(color = faint)) { append(WeeklyTestEngine.BLANK_MARK) }
                append(parts[1])
            }, style = MaterialTheme.typography.titleLarge) // iOS .title3
        }
        WeeklyTestItem.Kind.BUILD -> Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(stringResource(R.string.you_said_f105ab), style = MaterialTheme.typography.labelMedium,
                fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Text("“${item.prompt}”", style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        WeeklyTestItem.Kind.GRAMMAR -> Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            item.rule?.takeIf { it.isNotBlank() }?.let {
                Text(it, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold)
            }
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(stringResource(R.string.you_said_f105ab), style = MaterialTheme.typography.labelMedium,
                    fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Text(marked(item.prompt, item.focus), style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        WeeklyTestItem.Kind.UPGRADE -> Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(stringResource(R.string.you_said_f105ab), style = MaterialTheme.typography.labelMedium,
                    fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Text(marked(item.prompt, item.focus), style = MaterialTheme.typography.titleLarge)
            }
            item.focus?.let {
                Text(stringResource(R.string.wt_more_natural_than, it), style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.SemiBold)
            }
            // Once answered: the same line with the better word, and why.
            if (outcome != null) {
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    item.example?.takeIf { it.isNotBlank() }?.let {
                        Text(it, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.Medium,
                            color = RIGHT_GREEN)
                    }
                    item.note?.takeIf { it.isNotBlank() }?.let {
                        Text(it, style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
        }
        WeeklyTestItem.Kind.LISTEN -> Box(Modifier.fillMaxWidth().padding(vertical = 8.dp), Alignment.Center) {
            // iOS: a 76 pt label inside .borderedProminent, which pads it to ~90.
            FilledIconButton(onClick = onPlay, modifier = Modifier.size(90.dp)) {
                Icon(if (playing) Icons.Filled.VolumeUp else Icons.Filled.PlayArrow,
                    contentDescription = stringResource(R.string.play_the_line), modifier = Modifier.size(36.dp))
            }
        }
        WeeklyTestItem.Kind.SPEAK -> Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(item.answer, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Medium)
            if (outcome == null && canHear) {
                OutlinedButton(onClick = onHear, enabled = !speakBusy && !loadingLineAudio) {
                    if (loadingLineAudio) {
                        CircularProgressIndicator(Modifier.size(14.dp), strokeWidth = 2.dp)
                        Spacer(Modifier.width(6.dp))
                    }
                    Icon(Icons.Filled.VolumeUp, contentDescription = null, modifier = Modifier.size(16.dp))
                    Spacer(Modifier.width(6.dp))
                    Text(stringResource(R.string.hear_it), style = MaterialTheme.typography.labelLarge)
                }
            }
        }
    }
}

// ── Translate

/**
 * A new sentence in the learner's language that needs the grammar they got
 * wrong. The point and its tip are the hint; once graded, the model answer
 * with the spans that prove the point in bold, and the slip it was built on
 * (iOS `translatePrompt`).
 */
@Composable
private fun TranslatePrompt(item: WeeklyTestItem, outcome: Boolean?, showHint: Boolean, onShowHint: () -> Unit) {
    val secondary = MaterialTheme.colorScheme.onSurfaceVariant
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(item.prompt, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold)
        if (outcome == null) {
            if (showHint) {
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    HintLabel()
                    item.rule?.takeIf { it.isNotEmpty() }?.let {
                        Text(it, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.SemiBold)
                    }
                    item.note?.takeIf { it.isNotEmpty() }?.let {
                        Text(it, style = MaterialTheme.typography.bodySmall, color = secondary)
                    }
                }
            } else ShowHintButton(onShowHint)
        } else {
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(stringResource(R.string.wt_right_way), style = MaterialTheme.typography.labelMedium,
                    fontWeight = FontWeight.SemiBold, color = secondary)
                Text(spansBold(item.answer, WeeklyTestEngine.requiredSpans(item)),
                    style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.Medium, color = RIGHT_GREEN)
                item.rule?.takeIf { it.isNotEmpty() }?.let {
                    Text(it, style = MaterialTheme.typography.bodySmall, fontWeight = FontWeight.SemiBold,
                        modifier = Modifier.padding(top = 4.dp))
                }
                item.note?.takeIf { it.isNotEmpty() }?.let {
                    Text(it, style = MaterialTheme.typography.bodySmall, color = secondary)
                }
            }
            val was = item.focus
            val fixed = item.example
            if (was != null && fixed != null) {
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(stringResource(R.string.wt_last_time_you_said), style = MaterialTheme.typography.labelMedium,
                        fontWeight = FontWeight.SemiBold, color = secondary)
                    Text(buildAnnotatedString {
                        withStyle(SpanStyle(textDecoration = TextDecoration.LineThrough)) { append(was) }
                        append("  →  ")
                        withStyle(SpanStyle(fontWeight = FontWeight.Bold)) { append(fixed) }
                    }, style = MaterialTheme.typography.bodySmall, color = secondary)
                }
            }
        }
    }
}

/** [text] with each of [spans] (first occurrence) in bold and underlined. */
private fun spansBold(text: String, spans: List<String>) = buildAnnotatedString {
    val ranges = ArrayList<IntRange>()
    for (span in spans) {
        val r = WeeklyTestEngine.foldedRange(text, span) ?: continue
        if (ranges.none { it.first <= r.last && r.first <= it.last }) ranges += r
    }
    ranges.sortBy { it.first }
    var cursor = 0
    for (r in ranges) {
        append(text.substring(cursor, r.first))
        withStyle(SpanStyle(fontWeight = FontWeight.Bold, textDecoration = TextDecoration.Underline)) {
            append(text.substring(r.first, r.last + 1))
        }
        cursor = r.last + 1
    }
    append(text.substring(cursor))
}

@Composable
private fun HintLabel() {
    val secondary = MaterialTheme.colorScheme.onSurfaceVariant
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        Icon(Icons.Outlined.Lightbulb, contentDescription = null, modifier = Modifier.size(14.dp), tint = secondary)
        Text(stringResource(R.string.wt_hint), style = MaterialTheme.typography.labelMedium,
            fontWeight = FontWeight.SemiBold, color = secondary)
    }
}

/** iOS `.bordered` + `.controlSize(.small)`. */
@Composable
private fun ShowHintButton(onClick: () -> Unit) {
    Button(onClick = onClick, shape = CircleShape,
        contentPadding = PaddingValues(horizontal = 12.dp, vertical = 6.dp),
        colors = ButtonDefaults.buttonColors(
            containerColor = MaterialTheme.colorScheme.primary.copy(alpha = 0.15f),
            contentColor = MaterialTheme.colorScheme.primary),
        elevation = null) {
        Icon(Icons.Outlined.Lightbulb, contentDescription = null, modifier = Modifier.size(14.dp))
        Spacer(Modifier.width(4.dp))
        Text(stringResource(R.string.wt_show_hint), style = MaterialTheme.typography.labelMedium,
            fontWeight = FontWeight.SemiBold)
    }
}

// ── Rewrite

/**
 * The learner's own sentence, whole, with the slip underlined; the hint (why
 * it was corrected + the words the fix brings) only on request. Once graded:
 * the right way, with the fix in bold (iOS `rewritePrompt`).
 */
@Composable
private fun RewritePrompt(item: WeeklyTestItem, language: String, outcome: Boolean?,
                          showHint: Boolean, onShowHint: () -> Unit) {
    val secondary = MaterialTheme.colorScheme.onSurfaceVariant
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(stringResource(R.string.you_said_f105ab), style = MaterialTheme.typography.labelMedium,
                fontWeight = FontWeight.SemiBold, color = secondary)
            Text(buildAnnotatedString {
                append("“"); append(diffMarked(item.prompt, item.answer, language)); append("”")
            }, style = MaterialTheme.typography.titleLarge) // iOS .title3
        }
        if (outcome == null) {
            if (showHint) {
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                        Icon(Icons.Outlined.Lightbulb, contentDescription = null,
                            modifier = Modifier.size(14.dp), tint = secondary)
                        Text(stringResource(R.string.wt_hint), style = MaterialTheme.typography.labelMedium,
                            fontWeight = FontWeight.SemiBold, color = secondary)
                    }
                    WeeklyTestEngine.hintWords(item)?.let {
                        Text(it, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.SemiBold)
                    }
                    item.note?.takeIf { it.isNotEmpty() }?.let {
                        Text(it, style = MaterialTheme.typography.bodySmall, color = secondary)
                    }
                }
            } else {
                // iOS `.bordered` + `.controlSize(.small)`.
                Button(onClick = onShowHint, shape = CircleShape,
                    contentPadding = PaddingValues(horizontal = 12.dp, vertical = 6.dp),
                    colors = ButtonDefaults.buttonColors(
                        containerColor = MaterialTheme.colorScheme.primary.copy(alpha = 0.15f),
                        contentColor = MaterialTheme.colorScheme.primary),
                    elevation = null) {
                    Icon(Icons.Outlined.Lightbulb, contentDescription = null, modifier = Modifier.size(14.dp))
                    Spacer(Modifier.width(4.dp))
                    Text(stringResource(R.string.wt_show_hint), style = MaterialTheme.typography.labelMedium,
                        fontWeight = FontWeight.SemiBold)
                }
            }
        } else {
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(stringResource(R.string.wt_right_way), style = MaterialTheme.typography.labelMedium,
                    fontWeight = FontWeight.SemiBold, color = secondary)
                Text(diffMarked(item.answer, item.prompt, language), style = MaterialTheme.typography.bodyLarge,
                    fontWeight = FontWeight.Medium, color = RIGHT_GREEN)
                item.note?.takeIf { it.isNotEmpty() }?.let {
                    Text(it, style = MaterialTheme.typography.bodySmall, color = secondary)
                }
            }
        }
    }
}

/** [text] with the words [other] doesn't share (outside their longest
 *  common run) bold and underlined — what the fix changed, never the whole
 *  sentence when a card's source happens to be all of it. */
private fun diffMarked(text: String, other: String, language: String) = buildAnnotatedString {
    val words = WordSplitter.words(text, language)
    val kept = WeeklyTestEngine.tileCheck(words, other, language).correct
    val gap = if (WordSplitter.spaced(language)) " " else ""
    words.forEachIndexed { i, word ->
        if (i > 0) append(gap)
        if (kept[i]) append(word)
        else withStyle(SpanStyle(fontWeight = FontWeight.Bold, textDecoration = TextDecoration.Underline)) {
            append(word)
        }
    }
}

/** Say it (the field's mic dictates in the target language) or type it. */
@Composable
private fun RewriteArea(text: String, language: String, outcome: Boolean?, placeholder: String,
                        onText: (String) -> Unit) {
    if (outcome == null) {
        var usedVoice by remember { mutableStateOf(false) }
        SpeakOrTypeField(text = text, onText = onText, usedVoice = usedVoice,
            onUsedVoice = { usedVoice = it },
            placeholder = placeholder,
            locale = LanguageCatalog.sttLocale(language))
    } else {
        Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(stringResource(R.string.wt_your_answer), style = MaterialTheme.typography.labelMedium,
                fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Text(text, style = MaterialTheme.typography.bodyLarge)
        }
    }
}

/** “[text]” with the first occurrence of [focus] bold and underlined — the
 *  word or span the item is about. */
private fun marked(text: String, focus: String?) = buildAnnotatedString {
    append("“")
    val range = focus?.let { WeeklyTestEngine.foldedRange(text, it) }
    if (range == null) append(text) else {
        append(text.substring(0, range.first))
        withStyle(SpanStyle(fontWeight = FontWeight.Bold, textDecoration = TextDecoration.Underline)) {
            append(text.substring(range.first, range.last + 1))
        }
        append(text.substring(range.last + 1))
    }
    append("”")
}

@Composable
private fun OptionButton(option: String, item: WeeklyTestItem, chosen: String?, outcome: Boolean?,
                         onClick: () -> Unit) {
    val isAnswer = WeeklyTestEngine.isCorrect(item, option)
    val isChosen = chosen == option
    val graded = outcome != null
    // iOS: `.bordered` + `.controlSize(.large)` — a filled capsule (tint at
    // ~18 %, no stroke), ~62 pt tall; graded, the rows that are neither the
    // answer nor the pick go GRAY (fill and text), never a dimmed outline.
    val tint = when {
        !graded -> MaterialTheme.colorScheme.primary
        isAnswer -> RIGHT_GREEN
        isChosen -> WRONG_RED
        else -> IOS_GRAY
    }
    Button(
        onClick = onClick,
        modifier = Modifier.fillMaxWidth().heightIn(min = 62.dp),
        shape = CircleShape,
        contentPadding = PaddingValues(horizontal = 20.dp, vertical = 12.dp),
        colors = ButtonDefaults.buttonColors(
            containerColor = tint.copy(alpha = 0.18f), contentColor = tint),
        elevation = null,
    ) {
        Text(option, Modifier.weight(1f), style = MaterialTheme.typography.bodyLarge)
        // The verdict slot is ALWAYS laid out, so the text wraps the same way
        // before and after grading.
        Icon(if (graded && isAnswer) Icons.Filled.CheckCircle else Icons.Filled.Cancel,
            contentDescription = null,
            modifier = Modifier.size(22.dp).alpha(if (graded && (isAnswer || isChosen)) 1f else 0f))
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun BuildArea(item: WeeklyTestItem, language: String, laid: List<Int>, cursor: Int,
                      outcome: Boolean?, onLay: (Int) -> Unit, onTapPlaced: (Int) -> Unit,
                      onTapEnd: () -> Unit) {
    // Graded and wrong: which tiles were actually misplaced.
    val check = if (outcome == false)
        WeeklyTestEngine.tileCheck(laid.map { item.options[it] }, item.answer, language) else null
    // A fix item may carry decoys (the words the correction replaced), so some
    // tiles are meant to be left over — said up front, or a leftover tile
    // reads as a mistake or a bug (iOS `cf5b08d`).
    val fixes = item.kind == WeeklyTestItem.Kind.BUILD || item.kind == WeeklyTestItem.Kind.GRAMMAR
    val decoys = if (fixes) WeeklyTestEngine.decoyTiles(item, language) else emptyList()
    Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
        if (fixes && outcome == null) {
            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(stringResource(R.string.wt_write_correct_sentence), style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.SemiBold)
                if (decoys.isNotEmpty()) {
                    Text(stringResource(R.string.wt_some_words_traps), style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
        // iOS: a DASHED 14 pt outline in .tertiary, 56 pt of room inside a 12 pt pad.
        val dash = MaterialTheme.colorScheme.outline.copy(alpha = 0.55f)
        Box(Modifier.fillMaxWidth()
            .drawBehind {
                val w = 1.dp.toPx()
                drawRoundRect(dash, topLeft = Offset(w / 2, w / 2),
                    size = Size(size.width - w, size.height - w),
                    cornerRadius = CornerRadius(14.dp.toPx()),
                    style = Stroke(w, pathEffect = PathEffect.dashPathEffect(
                        floatArrayOf(6.dp.toPx(), 5.dp.toPx()))))
            }
            .clickable(onClick = onTapEnd).padding(12.dp).heightIn(min = 56.dp)) {
            if (laid.isEmpty() && item.kind == WeeklyTestItem.Kind.LISTEN) {
                Text(stringResource(R.string.tap_the_words_in_order), style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.outline, modifier = Modifier.padding(8.dp))
            }
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp)) {
                if (outcome == null && cursor == 0 && laid.isNotEmpty()) Caret()
                laid.forEachIndexed { position, index ->
                    val verdict = check?.correct?.getOrNull(position)
                    Tile(item.options[index], filled = true, outcome = outcome, verdict = verdict,
                        selected = outcome == null && cursor == position + 1 && cursor < laid.size) {
                        onTapPlaced(position)
                    }
                    if (outcome == null && cursor == position + 1 && cursor < laid.size) Caret()
                }
            }
        }
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)) {
            item.options.forEachIndexed { index, word ->
                if (index !in laid) Tile(word, filled = false, outcome = outcome, verdict = null) { onLay(index) }
            }
        }
        if (outcome == null && laid.isNotEmpty()) {
            Text(stringResource(R.string.tap_a_placed_word_to_add_after_it_tap_it_again_to_take_it_ou_d26a64),
                style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.outline)
        }
        // Once graded, the leftover traps are named for what they are: the
        // learner's own words from before the fix.
        if (outcome != null && decoys.isNotEmpty()) {
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(stringResource(R.string.wt_trap_words), style = MaterialTheme.typography.labelMedium,
                    fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.onSurfaceVariant)
                // Right: the leftover tiles above ARE the traps. Wrong: the
                // leftovers may mix in answer words, so the traps are spelled out.
                if (outcome == false) {
                    Text(decoys.joinToString(" · "), style = MaterialTheme.typography.bodySmall,
                        textDecoration = TextDecoration.LineThrough,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
        if (outcome == false) {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(stringResource(if (item.kind == WeeklyTestItem.Kind.LISTEN) R.string.what_was_said
                        else R.string.fluent_version), style = MaterialTheme.typography.labelMedium,
                        fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    // The words never placed carried in bold — the one word
                    // missing from an otherwise right sentence is the lesson.
                    val words = WordSplitter.words(item.answer, language)
                    val gap = if (WordSplitter.spaced(language)) " " else ""
                    Text(buildAnnotatedString {
                        if (check == null || check.answerMatched.size != words.size) {
                            withStyle(SpanStyle(color = RIGHT_GREEN)) { append(item.answer) }
                        } else words.forEachIndexed { i, w ->
                            if (i > 0) append(gap)
                            val missing = !check.answerMatched[i]
                            withStyle(SpanStyle(color = RIGHT_GREEN,
                                fontWeight = if (missing) FontWeight.Bold else FontWeight.Medium,
                                textDecoration = if (missing) TextDecoration.Underline else null)) { append(w) }
                        }
                    }, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.Medium)
                }
                // The card's own reason, labelled for what it is: why this
                // sentence was corrected, not a verdict on the order just laid.
                val note = item.note
                if (!note.isNullOrBlank()) {
                    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Text(stringResource(if (item.kind == WeeklyTestItem.Kind.GRAMMAR) R.string.wt_tip
                            else R.string.why_it_was_corrected), style = MaterialTheme.typography.labelMedium,
                            fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        Text(note, style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
        }
    }
}

/** [verdict] null = not graded (or graded right, where the whole row is
 *  green); true = this tile sits where the answer wants it. */
@Composable
private fun Tile(word: String, filled: Boolean, outcome: Boolean?, verdict: Boolean?,
                 selected: Boolean = false, onClick: () -> Unit) {
    val tint = when {
        !filled -> if (outcome == null) MaterialTheme.colorScheme.primary else IOS_GRAY
        outcome == null -> MaterialTheme.colorScheme.primary
        outcome == true -> RIGHT_GREEN
        verdict == true -> RIGHT_GREEN
        else -> WRONG_RED
    }
    Box(Modifier
        .background(tint.copy(alpha = 0.18f), RoundedCornerShape(50))
        .border(if (selected) 2.dp else 0.dp,
            if (selected) MaterialTheme.colorScheme.primary else Color.Transparent, RoundedCornerShape(50))
        .clickable(onClick = onClick)
        // iOS: 12/8 label padding inside `.bordered`, which adds its own ~10/6 —
        // a ~49 pt capsule.
        .padding(horizontal = 22.dp, vertical = 14.dp)) {
        Text(word, color = tint, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.Medium)
    }
}

/** The insertion point, drawn between placed tiles when it isn't at the end. */
@Composable
private fun Caret() {
    val t = rememberInfiniteTransition(label = "caret")
    val a by t.animateFloat(1f, 0.15f, infiniteRepeatable(tween(550), RepeatMode.Reverse), label = "blink")
    Box(Modifier.height(50.dp), Alignment.Center) {
        Box(Modifier.width(2.dp).height(24.dp).alpha(a)
            .background(MaterialTheme.colorScheme.primary, RoundedCornerShape(1.dp)))
    }
}

@Composable
private fun SpeakArea(phase: SpeakPhase, outcome: Boolean?, transcript: String?, score: Int?,
                      level: Float, onToggle: () -> Unit, onSkip: () -> Unit) {
    Column(Modifier.fillMaxWidth().padding(top = 8.dp), horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(14.dp)) {
        val recording = phase == SpeakPhase.RECORDING
        FilledIconButton(
            onClick = onToggle,
            enabled = phase != SpeakPhase.READING && outcome == null,
            modifier = Modifier.size(90.dp).scale(if (recording) 1f + level.coerceIn(0f, 1f) * 0.12f else 1f),
            shape = CircleShape,
            colors = if (recording) IconButtonDefaults.filledIconButtonColors(containerColor = WRONG_RED)
                else IconButtonDefaults.filledIconButtonColors(),
        ) {
            if (phase == SpeakPhase.READING) {
                CircularProgressIndicator(Modifier.size(26.dp), strokeWidth = 2.dp,
                    color = MaterialTheme.colorScheme.onPrimary)
            } else {
                Icon(if (recording) Icons.Filled.Stop else Icons.Filled.Mic,
                    contentDescription = stringResource(if (recording) R.string.stop else R.string.record),
                    modifier = Modifier.size(36.dp))
            }
        }
        val hint = when (phase) {
            SpeakPhase.IDLE -> if (outcome == null) R.string.tap_say_the_line_tap_again else null
            SpeakPhase.RECORDING -> R.string.tap_when_done
            SpeakPhase.READING -> R.string.listening_back
            SpeakPhase.HEARD_NOTHING -> R.string.didn_t_catch_that_try_again
            SpeakPhase.MIC_OFF -> R.string.microphone_is_off_for_this_app_in_settings
        }
        if (hint != null) {
            Text(stringResource(hint), style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        if (transcript != null && outcome != null) {
            Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(stringResource(R.string.you_said_f105ab), style = MaterialTheme.typography.labelMedium,
                    fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Row(verticalAlignment = Alignment.Top) {
                    Text(transcript, Modifier.weight(1f), style = MaterialTheme.typography.bodyLarge)
                    if (score != null) {
                        Text("$score", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold,
                            color = if (outcome == true) RIGHT_GREEN else MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
        }
        if (outcome == null && phase in setOf(SpeakPhase.IDLE, SpeakPhase.HEARD_NOTHING, SpeakPhase.MIC_OFF)) {
            TextButton(onClick = onSkip) {
                Text(stringResource(R.string.skip), style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

@Composable
private fun BottomBar(item: WeeklyTestItem, outcome: Boolean?, isLast: Boolean, canCheck: Boolean,
                      onCheck: () -> Unit, onContinue: () -> Unit) {
    val tiles = item.kind == WeeklyTestItem.Kind.BUILD || item.kind == WeeklyTestItem.Kind.LISTEN ||
        item.kind == WeeklyTestItem.Kind.GRAMMAR
    val rewrite = item.kind == WeeklyTestItem.Kind.REWRITE || item.kind == WeeklyTestItem.Kind.TRANSLATE
    if (outcome == null && !tiles && !rewrite) return
    Column(Modifier.fillMaxWidth().background(AppSurfaces.ground).bottomBarInsets()) {
        HorizontalDivider()
        Column(Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)) {
            if (outcome != null) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Icon(if (outcome) Icons.Filled.CheckCircle else Icons.Filled.Cancel, contentDescription = null,
                        tint = if (outcome) RIGHT_GREEN else WRONG_RED, modifier = Modifier.size(24.dp))
                    Column {
                        Text(stringResource(if (outcome) R.string.right else R.string.not_this_time),
                            style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
                        if (!outcome && !tiles && !rewrite) {
                            Text(item.answer, style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                }
                Button(onClick = onContinue, modifier = Modifier.fillMaxWidth().height(50.dp),
                    colors = if (outcome) ButtonDefaults.buttonColors(containerColor = RIGHT_GREEN)
                        else ButtonDefaults.buttonColors()) {
                    Text(stringResource(if (isLast) R.string.see_result else R.string.continue_))
                }
            } else {
                Button(onClick = onCheck, enabled = canCheck, modifier = Modifier.fillMaxWidth().height(50.dp)) {
                    Text(stringResource(R.string.check))
                }
            }
        }
    }
}

// ── Result

/**
 * The finished test: the host, one line of praise, the score against last
 * week's, then what was missed — the only list worth reading, because it is
 * what comes back in review. Two exits: try the misses again on the spot, or
 * leave them to the decks.
 */
@Composable
private fun WeeklyTestResult(test: WeeklyTest, isRetry: Boolean, language: String, onRetry: () -> Unit) {
    val context = LocalContext.current
    val shownAt = remember { System.currentTimeMillis() }
    var previous by remember { mutableStateOf<WeeklyTest?>(null) }
    var weeks by remember { mutableIntStateOf(0) }
    LaunchedEffect(test.id) {
        val all = WeeklyTestStore.shared(context).load(language)
        weeks = WeeklyTestStore.weekStreak(all, WeeklyTestSettings.schedule(context))
        previous = if (test.isMonthly || isRetry) null
            else all.firstOrNull { !it.isMonthly && it.isFinished && it.id != test.id && it.createdAt < test.createdAt }
    }
    val ratio = if (test.total == 0) 0.0 else test.score.toDouble() / test.total
    val wrong = test.answers.filter { !it.correct }.map { it.itemId }.toSet()
    val missed = test.items.filter { it.id in wrong }

    Column(Modifier.fillMaxSize()) {
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Column(Modifier.fillMaxWidth().padding(vertical = 16.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(4.dp)) {
                WeeklyTestCharacter(if (ratio >= 0.8) WeeklyTestHost.Mood.HAPPY else WeeklyTestHost.Mood.WAITING,
                    shownAt)
                Spacer(Modifier.height(10.dp))
                val headline = when {
                    isRetry -> if (missed.isEmpty()) R.string.got_them_all else R.string.closer
                    ratio >= 0.9 -> R.string.a_strong_week
                    ratio >= 0.6 -> R.string.a_good_week
                    else -> R.string.the_week_is_in_the_book
                }
                Text(stringResource(headline), style = MaterialTheme.typography.titleLarge,
                    fontWeight = FontWeight.SemiBold)
                Text(stringResource(R.string.lld_of_lld, test.score, test.total),
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                previous?.let {
                    Text(stringResource(R.string.last_week_lld_lld, it.score, it.total),
                        style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.outline)
                }
                if (!isRetry && weeks >= 2) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp),
                        modifier = Modifier.padding(top = 4.dp)) {
                        Icon(Icons.Filled.EventNote, contentDescription = null, modifier = Modifier.size(16.dp),
                            tint = MaterialTheme.colorScheme.onSurfaceVariant)
                        Text(stringResource(R.string.lld_weeks_running, weeks), style = MaterialTheme.typography.bodySmall,
                            fontWeight = FontWeight.Medium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
            if (missed.isEmpty()) {
                GroupedCard {
                    Row(Modifier.fillMaxWidth().padding(16.dp), verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        Icon(Icons.Filled.CheckCircle, contentDescription = null,
                            tint = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.size(20.dp))
                        Text(stringResource(if (isRetry) R.string.all_of_them_this_time else R.string.nothing_missed),
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
                if (!isRetry) GroupedFooter(stringResource(R.string.everything_here_waits_three_days_before_it_comes_back))
            } else {
                GroupedSectionHeader(stringResource(if (isRetry) R.string.still_missed else R.string.missed))
                GroupedCard {
                    missed.forEachIndexed { i, item ->
                        if (i > 0) GroupedRowDivider()
                        Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp),
                            horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            Icon(kindIcon(item.kind), contentDescription = null, modifier = Modifier.size(20.dp),
                                tint = MaterialTheme.colorScheme.onSurfaceVariant)
                            Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                                Text(item.answer, style = MaterialTheme.typography.bodyLarge)
                                if (item.kind in setOf(WeeklyTestItem.Kind.MEANING, WeeklyTestItem.Kind.BUILD,
                                        WeeklyTestItem.Kind.GRAMMAR, WeeklyTestItem.Kind.UPGRADE) &&
                                    item.prompt.isNotEmpty()) {
                                    Text(if (item.kind != WeeklyTestItem.Kind.MEANING)
                                        stringResource(R.string.you_said_b35fdb, item.prompt) else item.prompt,
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                                }
                            }
                        }
                    }
                }
                if (!isRetry) GroupedFooter(stringResource(R.string.these_are_back_in_your_review_due_now))
            }
            Spacer(Modifier.height(16.dp))
        }
        if (missed.isNotEmpty()) {
            Column(Modifier.fillMaxWidth().bottomBarInsets().padding(horizontal = 20.dp, vertical = 12.dp)) {
                Button(onClick = onRetry, modifier = Modifier.fillMaxWidth().height(50.dp)) {
                    Text(stringResource(R.string.try_the_missed_ones_again))
                }
            }
        }
    }
}
