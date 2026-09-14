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
import androidx.compose.foundation.background
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
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Bookmark
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material.icons.filled.PlayCircleOutline
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Speed
import androidx.compose.material.icons.outlined.BookmarkBorder
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import com.roro.futurevoice.R
import com.roro.futurevoice.audio.LiveTranscriber
import com.roro.futurevoice.audio.Mp3Player
import com.roro.futurevoice.core.InstallSalt
import com.roro.futurevoice.data.AuthRepository
import com.roro.futurevoice.data.LanguageCatalog
import com.roro.futurevoice.data.Recency
import com.roro.futurevoice.data.SavedLine
import com.roro.futurevoice.data.SavedLineStore
import com.roro.futurevoice.data.ShadowAttempt
import com.roro.futurevoice.net.ElevenLabsClient
import com.roro.futurevoice.talk.ShadowScore
import com.roro.futurevoice.talk.WordTiming
import com.roro.futurevoice.talk.WordTimings
import com.roro.futurevoice.ui.brand.AppSurfaces
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

/**
 * Shadow one line — `ShadowDrillView`'s spine: hear the fluent self say it
 * (cached TTS: deterministic idempotency key, so replays are free), say it
 * back, get the DETERMINISTIC score (`ShadowScore`, golden-vector-verified)
 * with the target's words colored by the diff.
 *
 * The screen is the iOS one: the line IS the page, and the only control is
 * the round mic at the bottom. Tapping it counts 3-2-1-0 and then records —
 * nothing plays while the mic is hot (speaker bleed would inflate the score),
 * so the karaoke highlight running on its own clock is the tempo guide. The
 * take ends by ITSELF once the learner has gone quiet, which leaves the
 * button one meaning mid-attempt: throw this one away.
 *
 * Tap a word to scope the attempt to a phrase; tap a second to extend, tap
 * the lone selected word to go back to the whole line.
 *
 * Not here yet, and honestly absent rather than faked: the coach bullets
 * (a server call with no ported prompt engine on Android), the duration /
 * rhythm cards (they need the learner's own recording and per-word onsets,
 * which `SpeechRecognizer` never hands over while it holds the mic), and
 * playback of a past take.
 */
private enum class ShadowPhase { IDLE, COUNTDOWN, RECORDING, ANALYZING, RESULT }

/** iOS `ShadowDrillView.stillSpeakingSeconds` — a breath is 0.5–1.5 s. */
private const val STILL_SPEAKING_MS = 1_500L

/** Rough spoken length of a line, for when the real audio duration isn't
 *  known yet — it only ever sizes the take's own floor and ceiling. */
private fun durationFromText(wordCount: Int): Int = maxOf(1_000, wordCount * 400)

/** iOS `attemptCutoffMs` — learners run long by a FACTOR, not a constant. */
private fun attemptCutoffMs(targetMs: Int): Int =
    maxOf(3_000, (targetMs * 1.5).toInt() + 2_500)

