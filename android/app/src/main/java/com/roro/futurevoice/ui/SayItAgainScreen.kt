package com.roro.futurevoice.ui

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.draw.clip
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.FastForward
import androidx.compose.material.icons.filled.GraphicEq
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.MicOff
import androidx.compose.material.icons.filled.RecordVoiceOver
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material3.AlertDialog
import com.roro.futurevoice.ui.brand.IosButton as Button
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
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
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import com.roro.futurevoice.R
import com.roro.futurevoice.audio.Mp3Player
import com.roro.futurevoice.audio.WavRecorder
import com.roro.futurevoice.data.PhraseAudioStore
import com.roro.futurevoice.data.PracticeLog
import com.roro.futurevoice.data.SayItAgainScript
import com.roro.futurevoice.data.ShadowAttempt
import com.roro.futurevoice.data.ShadowAttemptStore
import com.roro.futurevoice.data.ShadowPicks
import com.roro.futurevoice.data.StoreJson
import com.roro.futurevoice.data.TalkCurriculum
import com.roro.futurevoice.data.WordSplitter
import com.roro.futurevoice.talk.Scenario
import com.roro.futurevoice.talk.Session
import com.roro.futurevoice.talk.ShadowScore
import com.roro.futurevoice.talk.ShadowTranscriber
import com.roro.futurevoice.talk.SpokenWords
import com.roro.futurevoice.talk.StockPerson
import com.roro.futurevoice.ui.brand.AppSurfaces
import com.roro.futurevoice.ui.brand.Books
import com.roro.futurevoice.ui.brand.DialogueLine
import com.roro.futurevoice.ui.brand.DialogueSpeaker
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.joinAll
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import java.io.File

/**
 * What a run plays for the OTHER side's line — the audio that already
 * exists, never a new synthesis.
 */
sealed interface SayItAgainAudio {
    /** A recording kept on disk (a talk's `turn-audio/<id>.wav`). */
    class OnDisk(val file: File) : SayItAgainAudio
    /** A take in the phrase cache (a scene's counterpart line). */
    class Cached(val bytes: ByteArray) : SayItAgainAudio
}

/**
 * What is being run again — a finished talk or a Watch book's scene (iOS
 * `SayItAgainView.Source`). Everything that differs between the two is
 * resolved here, so the run itself never asks which one it is.
 */
class SayItAgainSource(
    /** "talk" / "scene" — telemetry only. */
    val kind: String,
    val title: String,
    val targetLanguage: String,
    /** Name on the OTHER side's lines, already localized. */
    val otherName: String,
    val steps: List<SayItAgainScript.Step>,
    /** The other side's line as it was ALREADY recorded. Null means the line
     *  is read, never synthesized: a talk replays for free and a scene is
     *  claimed by count, so a synthesis here would be the one metered act on
     *  a screen that promises none. Called off the main thread. */
    val audio: (SayItAgainScript.Step) -> SayItAgainAudio?,
) {
    companion object {
        /**
         * A finished talk. The fluent self's lines play from the recordings
         * the call left (`Turn.audioURL`, else `turn-audio/<id>.wav`); a line
         * whose recording didn't survive falls back to the phrase cache under
         * the learner's own voice (the cached greeting lives there), and past
         * that it is READ.
         */
        fun talk(context: Context, session: Session, otherName: String): SayItAgainSource {
            val app = context.applicationContext
            val byId = session.turns.associateBy { it.id }
            return SayItAgainSource(
                kind = "talk",
                title = session.displayTitle ?: app.getString(R.string.conversation),
                targetLanguage = session.targetLanguage,
                otherName = otherName,
                steps = SayItAgainScript.build(session) { id ->
                    File(File(app.filesDir, "turn-audio"), "$id.wav").let { it.isFile && it.length() > 44 }
                },
                audio = { step ->
                    val turn = byId[step.id]
                    val recorded = listOfNotNull(
                        turn?.audioURL?.let(::File),
                        File(File(app.filesDir, "turn-audio"), "${step.id}.wav"),
                    ).firstOrNull { it.isFile && it.length() > 44 }
                    recorded?.let { SayItAgainAudio.OnDisk(it) }
                        ?: PhraseAudioStore.shared(app).ownVoiceLineage.firstOrNull()?.let { voice ->
                            PhraseAudioStore.shared(app).data(step.text, voice)
                        }?.let { SayItAgainAudio.Cached(it) }
                },
            )
        }

        /**
         * A Watch book's scene. The counterpart's lines play from the phrase
         * cache under the SAME key Watch wrote them with (text + the scene's
         * preset voice), so a scene watched once runs here without a request.
         */
        fun scene(context: Context, scenario: Scenario, language: String): SayItAgainSource? {
            val cur = scenario.curriculum ?: return null
            val app = context.applicationContext
            val cast = StockPerson.by(scenario.voicePresetId)
            return SayItAgainSource(
                kind = "scene",
                title = cur.dialogueTitle?.takeIf { it.isNotBlank() } ?: scenario.cardTitle,
                targetLanguage = language,
                // The name Watch puts on the other side's lines.
                otherName = scenario.role.takeIf { it.isNotBlank() }
                    ?.substringBefore(" —")?.trim() ?: cast.name,
                steps = SayItAgainScript.build(cur.dialogue.orEmpty(), cur.shadowLines),
                audio = { step ->
                    PhraseAudioStore.shared(app).data(step.text, cast.voiceId)
                        ?.let { SayItAgainAudio.Cached(it) }
                },
            )
        }
    }
}