@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun ShadowScreen(
    line: String,
    voiceId: String,
    targetLanguage: String,
    onBack: () -> Unit,
    /** The line's origin turn, when it came from a talk — an attempt is
     *  filed against it so the next deal knows this one has been tried. */
    turnId: String? = null,
    /** Position in today's hand, for the header. Null = a one-off line. */
    position: Pair<Int, Int>? = null,
    /** Move to the next line of the hand. Null = this is the last one. */
    onNext: (() -> Unit)? = null,
) {
    androidx.activity.compose.BackHandler(onBack = onBack)
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val mp3 = remember { Mp3Player(context.cacheDir, source = "shadow") }
    val live = remember { LiveTranscriber(context) }

    val words = remember(line) { line.split(Regex("\\s+")).filter { it.isNotEmpty() } }

    var phase by remember { mutableStateOf(ShadowPhase.IDLE) }
    var countdown by remember { mutableIntStateOf(0) }
    var busy by remember { mutableStateOf(false) }
    var attempt by remember { mutableStateOf<ShadowScore.Analysis?>(null) }
    var said by remember { mutableStateOf("") }
    var error by remember { mutableStateOf<String?>(null) }
    /** Length of the model line, once its audio has been heard once. */
    var durationMs by remember { mutableIntStateOf(0) }
    /** Where the karaoke clock is, ms into the line (-1 = nothing running). */
    var clockMs by remember { mutableIntStateOf(-1) }
    /** Loop selection, shared by the tap handler and the attempt. */
    var selection by remember { mutableStateOf<IntRange?>(null) }
    var anchor by remember { mutableStateOf<Int?>(null) }
    /** Frozen at mic start: what THIS take is scored against. */
    var activeRange by remember { mutableStateOf<IntRange?>(null) }
    var saved by remember { mutableStateOf(false) }
    var past by remember { mutableStateOf<List<ShadowAttempt>>(emptyList()) }
    var reload by remember { mutableIntStateOf(0) }
    var take by remember { mutableStateOf<Job?>(null) }

    // Karaoke timings: estimated from the audio's own duration once it has
    // been heard, from the text's length before that — the rule is that the
    // highlight always works, and never at the cost of a second synthesis.
    val timings: List<WordTiming> = remember(line, durationMs) {
        WordTimings.estimate(line, if (durationMs > 0) durationMs else durationFromText(words.size))
    }

    // The selection as a scoring range: nil when it is stale or spans the
    // whole line (which is just whole-line practice).
    val practiceRange = selection?.takeIf { r ->
        r.last < words.size && !(r.first == 0 && r.last == words.lastIndex)
    }
    val practiceText = practiceRange?.let { words.slice(it).joinToString(" ") } ?: line

    LaunchedEffect(turnId) {
        saved = turnId != null && SavedLineStore.shared(context).isSaved(turnId)
    }
    LaunchedEffect(turnId, reload) {
        past = if (turnId == null) emptyList()
        else com.roro.futurevoice.data.ShadowAttemptStore.shared(context)
            .load(targetLanguage)
            .filter { it.turnId == turnId }
            .sortedByDescending { it.createdAt }
    }
    DisposableEffect(Unit) {
        onDispose { mp3.stop(); runCatching { live.stop() } }
    }

    fun playLine() {
        if (phase == ShadowPhase.COUNTDOWN || phase == ShadowPhase.RECORDING) return
        busy = true
        scope.launch {
            runCatching {
                val audio = ElevenLabsClient(AuthRepository()).synthesize(
                    voiceId = voiceId, text = line,
                    idempotencyKey = InstallSalt.ttsKey(line, voiceId, timestamps = false),
                    purpose = "shadow")
                busy = false
                // Karaoke follows the playback head against timings ESTIMATED
                // from this audio's own duration — no second synthesis, so a
                // cached line karaokes for free (the rule: cache first,
                // timings from free estimation, never a duplicate charge).
                val follow = launch {
                    var heard: List<WordTiming> = emptyList()
                    while (isActive) {
                        val d = mp3.durationMs
                        if (heard.isEmpty() && d > 0) {
                            heard = WordTimings.estimate(line, d)
                            durationMs = d
                        }
                        clockMs = if (heard.isEmpty()) -1 else mp3.positionMs
                        delay(40)
                    }
                }
                mp3.play(audio)
                follow.cancel()
            }.onFailure { e -> error = e.message ?: e.toString() }
            busy = false
            clockMs = -1
        }
    }

    fun cancelTake() {
        // CANCEL, not stop: ending a take is the auto-stop's job. Mid-attempt
        // this button means "this one went wrong, throw it away" — nothing is
        // scored and nothing is written.
        take?.cancel()
        take = null
        runCatching { live.stop() }
        clockMs = -1
        activeRange = null
        said = ""
        attempt = null
        phase = ShadowPhase.IDLE
    }

    fun runTake() {
        mp3.stop()
        activeRange = practiceRange
        val target = practiceText
        val range = practiceRange
        attempt = null
        said = ""
        take = scope.launch {
            // Mic FIRST: a learner who starts speaking on the beat must be
            // inside the recognition, and the countdown's silence is harmless.
            val started = runCatching {
                live.start(LanguageCatalog.sttLocale(targetLanguage)) { }
            }.isSuccess
            if (!started) {
                error = context.getString(R.string.microphone_or_speech_permission_denied)
                phase = ShadowPhase.IDLE
                return@launch
            }
            phase = ShadowPhase.COUNTDOWN
            for (n in 3 downTo 1) {
                countdown = n
                delay(700)
            }
            // "0" IS the go beat, so the start lands on a visible number.
            countdown = 0
            delay(350)

            val startedAt = System.currentTimeMillis()
            phase = ShadowPhase.RECORDING
            val offsetMs = range?.let { timings.getOrNull(it.first)?.startMs } ?: 0
            val targetMs = if (range != null && timings.size > range.last)
                maxOf(0, timings[range.last].endMs - timings[range.first].startMs)
            else if (durationMs > 0) durationMs else durationFromText(words.size)

            val karaoke = launch {
                while (isActive) {
                    clockMs = (System.currentTimeMillis() - startedAt).toInt() + offsetMs
                    delay(40)
                }
            }
            // Nothing can end the attempt before the line's OWN length — the
            // learner cannot be finished sooner, so a pause before that is
            // always mid-attempt.
            val earliest = maxOf(1_000, targetMs)
            val hardStop = startedAt + attemptCutoffMs(targetMs)
            delay(earliest.toLong())
            while (System.currentTimeMillis() < hardStop) {
                val voiced = live.lastVoicedAtMs ?: break
                if (System.currentTimeMillis() - voiced >= STILL_SPEAKING_MS) break
                delay(200)
            }
            karaoke.cancel()
            clockMs = -1

            phase = ShadowPhase.ANALYZING
            // Tail grace: the last syllable is still arriving.
            delay(300)
            val text = runCatching { live.stop() }.getOrDefault("")
            said = text
            val a = ShadowScore.analyze(target, text, targetLanguage)
            attempt = a
            phase = ShadowPhase.RESULT
            com.roro.futurevoice.core.Analytics.capture(
                "shadow_attempted", mapOf("score" to a.score))
            // File it: the score decides whether this line comes back, and
            // the rep is what the day's Shadowing goal counts.
            com.roro.futurevoice.data.ShadowAttemptStore.shared(context).add(
                ShadowAttempt(
                    turnId = turnId ?: com.roro.futurevoice.data.StoreJson.newId(),
                    targetText = target,
                    learnerTranscript = text,
                    matchScore = a.score,
                ),
                targetLanguage)
            com.roro.futurevoice.data.PracticeLog.record(
                context, com.roro.futurevoice.data.PracticeLog.Kind.SHADOW, finished = true)
            reload += 1
        }
    }

    val micPermission = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted -> if (granted) runTake() }

    fun onMicTap() {
        when (phase) {
            ShadowPhase.IDLE, ShadowPhase.RESULT -> {
                val ok = ContextCompat.checkSelfPermission(
                    context, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
                if (ok) runTake() else micPermission.launch(Manifest.permission.RECORD_AUDIO)
            }
            ShadowPhase.RECORDING -> cancelTake()
            else -> Unit
        }
    }

    fun tapWord(i: Int) {
        if (phase != ShadowPhase.IDLE && phase != ShadowPhase.RESULT) return
        // Re-tapping the lone selected word CLEARS it — the way back to
        // whole-line practice must be as easy as the way in.
        if (selection?.first == i && selection?.last == i) {
            selection = null; anchor = null; return
        }
        if (selection == null) anchor = null
        val a = anchor
        if (a != null) {
            selection = minOf(a, i)..maxOf(a, i)
            anchor = null
        } else {
            anchor = i
            selection = i..i
        }
    }

    Box(Modifier.fillMaxSize()) {
        Scaffold(
            containerColor = AppSurfaces.ground,
            topBar = {
                CenterAlignedTopAppBar(
                    colors = AppSurfaces.topBarColors(),
                    title = {
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            Text(stringResource(R.string.shadow),
                                style = MaterialTheme.typography.titleMedium)
                            position?.let { (i, total) ->
                                Text(stringResource(R.string.lld_of_lld, i, total),
                                    style = MaterialTheme.typography.labelSmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                        }
                    },
                    navigationIcon = {
                        // Archive this line for repeat practice — saved lines
                        // live under Practice → Saved lines. A line with no
                        // turn behind it has no id to file under, so that one
                        // keeps the plain way out instead.
                        if (turnId != null) {
                            IconButton(onClick = {
                                scope.launch {
                                    saved = SavedLineStore.shared(context)
                                        .toggle(SavedLine(id = turnId, text = line))
                                }
                            }) {
                                Icon(
                                    if (saved) Icons.Filled.Bookmark else Icons.Outlined.BookmarkBorder,
                                    contentDescription = stringResource(
                                        if (saved) R.string.remove_from_saved_lines
                                        else R.string.save_line),
                                    tint = MaterialTheme.colorScheme.primary)
                            }
                        } else {
                            IconButton(onClick = { mp3.stop(); runCatching { live.stop() }; onBack() }) {
                                Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = null)
                            }
                        }
                    },
                    actions = {
                        TextButton(
                            onClick = { mp3.stop(); runCatching { live.stop() }; onBack() },
                            enabled = phase != ShadowPhase.RECORDING && phase != ShadowPhase.COUNTDOWN,
                        ) { Text(stringResource(R.string.done)) }
                    },
                )
            },
            bottomBar = {
                // One control, centred and low: listening rides beside the mic
                // rather than owning a row of its own.
                Row(
                    Modifier.fillMaxWidth().bottomBarInsets()
                        .padding(top = 12.dp, bottom = 20.dp),
                    horizontalArrangement = Arrangement.Center,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Box(Modifier.size(56.dp), contentAlignment = Alignment.Center) {
                        IconButton(
                            onClick = { playLine() },
                            enabled = !busy && phase != ShadowPhase.RECORDING &&
                                phase != ShadowPhase.COUNTDOWN && phase != ShadowPhase.ANALYZING,
                        ) {
                            Icon(Icons.Filled.PlayCircleOutline,
                                contentDescription = stringResource(R.string.hear_it),
                                modifier = Modifier.size(32.dp))
                        }
                    }
                    Spacer(Modifier.width(20.dp))
                    MicButton(phase = phase, onTap = { onMicTap() })
                    Spacer(Modifier.width(20.dp))
                    // Keeps the mic optically centred against the play button.
                    Spacer(Modifier.width(56.dp))
                }
            },
        ) { padding ->
            Column(
                Modifier.padding(padding).fillMaxSize()
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = 20.dp).padding(top = 8.dp, bottom = 24.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                // ---- the line itself
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Row(Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween) {
                        Text(stringResource(R.string.target_line),
                            style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                        Text(stringResource(R.string.lld_words, words.size),
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f))
                    }
                    val a = attempt
                    val ops = a?.let { ShadowScore.targetOps(it.steps) }
                    val scored = activeRange?.let { words.slice(it) } ?: words
                    val spans = remember(a, scored, targetLanguage) {
                        if (ops == null) emptyList()
                        else ShadowScore.tokenSpans(scored, targetLanguage)
                    }
                    // Same philosophy as iOS: if the two streams don't account
                    // for each other exactly, colour NOTHING rather than
                    // something shifted. A wrong word in orange is worse.
                    val aligned = ops != null && spans.isNotEmpty() &&
                        spans.sumOf { it.count() } == ops.size
                    FlowRow(
                        horizontalArrangement = Arrangement.spacedBy(2.dp),
                        verticalArrangement = Arrangement.spacedBy(4.dp),
                    ) {
                        words.forEachIndexed { i, word ->
                            val selected = selection?.contains(i) == true
                            val color = wordColor(
                                index = i,
                                aligned = aligned,
                                ops = ops,
                                spans = spans,
                                activeRange = activeRange,
                                timing = timings.getOrNull(i),
                                clockMs = clockMs,
                            )
                            Text(
                                word,
                                style = MaterialTheme.typography.titleLarge,
                                fontWeight = FontWeight.SemiBold,
                                color = color,
                                modifier = Modifier
                                    .clip(RoundedCornerShape(4.dp))
                                    .background(
                                        if (selected) MaterialTheme.colorScheme.primary.copy(alpha = 0.22f)
                                        else Color.Transparent)
                                    .clickable(
                                        enabled = phase == ShadowPhase.IDLE || phase == ShadowPhase.RESULT
                                    ) { tapWord(i) }
                                    .padding(horizontal = 3.dp, vertical = 1.dp),
                            )
                        }
                    }
                }

                if (busy) LinearProgressIndicator(Modifier.fillMaxWidth())

                // ---- the take
                val a = attempt
                if (a != null) {
                    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        Row(Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically) {
                            Text(stringResource(R.string.your_match),
                                style = MaterialTheme.typography.labelMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant)
                            Row(verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                                Icon(Icons.Filled.Speed, contentDescription = null,
                                    modifier = Modifier.size(16.dp),
                                    tint = scoreColor(a.score))
                                Text("${a.score}",
                                    style = MaterialTheme.typography.labelLarge,
                                    fontWeight = FontWeight.SemiBold,
                                    color = scoreColor(a.score))
                                Text("${a.matchCount}/${a.targetTokenCount}",
                                    style = MaterialTheme.typography.labelSmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                        }
                        Text(diffText(a.steps,
                            wrong = MaterialTheme.colorScheme.error,
                            missed = MaterialTheme.colorScheme.onSurfaceVariant,
                            kept = MaterialTheme.colorScheme.onSurface),
                            style = MaterialTheme.typography.bodyLarge)
                        if (said.isNotBlank()) {
                            Text(stringResource(R.string.what_i_heard),
                                style = MaterialTheme.typography.labelMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                modifier = Modifier.padding(top = 4.dp))
                            Text(said, style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                }

                // Only after a score: moving on before saying it would make the
                // hand a list to click through.
                if (attempt != null && onNext != null) {
                    Button(onClick = onNext, modifier = Modifier.fillMaxWidth()) {
                        Text(stringResource(R.string.next))
                    }
                }

                // ---- every earlier take on this line, newest first
                if (past.isNotEmpty()) {
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Row(Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween) {
                            Text(stringResource(R.string.past_attempts),
                                style = MaterialTheme.typography.labelMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant)
                            Text(stringResource(R.string.lld_total, past.size),
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f))
                        }
                        past.forEach { PastAttemptRow(it) }
                    }
                }
            }
        }

        if (phase == ShadowPhase.COUNTDOWN) {
            Box(
                Modifier.fillMaxSize()
                    .background(MaterialTheme.colorScheme.scrim.copy(alpha = 0.5f)),
                contentAlignment = Alignment.Center,
            ) {
                Text("$countdown", fontSize = 120.sp, fontWeight = FontWeight.Black,
                    color = Color.White)
            }
        }
    }

    error?.let { message ->
        AlertDialog(
            onDismissRequest = { error = null },
            title = { Text(stringResource(R.string.something_went_wrong)) },
            text = { Text(message) },
            confirmButton = {
                TextButton(onClick = { error = null }) { Text(stringResource(R.string.ok)) }
            },
        )
    }
}

/**
 * The one control: record / cancel / retry, by phase. An X mid-attempt, not a
 * stop square — a tap DISCARDS the take; ending it is the auto-stop's job.
 */
@Composable
private fun MicButton(phase: ShadowPhase, onTap: () -> Unit) {
    val recording = phase == ShadowPhase.RECORDING
    val enabled = phase == ShadowPhase.IDLE || phase == ShadowPhase.RESULT || recording
    val pulse = rememberInfiniteTransition(label = "mic")
    val scale by pulse.animateFloat(
        initialValue = 1f, targetValue = if (recording) 1.06f else 1f,
        animationSpec = infiniteRepeatable(tween(900), RepeatMode.Reverse), label = "pulse")
    val fill = if (recording) MaterialTheme.colorScheme.error
    else MaterialTheme.colorScheme.primary
    val glyph = if (recording) MaterialTheme.colorScheme.onError
    else MaterialTheme.colorScheme.onPrimary
    Box(
        Modifier
            .scale(scale)
            .size(68.dp)
            .clip(CircleShape)
            .background(if (enabled) fill else fill.copy(alpha = 0.4f))
            .clickable(enabled = enabled, onClick = onTap),
        contentAlignment = Alignment.Center,
    ) {
        Icon(
            when (phase) {
                ShadowPhase.RECORDING -> Icons.Filled.Close
                ShadowPhase.ANALYZING -> Icons.Filled.MoreHoriz
                ShadowPhase.RESULT -> Icons.Filled.Refresh
                else -> Icons.Filled.Mic
            },
            contentDescription = stringResource(
                when (phase) {
                    ShadowPhase.RECORDING -> R.string.follow_the_highlight_tap_to_cancel
                    ShadowPhase.ANALYZING -> R.string.comparing
                    ShadowPhase.RESULT -> R.string.tap_to_try_again
                    else -> R.string.tap_to_sync_shadow
                }),
            tint = glyph,
            modifier = Modifier.size(26.dp),
        )
    }
}

@Composable
private fun PastAttemptRow(a: ShadowAttempt) {
    Row(
        Modifier.fillMaxWidth()
            .clip(RoundedCornerShape(10.dp))
            .background(AppSurfaces.card)
            .padding(horizontal = 12.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Column(Modifier.width(56.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Text("${a.matchScore}",
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.Bold,
                color = scoreColor(a.matchScore))
            Text(Recency.label(a.createdAt),
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        val silent = stringResource(R.string.silent_take)
        Text(a.learnerTranscript.ifBlank { silent },
            style = MaterialTheme.typography.bodySmall,
            maxLines = 2,
            color = MaterialTheme.colorScheme.onSurface)
    }
}

/**
 * One target word's colour.
 *
 * After a take the text colour is CONTENT accuracy only — the word the
 * learner said differently, the word they skipped, the word they hit. Before
 * one it is the karaoke: the word the clock is on, the words behind it, the
 * words still ahead.
 */
@Composable
private fun wordColor(
    index: Int,
    aligned: Boolean,
    ops: List<ShadowScore.DiffOp>?,
    spans: List<IntRange>,
    activeRange: IntRange?,
    timing: WordTiming?,
    clockMs: Int,
): Color {
    val quiet = MaterialTheme.colorScheme.onSurfaceVariant
    // A phrase attempt: the rest of the line was never attempted, and while
    // the clock runs it stays out of the way too.
    if (activeRange != null && index !in activeRange) return quiet
    if (ops != null) {
        if (!aligned) return MaterialTheme.colorScheme.onSurface
        val span = spans.getOrNull(index - (activeRange?.first ?: 0)) ?: return quiet
        val slice = span.mapNotNull { ops.getOrNull(it) }
        return when {
            slice.isEmpty() -> MaterialTheme.colorScheme.onSurface          // punctuation only
            slice.contains(ShadowScore.DiffOp.SUB) -> MaterialTheme.colorScheme.error
            // A word split across tokens counts as attempted unless EVERY
            // piece went missing — "speech text" for "speech-to-text" is a
            // wrong word, not a skipped one.
            slice.all { it == ShadowScore.DiffOp.DEL } -> quiet
            slice.contains(ShadowScore.DiffOp.DEL) -> MaterialTheme.colorScheme.error
            else -> MaterialTheme.colorScheme.onSurface
        }
    }
    if (clockMs < 0 || timing == null) return quiet
    return when {
        clockMs >= timing.endMs -> MaterialTheme.colorScheme.onSurface  // passed
        clockMs >= timing.startMs -> MaterialTheme.colorScheme.primary  // current
        else -> quiet                                                   // upcoming
    }
}

/** The TARGET line scored against the take — not a transcript of it. */
private fun diffText(
    steps: List<ShadowScore.DiffStep>,
    wrong: Color,
    missed: Color,
    kept: Color,
) = buildAnnotatedString {
    steps.forEachIndexed { i, step ->
        if (i > 0) append(" ")
        when (step.op) {
            ShadowScore.DiffOp.MATCH -> {
                pushStyle(SpanStyle(color = kept)); append(step.target.orEmpty()); pop()
            }
            ShadowScore.DiffOp.SUB -> {
                pushStyle(SpanStyle(color = wrong)); append(step.target.orEmpty()); pop()
            }
            ShadowScore.DiffOp.DEL -> {
                pushStyle(SpanStyle(color = missed, textDecoration = TextDecoration.LineThrough))
                append(step.target.orEmpty()); pop()
            }
            ShadowScore.DiffOp.INS -> {
                pushStyle(SpanStyle(color = wrong)); append("(+${step.learner.orEmpty()})"); pop()
            }
        }
    }
}

/** iOS `scoreColor`: 80+ green, 50–79 the accent, below that a warning. */
@Composable
private fun scoreColor(score: Int): Color = when {
    score >= 80 -> Color(0xFF34C759)
    score >= 50 -> MaterialTheme.colorScheme.primary
    else -> MaterialTheme.colorScheme.error
}