/** Where a run is. Scoring is deliberately NOT a phase: a take is graded
 *  behind the other side's answer, which is the pause a call already has. */
private enum class SayPhase { INTRO, LISTENING, READING, FINISHED }

/** One read line. `HEARD_NOTHING` is not a 0 — nothing is saved, counted or
 *  scored, the same rule the shadow screen holds. */
private data class SayTake(val score: Int? = null, val outcome: Outcome, val heard: String = "") {
    enum class Outcome { SCORED, HEARD_NOTHING, SKIPPED }
}

/** How long the prompter waits for the learner to START before letting the
 *  conversation move on. Generous — the run's promise is that it doesn't stop. */
private const val FIRST_VOICE_MS = 8_000L
/** Earliest a read can end, per word — measured from the FIRST WORD. */
private const val READ_MS_PER_WORD = 380
/** The only thing that ends a take on a learner still talking: a room that
 *  never falls quiet. Far past any line a turn can be (iOS 0952451). */
private const val MAX_READ_MS = 60_000L
/** Pause for an other-side line whose recording didn't survive. */
private const val SILENT_READ_MS_PER_WORD = 380

/**
 * Say it again (다시 말하기) — the talk, run AGAIN, with the learner in it
 * (iOS `SayItAgainView`, 2026-09-27). Their line comes up on the prompter,
 * they read it out loud, the fluent self's stored answer plays, the next line
 * comes up. Live shadowing in the shape of the call it came from. A Watch
 * book gets the same door, reading the fluent self's side of its scene.
 *
 * - **Nothing is synthesized and nothing is metered**, so there is no billing
 *   gate: the other side's lines are the audio already on disk, and the only
 *   network call is the free audio-grounded read of a take.
 * - **A score walks through the one door**: `ShadowTranscriber` reads the
 *   take, `ShadowScore` grades it. No coach call (twenty lines would be
 *   twenty calls for text nobody reads mid-run); rhythm is null by
 *   construction — nobody ever spoke a correction, so there is no beat.
 * - **It never stops.** A weak read is scored, shown and left behind; every
 *   read line keeps a Retry for as long as the screen is open.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SayItAgainScreen(
    source: SayItAgainSource,
    onClose: () -> Unit,
    /** Capture only: park the screen in "reading" or "done". */
    captureStage: String? = null,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    // No `source`: the run is one ANALYTICS event, not one per line played.
    val player = remember { Mp3Player(context.cacheDir) }
    val recorder = remember { WavRecorder() }
    val steps = source.steps
    val language = source.targetLanguage

    var phase by remember { mutableStateOf(SayPhase.INTRO) }
    var index by remember { mutableIntStateOf(0) }
    val takes = remember { mutableStateMapOf<String, SayTake>() }
    val scoreJobs = remember { HashMap<String, Job>() }
    var runJob by remember { mutableStateOf<Job?>(null) }
    /** What the prompter shows — separate from `index` so a one-off retry
     *  from the finished screen doesn't wind the history back. */
    var promptStep by remember { mutableStateOf<SayItAgainScript.Step?>(null) }
    var oneOffRetry by remember { mutableStateOf(false) }
    var skipRequested by remember { mutableStateOf(false) }
    var micError by remember { mutableStateOf<String?>(null) }
    /** A finished run whose event hasn't been sent yet (it waits for the
     *  last takes' scores). */
    var pendingLog by remember { mutableStateOf<(() -> Unit)?>(null) }

    val spokenCount = steps.count { it.isSpoken }
    val correctedCount = steps.count { it.isSpoken && it.isCorrected }
    val scores = takes.values.mapNotNull { it.score }
    val readCount = scores.size
    val averageScore = if (scores.isEmpty()) null else scores.sum() / scores.size

    fun flushLog() {
        pendingLog?.invoke()
        pendingLog = null
    }

    // A run holds the mic and the screen for minutes — don't let it sleep.
    val view = LocalView.current
    DisposableEffect(Unit) {
        view.keepScreenOn = true
        onDispose {
            view.keepScreenOn = false
            flushLog()
            runJob?.cancel()
            scoreJobs.values.forEach { it.cancel() }
            player.stop()
            runCatching { recorder.stop() }
        }
    }

    LaunchedEffect(captureStage) {
        val spoken = steps.withIndex().filter { it.value.isSpoken }
        when (captureStage) {
            "reading" -> spoken.firstOrNull()?.let { (i, step) ->
                index = i; promptStep = step; phase = SayPhase.READING
            }
            "done" -> {
                spoken.forEachIndexed { n, (_, step) ->
                    takes[step.id] = SayTake(if (n == 0) 92 else 61, SayTake.Outcome.SCORED,
                        heard = "How relaxed I stay, even on hard question.")
                }
                index = steps.lastIndex; phase = SayPhase.FINISHED
            }
        }
    }

    // ── The run

    suspend fun waitUnlessSkipped(ms: Long) {
        val deadline = System.currentTimeMillis() + ms
        while (!skipRequested && System.currentTimeMillis() < deadline) delay(100)
    }

    fun silentPause(text: String): Long =
        (WordSplitter.count(text, language) * SILENT_READ_MS_PER_WORD).coerceIn(1_500, 8_000).toLong()

    /** The other side's answer — the audio that call already produced, never
     *  a new synthesis. A line whose recording didn't survive is READ. */
    suspend fun listenStep(step: SayItAgainScript.Step) {
        phase = SayPhase.LISTENING
        skipRequested = false
        val audio = withContext(Dispatchers.IO) { runCatching { source.audio(step) }.getOrNull() }
        if (audio == null) { waitUnlessSkipped(silentPause(step.text)); return }
        val played = coroutineScope {
            val playing = async {
                runCatching {
                    when (audio) {
                        is SayItAgainAudio.OnDisk -> player.play(audio.file)
                        is SayItAgainAudio.Cached -> player.play(audio.bytes)
                    }
                }.isSuccess
            }
            while (playing.isActive && !skipRequested) delay(100)
            if (playing.isActive) { playing.cancel(); player.stop(); true } else playing.await()
        }
        if (!played) waitUnlessSkipped(silentPause(step.text))
    }

    /** True once the learner actually said something: waits for their FIRST
     *  word, then for the line's own length, then for the shadow surface's
     *  1.5 s of quiet (someone reading a line for the first time breathes
     *  more than a talker does). */
    suspend fun waitForReadToEnd(text: String): Boolean {
        val firstDeadline = System.currentTimeMillis() + FIRST_VOICE_MS
        var voiced = false
        while (!skipRequested && System.currentTimeMillis() < firstDeadline) {
            if (recorder.level >= VOICED_LEVEL) { voiced = true; break }
            delay(100)
        }
        if (skipRequested) return false
        if (!voiced) return false

        val lineMs = maxOf(1_200, WordSplitter.count(text, language) * READ_MS_PER_WORD)
        val began = System.currentTimeMillis()
        val earliest = began + lineMs
        // Only silence ends a take. The line's length used to be a hard stop
        // too (~1.5x the estimate), and a whole turn read for the first time
        // runs past 380 ms a word easily, so the take was cut mid-sentence.
        val hardStop = began + MAX_READ_MS
        var lastVoiced = began
        while (!skipRequested && System.currentTimeMillis() < hardStop) {
            val now = System.currentTimeMillis()
            if (recorder.level >= VOICED_LEVEL) lastVoiced = now
            if (now >= earliest && now - lastVoiced >= STILL_SPEAKING_MS) break
            delay(100)
        }
        return !skipRequested
    }

    /** Grade the take. Only a line that IS review material becomes an
     *  attempt on file; everything else is counted as a rep and its
     *  recording dropped rather than left under a name nothing references. */
    suspend fun score(step: SayItAgainScript.Step, file: File) {
        val read = ShadowTranscriber.read(file, language)
        // A retry cancels the task it replaced, but the read it was inside
        // finishes anyway — its verdict must not land on the NEW take.
        if (!currentCoroutineContextActive()) { file.delete(); return }
        val heard = read.text.trim()
        if (heard.isEmpty()) {
            file.delete()
            takes[step.id] = SayTake(outcome = SayTake.Outcome.HEARD_NOTHING)
            return
        }
        val analysis = ShadowScore.analyze(step.text, heard, language)
        takes[step.id] = SayTake(analysis.score, SayTake.Outcome.SCORED, heard)
        // One take, one rep — the unit the shadow screen counts.
        PracticeLog.record(context, PracticeLog.Kind.SHADOW, finished = true)
        val attemptId = step.attemptId
        if (attemptId == null) {
            withContext(Dispatchers.IO) { file.delete() }
            return
        }
        ShadowAttemptStore.shared(context).add(ShadowAttempt(
            turnId = attemptId,
            targetText = step.text,
            learnerTranscript = heard,
            recordingFilename = file.absolutePath,
            matchScore = analysis.score,
            rhythmScore = null,
        ), language)
    }

    /** The learner's line. The mic opens with the line, the take ends when
     *  they go quiet, and the GRADING runs on its own so the other side
     *  answers immediately. */
    suspend fun readStep(step: SayItAgainScript.Step) {
        phase = SayPhase.READING
        promptStep = step
        skipRequested = false
        takes.remove(step.id)
        scoreJobs.remove(step.id)?.cancel()
        player.stop()
        val file = File(File(context.filesDir, "shadow-takes"), StoreJson.newId() + ".wav")
        if (runCatching { recorder.start(file) }.isFailure) {
            micError = context.getString(R.string.microphone_or_speech_permission_denied)
            takes[step.id] = SayTake(outcome = SayTake.Outcome.SKIPPED)
            return
        }
        var spoke = false
        var completed = false
        try {
            spoke = waitForReadToEnd(step.text)
            // Tail grace — "Done reading" lands mid-syllable, and a clipped
            // tail reads as a deletion in the diff.
            delay(300)
            completed = true
        } finally {
            withContext(NonCancellable + Dispatchers.IO) {
                runCatching { recorder.stop() }
                if (!completed) file.delete()
            }
        }
        if (!spoke) {
            withContext(Dispatchers.IO) { file.delete() }
            takes[step.id] = SayTake(outcome = if (skipRequested) SayTake.Outcome.SKIPPED
                else SayTake.Outcome.HEARD_NOTHING)
            return
        }
        scoreJobs[step.id] = scope.launch { score(step, file) }
    }

    fun logWhenScored() {
        val kind = source.kind
        val log = {
            val s = takes.values.mapNotNull { it.score }
            com.roro.futurevoice.core.Telemetry.log("say_again_run", mapOf(
                "kind" to kind,
                "lines" to spokenCount.toString(),
                "read" to s.size.toString(),
                "avg" to (if (s.isEmpty()) "" else (s.sum() / s.size).toString()),
            ))
        }
        pendingLog = log
        scope.launch {
            // The last line's score is still being read; wait for it rather
            // than reporting a run one take short.
            withTimeoutOrNull(25_000) { scoreJobs.values.toList().joinAll() }
            if (pendingLog === log) flushLog()
        }
    }

    /** Walk the script. Every step awaits its own end, so the loop IS the
     *  pacing — there is no timer anywhere on this screen. */
    suspend fun run(from: Int) {
        oneOffRetry = false
        for (i in from until steps.size) {
            index = i
            val step = steps[i]
            if (step.isSpoken) readStep(step) else listenStep(step)
        }
        index = maxOf(0, steps.lastIndex)
        phase = SayPhase.FINISHED
        // A finished run is what a routine's say-it-again block counts.
        com.roro.futurevoice.data.ActivityEventLog.record(context,
            com.roro.futurevoice.data.ActivityEventLog.Kind.SAY_IT_AGAIN)
        logWhenScored()
    }

    fun start(from: Int) {
        flushLog()
        runJob?.cancel()
        runJob = scope.launch { run(from) }
    }

    /** Re-read one line. Mid-run it rejoins the script there — the answer
     *  after it plays again, which IS the conversation. On the finished
     *  screen it is a single take and the page stays where it is. */
    fun retry(step: SayItAgainScript.Step) {
        val i = steps.indexOfFirst { it.id == step.id }
        if (i < 0) return
        val wasFinished = phase == SayPhase.FINISHED
        flushLog()
        runJob?.cancel()
        player.stop()
        takes.remove(step.id)
        runJob = scope.launch {
            if (wasFinished) {
                oneOffRetry = true
                readStep(step)
                oneOffRetry = false
                phase = SayPhase.FINISHED
            } else run(i)
        }
    }

    // The mic permission is asked at the first tap that needs it.
    var afterPermission by remember { mutableStateOf<(() -> Unit)?>(null) }
    val micPermission = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted ->
        val next = afterPermission
        afterPermission = null
        if (granted) next?.invoke()
        else micError = context.getString(R.string.microphone_or_speech_permission_denied)
    }
    fun withMic(action: () -> Unit) {
        val ok = ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) ==
            PackageManager.PERMISSION_GRANTED
        if (ok) action() else {
            afterPermission = action
            micPermission.launch(Manifest.permission.RECORD_AUDIO)
        }
    }

    fun close() {
        flushLog()
        runJob?.cancel()
        scoreJobs.values.forEach { it.cancel() }
        player.stop()
        runCatching { recorder.stop() }
        onClose()
    }

    // A back gesture mid-take would leave the mic hot; Close is explicit.
    BackHandler(enabled = phase != SayPhase.READING) { close() }
    BackHandler(enabled = phase == SayPhase.READING) { }

    // ── The conversation so far: everything already played or read. While
    // the learner is READING, the current line lives on the prompter only.
    val history = when (phase) {
        SayPhase.INTRO -> emptyList()
        else -> {
            val upTo = if (phase == SayPhase.READING && !oneOffRetry) index else index + 1
            steps.take(upTo.coerceIn(0, steps.size))
        }
    }
    val listState = rememberLazyListState()
    LaunchedEffect(history.size, phase) {
        if (history.isNotEmpty()) listState.animateScrollToItem(history.lastIndex)
    }

    Scaffold(
        containerColor = AppSurfaces.ground,
        topBar = {
            CenterAlignedTopAppBar(
                colors = AppSurfaces.topBarColors(),
                title = { Text(stringResource(R.string.say_it_again),
                    style = MaterialTheme.typography.titleMedium) },
                actions = {
                    TextButton(onClick = { close() }) { Text(stringResource(R.string.close)) }
                },
            )
        },
        bottomBar = {
            Column(Modifier.fillMaxWidth().bottomBarInsets()) {
                if (phase != SayPhase.INTRO) HorizontalDivider()
                Column(Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 14.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    when (phase) {
                        SayPhase.INTRO -> IntroPanel(spokenCount) { withMic { start(0) } }
                        SayPhase.LISTENING -> ListeningPanel(source.otherName) { skipRequested = true }
                        SayPhase.READING -> ReadingPanel(promptStep,
                            onSkip = { skipRequested = true })
                        SayPhase.FINISHED -> FinishedPanel(
                            readCount = readCount, spokenCount = spokenCount, average = averageScore,
                            onRunAgain = { withMic {
                                // The finished run is reported BEFORE its
                                // takes are wiped, and no late score may land
                                // on the new one.
                                flushLog()
                                scoreJobs.values.forEach { it.cancel() }
                                scoreJobs.clear()
                                takes.clear()
                                start(0)
                            } },
                            onDone = { close() })
                    }
                }
            }
        },
    ) { padding ->
        if (phase == SayPhase.INTRO) {
            IntroHero(source, spokenCount, correctedCount,
                Modifier.padding(padding).fillMaxSize().verticalScroll(rememberScrollState()))
        } else {
            LazyColumn(
                state = listState,
                modifier = Modifier.padding(padding).fillMaxSize(),
                contentPadding = PaddingValues(20.dp),
                verticalArrangement = Arrangement.spacedBy(14.dp),
            ) {
                itemsIndexed(history, key = { _, s -> s.id }) { i, step ->
                    HistoryRow(step, source.otherName, takes[step.id],
                        isCurrent = phase == SayPhase.LISTENING && i == index,
                        onRetry = { withMic { retry(step) } })
                }
            }
        }
    }

    micError?.let { message ->
        AlertDialog(
            onDismissRequest = { micError = null },
            title = { Text(stringResource(R.string.something_went_wrong)) },
            text = { Text(message) },
            confirmButton = { TextButton(onClick = { micError = null }) { Text(stringResource(R.string.ok)) } },
        )
    }
}

/** `isActive` of the calling coroutine, readable from a local suspend fun. */
private suspend fun currentCoroutineContextActive(): Boolean =
    kotlin.coroutines.coroutineContext.isActive

@Composable
private fun HistoryRow(
    step: SayItAgainScript.Step,
    otherName: String,
    take: SayTake?,
    isCurrent: Boolean,
    onRetry: () -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        DialogueLine(
            speaker = if (step.isSpoken) DialogueSpeaker.USER else DialogueSpeaker.OTHER,
            name = if (step.isSpoken) stringResource(R.string.you) else otherName,
            isCurrent = isCurrent,
            accessory = { if (step.isSpoken) TakeAccessory(take, onRetry) },
        ) {
            if (step.isCorrected) Text(highlightedCorrection(step.text, step.said))
            else Text(step.text)
        }
        // A weak read is told in the learner's own words as well as a number:
        // which words drifted is the only actionable half of a low score.
        val score = take?.score
        if (step.isSpoken && score != null && score < ShadowPicks.RETRY_THRESHOLD &&
            take.heard.isNotEmpty()) {
            Text(stringResource(R.string.heard) + ": " + take.heard,
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.End,
                modifier = Modifier.fillMaxWidth())
        }
    }
}

@Composable
private fun TakeAccessory(take: SayTake?, onRetry: () -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        when (take?.outcome) {
            SayTake.Outcome.SCORED -> {
                val s = take.score ?: 0
                Icon(if (s >= TalkCurriculum.SHADOW_MASTERY_SCORE) Icons.Filled.CheckCircle
                    else Icons.Filled.GraphicEq, contentDescription = null,
                    modifier = Modifier.size(14.dp), tint = sayScoreColor(s))
                Text("$s", style = MaterialTheme.typography.labelMedium,
                    fontWeight = FontWeight.SemiBold, color = sayScoreColor(s))
            }
            SayTake.Outcome.HEARD_NOTHING -> {
                Icon(Icons.Filled.MicOff, contentDescription = null, modifier = Modifier.size(14.dp),
                    tint = MaterialTheme.colorScheme.onSurfaceVariant)
                Text(stringResource(R.string.didn_t_hear_that),
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            SayTake.Outcome.SKIPPED -> {
                Icon(Icons.Filled.FastForward, contentDescription = null, modifier = Modifier.size(14.dp),
                    tint = MaterialTheme.colorScheme.onSurfaceVariant)
                Text(stringResource(R.string.skipped),
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            null -> CircularProgressIndicator(Modifier.size(12.dp), strokeWidth = 1.5.dp)
        }
        if (take != null) {
            OutlinedButton(onClick = onRetry,
                contentPadding = PaddingValues(horizontal = 10.dp, vertical = 0.dp),
                modifier = Modifier.padding(start = 2.dp)) {
                Icon(Icons.Filled.Refresh, contentDescription = null, modifier = Modifier.size(14.dp))
                Spacer(Modifier.width(4.dp))
                Text(stringResource(R.string.retry), style = MaterialTheme.typography.labelMedium)
            }
        }
    }
}

/** The cover of a run: what is about to happen, and how much of it. */
@Composable
private fun IntroHero(source: SayItAgainSource, spoken: Int, corrected: Int, modifier: Modifier) {
    Column(modifier.padding(horizontal = 28.dp).padding(top = 48.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Icon(Icons.Filled.RecordVoiceOver, contentDescription = null,
            tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(40.dp))
        Text(source.title, style = MaterialTheme.typography.titleLarge,
            fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center)
        // Says what the run IS: the whole conversation again, with the
        // learner's part spoken right — not a list of fixes.
        Text(stringResource(if (source.kind == "scene")
            R.string.do_this_scene_again_from_the_start_and_say_your_part_out_lou_3f2c37
        else R.string.do_this_talk_again_from_the_start_and_say_your_part_the_corr_5ece3b),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center)
        if (corrected > 0) {
            Row(verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Icon(Icons.Filled.AutoAwesome, contentDescription = null, modifier = Modifier.size(14.dp),
                    tint = MaterialTheme.colorScheme.onSurfaceVariant)
                Text(stringResource(R.string.lld_lines_lld_corrected, spoken, corrected),
                    style = MaterialTheme.typography.labelLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

@Composable
private fun IntroPanel(spoken: Int, onStart: () -> Unit) {
    if (spoken == 0) {
        Text(stringResource(R.string.nothing_to_read_in_this_talk),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth())
    } else {
        Button(onClick = onStart, modifier = Modifier.fillMaxWidth(),
            contentPadding = PaddingValues(vertical = 14.dp)) {
            Icon(Icons.Filled.RecordVoiceOver, contentDescription = null, modifier = Modifier.size(18.dp))
            Spacer(Modifier.width(8.dp))
            Text(stringResource(R.string.start))
        }
    }
}

@Composable
private fun ListeningPanel(otherName: String, onSkip: () -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Icon(Icons.Filled.GraphicEq, contentDescription = null,
            tint = MaterialTheme.colorScheme.primary)
        Text(stringResource(R.string.is_answering, otherName),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            maxLines = 1, modifier = Modifier.weight(1f))
        OutlinedButton(onClick = onSkip) { Text(stringResource(R.string.skip)) }
    }
}

/**
 * The teleprompter (iOS `5b24d43`). A card washed in the learner's own
 * Futureself colour with the line in a deep shade of the same hue
 * (tone-on-tone), so it reads as a script held up in front of them rather
 * than one more row of the transcript above it. There is no "done" button:
 * the take ends on its own when they go quiet (`waitForReadToEnd`), the same
 * way a call turn does, so a button would only ask them to confirm what the
 * mic already knows. Skip stays, small, for a line they don't want to say.
 */
@Composable
private fun ReadingPanel(step: SayItAgainScript.Step?, onSkip: () -> Unit) {
    val context = LocalContext.current
    val theme = com.roro.futurevoice.ui.brand.FutureselfTheme.live.value
        ?: com.roro.futurevoice.ui.brand.FutureselfTheme.stored(context)
    val dark = androidx.compose.foundation.isSystemInDarkTheme()
    val tint = theme.tint()
    val ink = promptInk(tint, dark)
    val mono = theme == com.roro.futurevoice.ui.brand.FutureselfTheme.MONO
    // Mono's light accent is near-black charcoal, so the colours' 14% wash
    // comes out a muddy mid-grey there; it gets a paper-light 5% instead.
    val wash = if (mono && !dark) 0.05f else 0.14f
    // Mono's accent IS its ink, so the fixed words — drawn in the accent —
    // would vanish into the line; there the rest of the line steps back.
    val lineInk = if (mono) ink.copy(alpha = 0.55f) else ink
    val shape = RoundedCornerShape(22.dp)
    Column(
        Modifier.fillMaxWidth()
            .clip(shape)
            .background(tint.copy(alpha = wash))
            .border(1.dp, tint.copy(alpha = wash * 2), shape)
            .padding(horizontal = 20.dp, vertical = 18.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Box(Modifier.size(8.dp).clip(CircleShape).background(Color(0xFFFF3B30)))
            Text(stringResource(if (step?.isCorrected == true) R.string.say_it_the_fixed_way
                else R.string.say_your_line),
                style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.SemiBold,
                color = ink.copy(alpha = 0.7f), modifier = Modifier.weight(1f))
            Text(stringResource(R.string.skip),
                style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.SemiBold,
                color = ink.copy(alpha = 0.7f),
                modifier = Modifier.clip(RoundedCornerShape(6.dp)).clickable(onClick = onSkip)
                    .padding(horizontal = 4.dp, vertical = 2.dp))
        }
        if (step != null) {
            Text(if (step.isCorrected) highlightedCorrection(step.text, step.said)
                else buildAnnotatedString { append(step.text) },
                style = MaterialTheme.typography.headlineSmall.copy(
                    lineHeight = MaterialTheme.typography.headlineSmall.lineHeight * 1.1f),
                fontWeight = FontWeight.SemiBold, color = lineInk,
                textAlign = androidx.compose.ui.text.style.TextAlign.Center,
                modifier = Modifier.fillMaxWidth())
            if (step.note.isNotBlank()) {
                Text(step.note, style = MaterialTheme.typography.bodySmall,
                    color = ink.copy(alpha = 0.7f),
                    textAlign = androidx.compose.ui.text.style.TextAlign.Center)
            }
        }
        // Says how the take ends, since nothing on the card does it.
        Row(verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Icon(Icons.Filled.GraphicEq, contentDescription = null, modifier = Modifier.size(14.dp),
                tint = ink.copy(alpha = 0.5f))
            Text(stringResource(R.string.say_again_moves_on), style = MaterialTheme.typography.labelMedium,
                color = ink.copy(alpha = 0.5f))
        }
    }
}

/** The palette's hue deep enough to READ on its own wash (iOS
 *  `FutureselfTheme.ink`): light mode pulls the accent toward black, dark
 *  mode toward white, so text keeps its contrast on every palette, Amber
 *  included, whose raw accent is too pale to read on its own wash. */
private fun promptInk(tint: Color, dark: Boolean): Color {
    val toward = if (dark) 1f else 0f
    val k = if (dark) 0.55f else 0.5f
    return Color(red = tint.red + (toward - tint.red) * k, green = tint.green + (toward - tint.green) * k,
        blue = tint.blue + (toward - tint.blue) * k, alpha = 1f)
}

@Composable
private fun FinishedPanel(
    readCount: Int, spokenCount: Int, average: Int?,
    onRunAgain: () -> Unit, onDone: () -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(10.dp),
        horizontalAlignment = Alignment.CenterHorizontally) {
        if (average != null) {
            Row(verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Icon(Icons.Filled.Verified, contentDescription = null, modifier = Modifier.size(18.dp),
                    tint = Books.mastery)
                Text(stringResource(R.string.lld_of_lld_lines_read_lld_average,
                    readCount, spokenCount, average),
                    style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold,
                    color = Books.mastery)
            }
        } else {
            Text(stringResource(R.string.nothing_was_scored_this_time_the_mic_heard_no_speech),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center)
        }
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            OutlinedButton(onClick = onRunAgain, modifier = Modifier.weight(1f),
                contentPadding = PaddingValues(vertical = 12.dp)) {
                Icon(Icons.Filled.Refresh, contentDescription = null, modifier = Modifier.size(18.dp))
                Spacer(Modifier.width(6.dp))
                Text(stringResource(R.string.run_again), maxLines = 1)
            }
            Button(onClick = onDone, modifier = Modifier.weight(1f),
                contentPadding = PaddingValues(vertical = 12.dp)) {
                Text(stringResource(R.string.done))
            }
        }
    }
}

/** The corrected line with the CHANGED words lit — compared through
 *  `SpokenWords`, so a contraction the transcriber expanded lights nothing
 *  (the same rule the call's correction card holds). */
@Composable
private fun highlightedCorrection(text: String, said: String) = run {
    val tint = MaterialTheme.colorScheme.primary
    val language = com.roro.futurevoice.data.LanguageScope.active(LocalContext.current)
    remember(text, said, tint, language) {
        correctionLine(text, said, language, SpanStyle(color = tint, fontWeight = FontWeight.SemiBold))
    }
}

/** Mastery green at the bar a take files as mastered, the accent above the
 *  retry line, orange under it — the bands the talk book draws. */
@Composable
private fun sayScoreColor(score: Int): Color = when {
    score >= TalkCurriculum.SHADOW_MASTERY_SCORE -> Books.mastery
    score >= ShadowPicks.RETRY_THRESHOLD -> MaterialTheme.colorScheme.primary
    else -> Color(0xFFFF9500)
}
