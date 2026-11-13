package com.roro.futurevoice.ui.speech

import android.content.Context
import android.media.MediaPlayer
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
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
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.RecordVoiceOver
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import com.roro.futurevoice.R
import com.roro.futurevoice.audio.WavRecorder
import com.roro.futurevoice.core.Analytics
import com.roro.futurevoice.data.ScriptVoiceover
import com.roro.futurevoice.data.ScriptVoiceoverCenter
import com.roro.futurevoice.data.ScriptVoiceoverStore
import com.roro.futurevoice.data.SpeechScript
import com.roro.futurevoice.data.SpeechStore
import com.roro.futurevoice.data.SpeechTake
import com.roro.futurevoice.net.EdgeError
import com.roro.futurevoice.talk.PronunciationAssessor
import com.roro.futurevoice.talk.SpeechListenService
import com.roro.futurevoice.talk.SpeechListenText
import com.roro.futurevoice.talk.SpeechPhrase
import com.roro.futurevoice.talk.SpeechPhraseMark
import com.roro.futurevoice.talk.SpeechReading
import com.roro.futurevoice.talk.SpeechReadingScore
import com.roro.futurevoice.talk.SpeechReference
import com.roro.futurevoice.ui.FormDivider
import com.roro.futurevoice.ui.FormSection
import com.roro.futurevoice.ui.SheetHeader
import com.roro.futurevoice.ui.brand.IosGlassTextButton
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.util.Locale
import kotlin.math.max
import kotlin.math.min

/**
 * A file player that keeps its place (iOS `AudioPlayer` as the speech surfaces
 * use it): play, pause and go on, a stretch of the file, a seek, a fade. Its
 * clock is Compose state, polled while it plays.
 */
internal class SpeechAudioPlayer(private val source: String? = null) {
    private var mp: MediaPlayer? = null
    private var loadedFile: File? = null
    private val scope = MainScope()
    private var ticker: Job? = null
    private var fade: Job? = null
    private var segmentEnd: Double? = null

    var isPlaying by mutableStateOf(false); private set
    var currentTime by mutableDoubleStateOf(0.0); private set
    var duration by mutableDoubleStateOf(0.0); private set
    val isLoaded: Boolean get() = mp != null

    /** Loads [file] without playing (a bar can be dragged first). */
    fun prepare(file: File): Boolean {
        if (mp != null && loadedFile == file) return true
        release()
        val player = runCatching {
            MediaPlayer().apply {
                setDataSource(file.path)
                prepare()
                setOnCompletionListener {
                    this@SpeechAudioPlayer.isPlaying = false
                    currentTime = this@SpeechAudioPlayer.duration
                    ticker?.cancel()
                }
            }
        }.getOrNull() ?: return false
        mp = player
        loadedFile = file
        duration = player.duration / 1000.0
        currentTime = 0.0
        return true
    }

    fun play(file: File) {
        if (!prepare(file)) return
        source?.let { Analytics.capture("audio_played", mapOf("source" to it)) }
        playSegment(0.0, null)
    }

    /** From [from] to [to] (seconds; null = the end). */
    fun playSegment(from: Double, to: Double?) {
        val player = mp ?: return
        segmentEnd = to
        runCatching { player.seekTo((from * 1000).toInt()); player.start() }
        currentTime = from
        isPlaying = true
        ticker?.cancel()
        ticker = scope.launch {
            while (isActive) {
                delay(50)
                val p = mp ?: break
                currentTime = runCatching { p.currentPosition / 1000.0 }.getOrDefault(currentTime)
                val end = segmentEnd
                if (end != null && currentTime >= end) { pause(); break }
                if (!p.isPlaying && !isPlaying) break
            }
        }
    }

    fun pause() {
        runCatching { mp?.pause() }
        isPlaying = false
        ticker?.cancel()
    }

    fun seek(seconds: Double) {
        val player = mp ?: return
        runCatching { player.seekTo((seconds * 1000).toInt()) }
        currentTime = seconds
    }

    /** Ramps the volume of what is playing, 0…1. */
    fun fadeVolume(to: Float, seconds: Double) {
        fade?.cancel()
        val player = mp ?: return
        if (seconds <= 0) { volume = to; runCatching { player.setVolume(to, to) }; return }
        val from = volume
        fade = scope.launch {
            val steps = max(1, (seconds * 20).toInt())
            for (i in 1..steps) {
                volume = from + (to - from) * i / steps
                runCatching { mp?.setVolume(volume, volume) }
                delay((seconds * 1000 / steps).toLong())
            }
        }
    }
    private var volume = 1f

    fun stop() {
        release()
        currentTime = 0.0
    }

    private fun release() {
        ticker?.cancel()
        fade?.cancel()
        runCatching { mp?.release() }
        mp = null
        loadedFile = null
        isPlaying = false
        volume = 1f
    }
}

/**
 * A challenge's fluent reading, loaded once (iOS `SpeechListenModel`): played
 * whole on the script sheet, the words lighting up as it reads, and a stretch
 * of it in the phrase drill.
 */
internal class SpeechListenModel {
    enum class Phase { IDLE, LOADING, READY, UNAVAILABLE }

    var phase by mutableStateOf(Phase.IDLE); private set
    var text by mutableStateOf<SpeechListenText?>(null); private set
    /** The reading's timed words (ms), for the phrase drill. */
    var audioWords by mutableStateOf<List<SpeechReference.Word>?>(null); private set
    val player = SpeechAudioPlayer("speech_listen")
    private var file: File? = null

    suspend fun load(context: Context, script: SpeechScript) {
        if (phase != Phase.IDLE) return
        phase = Phase.LOADING
        val loaded = SpeechListenService.load(context, script)
        if (loaded == null) { phase = Phase.UNAVAILABLE; return }
        file = loaded.second
        audioWords = loaded.first.words
        text = withContext(Dispatchers.Default) { SpeechListenText(script.body, loaded.first.words) }
        phase = Phase.READY
    }

    /** One stretch of the reading (the phrase drill's "Fluent"). */
    fun playSegment(from: Double, to: Double) {
        introJob?.cancel(); introJob = null
        val f = file ?: return
        if (!player.isLoaded) player.prepare(f)
        player.playSegment(from, to)
    }

    /** Play or pause the whole reading, from where it was (the start again
     *  once it has played to the end). */
    fun toggle() {
        introJob?.cancel(); introJob = null
        val f = file ?: return
        when {
            player.isPlaying -> player.pause()
            player.isLoaded -> {
                player.fadeVolume(1f, 0.0)
                val atEnd = player.currentTime >= player.duration - 0.25
                player.playSegment(if (atEnd) 0.0 else player.currentTime, null)
            }
            else -> player.play(f)
        }
    }

    private val scope = MainScope()
    private var introJob: Job? = null
    private var introPlayed = false

    /** How far along the reading is, 0…1. */
    val progress: Double get() {
        val total = if (player.duration > 0) player.duration else (text?.duration ?: 0.0)
        return if (total > 0) min(1.0, player.currentTime / total) else 0.0
    }

    /** The reading goes on, whole: an intro still fading in keeps playing at
     *  full volume instead of fading away, a paused one resumes where it was. */
    fun playOn() {
        if (phase != Phase.READY) return
        if (player.isPlaying) {
            introJob?.cancel(); introJob = null
            player.fadeVolume(1f, 0.3)
        } else toggle()
    }

    /** The challenge page's intro (iOS `playIntro`): the opening rises over a
     *  couple of seconds and fades away at the end of the first sentence that
     *  finishes after [seconds]. It PAUSES at the end, not stops: the page's
     *  Script button is a mini player, and a tap goes on from there. */
    fun playIntro(seconds: Double = 9.0) {
        val f = file ?: return
        if (introPlayed || introJob != null || player.isPlaying) return
        introPlayed = true
        player.play(f)
        if (!player.isPlaying) return
        player.fadeVolume(0f, 0.0)
        player.fadeVolume(1f, 2.5)
        val end = text?.sentenceEnd(seconds) ?: (seconds + 3)
        introJob = scope.launch {
            delay((max(1.0, end - 1.2) * 1000).toLong())
            player.fadeVolume(0f, 1.6)
            delay(1700)
            player.pause()
            player.fadeVolume(1f, 0.0)
            introJob = null
        }
    }

    /** Quietly to a pause, keeping the place (a take or the takes opening over the page). */
    fun fadeToPause() {
        introJob?.cancel(); introJob = null
        if (!player.isPlaying) return
        player.fadeVolume(0f, 0.4)
        scope.launch { delay(450); player.pause(); player.fadeVolume(1f, 0.0) }
    }

    /** Quietly, never cut: leaving the page, or starting a take. */
    fun fadeOut() {
        introJob?.cancel(); introJob = null
        if (!player.isPlaying) { player.stop(); return }
        player.fadeVolume(0f, 0.5)
        scope.launch { delay(550); player.stop() }
    }

    fun stop() {
        introJob?.cancel(); introJob = null
        player.stop()
    }
}

private fun clock(t: Double): String {
    val s = t.toInt()
    return "${s / 60}:" + "%02d".format(Locale.US, s % 60)
}

/** The play row at the top of the script sheet: a round play button, the time,
 *  and how far along the reading is (iOS `SpeechListenRow`). */
@Composable
internal fun SpeechListenRow(model: SpeechListenModel) {
    val player = model.player
    val accent = MaterialTheme.colorScheme.primary
    Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Box(Modifier.size(44.dp).clip(CircleShape).background(accent)
            .clickable(enabled = model.phase == SpeechListenModel.Phase.READY) { model.toggle() },
            contentAlignment = Alignment.Center) {
            Icon(if (player.isPlaying) Icons.Filled.Pause else Icons.Filled.PlayArrow,
                stringResource(if (player.isPlaying) R.string.pause else R.string.play), tint = Color.White)
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(stringResource(R.string.speech_listen_fluent_reading), style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
                val total = model.text?.duration ?: 0.0
                if (model.phase == SpeechListenModel.Phase.LOADING) {
                    CircularProgressIndicator(Modifier.size(14.dp), strokeWidth = 2.dp)
                } else if (total > 0) {
                    Text("${clock(player.currentTime)} / ${clock(total)}", style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            LinearProgressIndicator(progress = {
                min(1.0, player.currentTime / max(1.0, model.text?.duration ?: 1.0)).toFloat()
            }, color = accent, trackColor = MaterialTheme.colorScheme.outlineVariant, modifier = Modifier.fillMaxWidth())
        }
    }
}

/** The script as the fluent reader reads it: words already said in full, the
 *  one being said in the accent colour, the rest faded until the voice reaches
 *  them. "/" where the reader breathes, "‿" where two words run together. */
@Composable
internal fun SpeechListenTextView(text: SpeechListenText, player: SpeechAudioPlayer) {
    val reading = player.isPlaying || player.currentTime > 0
    val time = player.currentTime
    val primary = MaterialTheme.colorScheme.onSurface
    val accent = MaterialTheme.colorScheme.primary
    val secondary = MaterialTheme.colorScheme.onSurfaceVariant
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        text.paragraphs.forEach { tokens ->
            Text(buildAnnotatedString {
                for (t in tokens) {
                    val color = when {
                        !reading || t.end <= time -> primary
                        t.start <= time -> accent
                        else -> primary.copy(alpha = 0.28f)
                    }
                    withStyle(SpanStyle(color = color)) { append(t.text) }
                    if (t.runsOn) withStyle(SpanStyle(color = secondary)) { append("‿") } else append(" ")
                    if (t.breath) withStyle(SpanStyle(color = secondary, fontWeight = FontWeight.SemiBold)) { append("/ ") }
                }
            }, style = MaterialTheme.typography.bodyLarge.copy(lineHeight = MaterialTheme.typography.bodyLarge.lineHeight * 1.2f),
                modifier = Modifier.fillMaxWidth())
        }
    }
}

/** What the two marks mean, under the script. */
@Composable
internal fun SpeechListenLegend(modifier: Modifier = Modifier) {
    val secondary = MaterialTheme.colorScheme.onSurfaceVariant
    Row(modifier, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
        Text(stringResource(R.string.speech_listen_breathe, "/"), style = MaterialTheme.typography.bodySmall, color = secondary)
        Text(stringResource(R.string.speech_listen_run_together, "‿"), style = MaterialTheme.typography.bodySmall, color = secondary)
    }
}

// MARK: - Fix one phrase

/**
 * Fix one phrase (iOS `SpeechPhraseDrillSheet`, 2026-11-13): a mark on a
 * Season 2 result (a stop where the fluent reading runs on, a word held far
 * longer) opens the phrase around it. Each word's length is drawn twice, the
 * fluent reading's and the learner's; both can be heard; and the phrase is said
 * again until it holds together. Nothing here changes the take's score.
 */
@Composable
internal fun SpeechPhraseDrillSheet(script: SpeechScript, take: SpeechTake, mark: SpeechPhraseMark, onDismiss: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val listen = remember { SpeechListenModel() }
    val yours = remember { SpeechAudioPlayer() }
    val recorder = remember { WavRecorder() }
    var recordingFile by remember { mutableStateOf<File?>(null) }
    var tries by remember { mutableStateOf(listOf<SpeechPhrase.Judgement>()) }
    var judging by remember { mutableStateOf(false) }
    var failed by remember { mutableStateOf(false) }
    LaunchedEffect(script.id) { listen.load(context, script) }
    DisposableEffect(Unit) {
        onDispose {
            listen.stop(); yours.stop()
            if (recordingFile != null) runCatching { recorder.stop() }
        }
    }
    val micPermission = androidx.activity.compose.rememberLauncherForActivityResult(
        androidx.activity.result.contract.ActivityResultContracts.RequestPermission()) { ok -> if (!ok) failed = true }

    val written = remember(script.body) { script.body.split(Regex("\\s+")).filter { it.isNotEmpty() } }
    val range = remember(written, mark) { SpeechPhrase.around(mark, written) }
    val phraseText = written.slice(range).joinToString(" ")
    val fluentWords = remember(listen.audioWords, written) {
        val words = listen.audioWords ?: return@remember emptyList()
        val all = SpeechListenText.display(script.body, words)
        if (all.size == written.size) all.slice(range) else emptyList()
    }
    val yourWords = remember(take.id, written) {
        val words = SpeechPhrase.takeWords(take) ?: return@remember emptyList()
        val all = SpeechListenText.display(script.body, words)
        if (all.size == written.size) all.slice(range) else emptyList()
    }

    fun segment(words: List<SpeechListenText.Display>): Pair<Double, Double>? {
        val first = words.firstNotNullOfOrNull { it.time } ?: return null
        val last = words.lastOrNull { it.time != null }?.time ?: return null
        return max(0.0, first.first - 0.08) to last.second + 0.15
    }
    fun playYours() {
        listen.player.pause()
        val seg = segment(yourWords) ?: return
        val file = SpeechStore.mediaFile(context, take.audioFilename)
        if (!yours.isLoaded) yours.prepare(file)
        yours.playSegment(seg.first, seg.second)
    }
    fun playFluent(then: (() -> Unit)? = null) {
        yours.stop()
        val seg = segment(fluentWords) ?: return
        listen.playSegment(seg.first, seg.second)
        if (then != null) scope.launch {
            delay(((seg.second - seg.first + 0.4) * 1000).toLong())
            then()
        }
    }
    fun record() {
        val file = recordingFile
        if (file != null) {
            runCatching { recorder.stop() }
            recordingFile = null
            judging = true
            failed = false
            scope.launch {
                try {
                    val result = PronunciationAssessor.assess(context, file, phraseText, script.language, "speech_drill")
                    file.delete()
                    val words = result.result?.words?.filter { !it.isOmission && !it.isInsertion && it.durationMs > 0 }
                    if (words.isNullOrEmpty()) { failed = true; return@launch }
                    val said = SpeechListenText.display(phraseText,
                        words.map { SpeechReference.Word(it.word, it.offsetMs, it.offsetMs + it.durationMs) })
                    val judgement = SpeechPhrase.judge(said, fluentWords)
                    tries = tries + judgement
                    Analytics.capture("speech_phrase_try", mapOf(
                        "kind" to if (mark.kind == SpeechPhraseMark.Kind.STOP) "stop" else "held",
                        "try" to tries.size, "matched" to judgement.matched))
                } finally {
                    judging = false
                }
            }
        } else {
            listen.player.pause(); yours.pause()
            if (androidx.core.content.ContextCompat.checkSelfPermission(context, android.Manifest.permission.RECORD_AUDIO) !=
                android.content.pm.PackageManager.PERMISSION_GRANTED) {
                micPermission.launch(android.Manifest.permission.RECORD_AUDIO); return
            }
            val out = File(context.cacheDir, "speech-drill-${System.nanoTime()}.wav")
            if (runCatching { recorder.start(out) }.isSuccess) recordingFile = out else failed = true
        }
    }

    val word = written[min(mark.word, written.size - 1)]
    val explanation = when (mark.kind) {
        SpeechPhraseMark.Kind.STOP -> stringResource(R.string.speech_drill_stopped, "%.1f".format(Locale.US, mark.seconds), word)
        SpeechPhraseMark.Kind.HELD -> stringResource(R.string.speech_drill_held, word, "%.1f".format(Locale.US, mark.seconds))
    }
    val last = tries.lastOrNull()
    val status = when {
        recordingFile != null -> stringResource(R.string.speech_drill_say_then_stop)
        judging -> stringResource(R.string.speech_drill_listening)
        failed -> stringResource(R.string.speech_drill_failed)
        last == null -> stringResource(R.string.speech_drill_hear_first)
        last.matched -> stringResource(R.string.speech_drill_holds)
        last.missing > 0 -> stringResource(R.string.speech_drill_missing)
        last.stops.isNotEmpty() -> stringResource(R.string.speech_drill_still_stop, last.stops.first())
        last.held.isNotEmpty() -> stringResource(R.string.speech_drill_still_long, last.held.first())
        else -> stringResource(R.string.speech_drill_closer)
    }

    SpeechSheet(onDismiss) {
        SheetHeader(stringResource(R.string.speech_drill_title),
            trailing = { IosGlassTextButton(stringResource(R.string.done), onClick = onDismiss, bold = true) })
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 16.dp).padding(bottom = 32.dp)) {
            FormSection(stringResource(if (mark.kind == SpeechPhraseMark.Kind.STOP) R.string.speech_drill_a_stop else R.string.speech_drill_a_held_word)) {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("“$phraseText”", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                    Text(explanation, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            if (fluentWords.isNotEmpty()) {
                val accent = MaterialTheme.colorScheme.primary
                val ink = MaterialTheme.colorScheme.onSurface
                val footer = stringResource(R.string.speech_drill_lengths_footer, "■", "■")
                FormSection(stringResource(R.string.speech_drill_lengths)) {
                    SpeechPhraseBars(written.slice(range), fluentWords, yourWords, Modifier.padding(16.dp))
                }
                Text(buildAnnotatedString {
                    val firstAt = footer.indexOf("■")
                    val secondAt = footer.indexOf("■", firstAt + 1)
                    if (firstAt < 0 || secondAt < 0) { append(footer); return@buildAnnotatedString }
                    append(footer.substring(0, firstAt))
                    withStyle(SpanStyle(color = accent.copy(alpha = 0.5f))) { append("■") }
                    append(footer.substring(firstAt + 1, secondAt))
                    withStyle(SpanStyle(color = ink)) { append("■") }
                    append(footer.substring(secondAt + 1))
                }, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(start = 16.dp, end = 16.dp, top = 7.dp))
            }
            FormSection(null) {
                Row(Modifier.fillMaxWidth().padding(12.dp), horizontalArrangement = Arrangement.spacedBy(10.dp, Alignment.CenterHorizontally)) {
                    DrillButton(stringResource(R.string.speech_drill_fluent), Icons.Filled.PlayArrow, fluentWords.isNotEmpty()) { playFluent() }
                    DrillButton(stringResource(R.string.speech_drill_yours), Icons.Filled.PlayArrow, yourWords.isNotEmpty()) { playYours() }
                    DrillButton(stringResource(R.string.speech_drill_both), null, fluentWords.isNotEmpty() && yourWords.isNotEmpty()) {
                        playFluent { playYours() }
                    }
                }
            }
            FormSection(null) {
                Column(Modifier.fillMaxWidth().padding(vertical = 16.dp), horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    if (tries.isNotEmpty()) {
                        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            tries.forEachIndexed { i, t ->
                                Box(Modifier.size(28.dp).background(
                                    if (t.matched) Color(0xFF34C759).copy(alpha = 0.25f) else Color(0xFFFF9500).copy(alpha = 0.2f),
                                    CircleShape), contentAlignment = Alignment.Center) {
                                    Text("${i + 1}", style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.SemiBold)
                                }
                            }
                        }
                    }
                    val recording = recordingFile != null
                    Box(Modifier.size(72.dp).clip(CircleShape).background(Color(0xFFFF3B30))
                        .clickable(enabled = !judging && fluentWords.isNotEmpty()) { record() },
                        contentAlignment = Alignment.Center) {
                        Icon(if (recording) Icons.Filled.Stop else Icons.Filled.Mic,
                            stringResource(if (recording) R.string.speech_drill_stop_button else R.string.speech_drill_say_again),
                            tint = Color.White, modifier = Modifier.size(30.dp))
                    }
                    Text(status, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant,
                        textAlign = TextAlign.Center, modifier = Modifier.padding(horizontal = 16.dp))
                }
            }
        }
    }
}

@Composable
private fun DrillButton(label: String, icon: androidx.compose.ui.graphics.vector.ImageVector?, enabled: Boolean, onClick: () -> Unit) {
    val accent = MaterialTheme.colorScheme.primary
    Row(Modifier.clip(RoundedCornerShape(10.dp)).background(accent.copy(alpha = if (enabled) 0.12f else 0.05f))
        .clickable(enabled = enabled, onClick = onClick).padding(horizontal = 12.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        val tint = if (enabled) accent else accent.copy(alpha = 0.4f)
        if (icon != null) Icon(icon, null, tint = tint, modifier = Modifier.size(16.dp))
        Text(label, color = tint, style = MaterialTheme.typography.bodyMedium, maxLines = 1)
    }
}

/** Each word of the phrase with two bars: how long the fluent reader held it
 *  and how long you did, on one scale. A stop where the fluent reading runs on
 *  is a row of its own (iOS `SpeechPhraseBars`). */
@Composable
internal fun SpeechPhraseBars(written: List<String>, fluent: List<SpeechListenText.Display>,
                              yours: List<SpeechListenText.Display>, modifier: Modifier = Modifier) {
    data class Row_(val label: String, val fluent: Double, val yours: Double?, val isStop: Boolean)
    val stopLabel = stringResource(R.string.speech_drill_stop_row)
    val rows = mutableListOf<Row_>()
    written.indices.forEach { k ->
        val f = fluent.getOrNull(k)?.time?.let { it.second - it.first } ?: 0.0
        val y = yours.getOrNull(k)?.time?.let { it.second - it.first }
        rows += Row_(written[k], f, y, false)
        if (k + 1 < written.size && !SpeechPhrase.endsPhrase(written[k]) && k + 1 < yours.size) {
            val a = yours[k].time; val b = yours[k + 1].time
            if (a != null && b != null && b.first - a.second >= SpeechReading.PAUSE_SECONDS) {
                val fluentGap = (fluent.getOrNull(k + 1)?.time?.first ?: 0.0) - (fluent.getOrNull(k)?.time?.second ?: 0.0)
                if (fluentGap < SpeechReading.PAUSE_SECONDS) rows += Row_(stopLabel, 0.0, b.first - a.second, true)
            }
        }
    }
    val scale = max(0.6, rows.maxOfOrNull { max(it.fluent, it.yours ?: 0.0) } ?: 0.6)
    val accent = MaterialTheme.colorScheme.primary
    val ink = MaterialTheme.colorScheme.onSurface
    val red = Color(0xFFFF3B30)
    val orange = Color(0xFFFF9500)
    Column(modifier, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        rows.forEach { row ->
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Text(row.label, style = MaterialTheme.typography.bodyMedium,
                    fontWeight = if (row.isStop) FontWeight.Normal else FontWeight.Medium,
                    fontStyle = if (row.isStop) FontStyle.Italic else FontStyle.Normal,
                    color = if (row.isStop) red else ink, maxLines = 1, overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.width(84.dp))
                androidx.compose.foundation.layout.BoxWithConstraints(Modifier.weight(1f).height(17.dp)) {
                    val w = maxWidth
                    Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                        val fw = if (row.fluent > 0) max(3.0, w.value * row.fluent / scale) else 0.0
                        Box(Modifier.width(fw.dp).height(7.dp).background(accent.copy(alpha = 0.5f), CircleShape))
                        // Orange when your word ran past twice the fluent length
                        // (raw, not pace-corrected: this is a picture).
                        val y = row.yours
                        val color = when {
                            row.isStop -> red
                            y != null && row.fluent > 0 && y >= row.fluent * 2 && y - row.fluent >= 0.15 -> orange
                            else -> ink
                        }
                        Box(Modifier.width((w.value * (y ?: 0.0) / scale).dp).height(7.dp).background(color, CircleShape))
                    }
                }
                Text(row.yours?.let { "%.1fs".format(Locale.US, it) } ?: "", style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.End, modifier = Modifier.width(34.dp))
            }
        }
    }
}

// MARK: - Listening under the marked script

/**
 * Listening under the marked script (iOS `SpeechScriptListening`,
 * 2026-11-13): the take's own voice, or the same script read by the FUTURE
 * SELF in the learner's cloned voice (the Speech tab's paid voiceover, made
 * once per script, charged in talk minutes, free to replay), so the marks can
 * be heard against the way it should go. Two players, each keeping its own
 * place; starting one pauses the other. Either way the word being heard is
 * drawn on the script ([onCurrent]).
 */
@Composable
internal fun SpeechScriptListening(take: SpeechTake, script: SpeechScript, mine: SpeechAudioPlayer,
                                   future: SpeechAudioPlayer, onCurrent: (Int?) -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val voiceId = rememberCloneVoiceId()
    val jobs by ScriptVoiceoverCenter.jobs.collectAsState()
    val revision by ScriptVoiceoverCenter.revision.collectAsState()
    val account = rememberGateAccount()
    var stored by remember { mutableStateOf<ScriptVoiceoverStore.Stored?>(null) }
    LaunchedEffect(script.body, voiceId, revision) {
        stored = voiceId?.let { v -> withContext(Dispatchers.IO) { ScriptVoiceoverCenter.existing(context, script, v) } }
    }
    val quote = remember(script.body, script.language) { ScriptVoiceover.quoteMinutes(script.body, script.language) }
    var activeMine by remember { mutableStateOf(true) }
    var wall by remember { mutableStateOf<VoiceoverWall?>(null) }
    var error by remember { mutableStateOf<String?>(null) }

    // The word being heard, by the script's written word.
    val mineTimes = remember(take.id, script.body) {
        SpeechPhrase.takeWords(take)?.let { words -> SpeechListenText.display(script.body, words).map { it.time } } ?: emptyList()
    }
    val futureTimes = remember(stored) {
        val timings = stored?.meta?.timings
        if (timings.isNullOrEmpty()) emptyList()
        else SpeechListenText.display(script.body, timings.map { SpeechReference.Word(it.word, it.startMs, it.endMs) }).map { it.time }
    }
    val player = if (activeMine) mine else future
    val times = if (activeMine) mineTimes else futureTimes
    val current = if (player.isPlaying || player.currentTime > 0) {
        val t = player.currentTime
        times.indexOfLast { (it?.first ?: Double.POSITIVE_INFINITY) <= t }.takeIf { it >= 0 }
    } else null
    LaunchedEffect(current) { onCurrent(current) }

    fun fileFor(isMine: Boolean): File? =
        if (isMine) SpeechStore.mediaFile(context, take.audioFilename) else stored?.file

    /** Ready one at the start without playing (a drag before any play), and
     *  make it the one the script follows. */
    fun load(isMine: Boolean) {
        val p = if (isMine) mine else future
        val other = if (isMine) future else mine
        if (other.isPlaying) other.pause()
        activeMine = isMine
        if (!p.isLoaded) fileFor(isMine)?.let { p.prepare(it) }
    }
    /** Play or pause one; starting it pauses the other, which keeps its place. */
    fun start(isMine: Boolean) {
        val p = if (isMine) mine else future
        val other = if (isMine) future else mine
        if (other.isPlaying) other.pause()
        activeMine = isMine
        when {
            p.isPlaying -> p.pause()
            p.isLoaded -> p.playSegment(p.currentTime, null)
            else -> fileFor(isMine)?.let { p.play(it) }
        }
    }
    fun makeFuture() {
        val v = voiceId ?: return
        scope.launch {
            if (voiceoverBlocked()) { wall = VoiceoverWall.PAYWALL; return@launch }
            ScriptVoiceoverCenter.clearFailure(script, v)
            try {
                ScriptVoiceoverCenter.make(context, script, v, quote)
                Analytics.capture("speech_result_future_self_made", mapOf("minutes" to quote))
            } catch (e: EdgeError) {
                val w = e.voiceoverWall()
                if (w != null) wall = w else error = e.message
            } catch (_: Exception) {
                // Shown under the buttons from the job's state.
            }
        }
    }

    val purple = speechPartColor(SpeechReadingScore.Part.PRONUNCIATION)
    val job = voiceId?.let { jobs[ScriptVoiceoverCenter.keyFor(script, it)] }
    Column(Modifier.fillMaxWidth().padding(start = 16.dp, end = 16.dp, top = 12.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        // Both sides as tall as the taller one: the make button beside a
        // player read as a different, shorter thing (iOS a574dead).
        Row(Modifier.fillMaxWidth().height(IntrinsicSize.Min), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            SpeechPlayTile(stringResource(R.string.speech_listen_my_reading), take.durationSeconds,
                MaterialTheme.colorScheme.primary, mine, onAction = { start(true) }, onLoad = { load(true) },
                modifier = Modifier.weight(1f).fillMaxHeight())
            if (voiceId != null) {
                val s = stored
                if (s != null) {
                    SpeechPlayTile(stringResource(R.string.speech_listen_future_self), s.meta.seconds, purple, future,
                        onAction = { start(false) }, onLoad = { load(false) },
                        modifier = Modifier.weight(1f).fillMaxHeight())
                } else if (job is ScriptVoiceoverCenter.Job.Making) {
                    Row(Modifier.weight(1f).fillMaxHeight().heightIn(min = 56.dp)
                        .background(MaterialTheme.colorScheme.surfaceContainerHighest, RoundedCornerShape(14.dp)).padding(10.dp),
                        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally)) {
                        CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
                        Text("${job.done}/${job.total}", style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                } else {
                    val enabled = quote <= ScriptVoiceover.MAX_MINUTES
                    Row(Modifier.weight(1f).fillMaxHeight().heightIn(min = 56.dp).clip(RoundedCornerShape(14.dp))
                        .background(purple.copy(alpha = 0.12f)).clickable(enabled = enabled) { makeFuture() }.padding(10.dp),
                        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterHorizontally)) {
                        Icon(Icons.Filled.RecordVoiceOver, null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(18.dp))
                        Text(stringResource(R.string.speech_listen_future_self), fontWeight = FontWeight.SemiBold,
                            color = MaterialTheme.colorScheme.primary, style = MaterialTheme.typography.bodyMedium)
                    }
                }
            }
        }
        if (voiceId != null && stored == null) {
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(stringResource(R.string.speech_listen_future_pitch), style = MaterialTheme.typography.bodySmall)
                Text(voiceoverPriceLine(quote, account), style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                (job as? ScriptVoiceoverCenter.Job.Failed)?.let {
                    Text(it.message, style = MaterialTheme.typography.bodySmall, color = Color(0xFFFF3B30))
                }
            }
        }
    }
    VoiceoverWallHost(wall) { wall = null }
    error?.let { msg ->
        AlertDialog(onDismissRequest = { error = null },
            confirmButton = { TextButton(onClick = { error = null }) { Text(stringResource(R.string.ok)) } },
            title = { Text(stringResource(R.string.couldn_t_make_it_in_your_voice)) },
            text = { Text(msg) })
    }
}

/** One of the two players: its button, its own clock, and a bar that can be
 *  dragged to any point (iOS `SpeechPlayTile`). A drag pauses while it moves
 *  and plays on if it was playing. */
@Composable
private fun SpeechPlayTile(title: String, seconds: Double, tint: Color, player: SpeechAudioPlayer,
                           onAction: () -> Unit, onLoad: () -> Unit, modifier: Modifier = Modifier) {
    var resumeAfterDrag by remember { mutableStateOf(false) }
    var dragging by remember { mutableStateOf(false) }
    val started = player.isLoaded || player.currentTime > 0
    val total = max(seconds, 0.1)
    Column(modifier.background(if (player.isPlaying) tint.copy(alpha = 0.12f)
            else MaterialTheme.colorScheme.surfaceContainerHighest, RoundedCornerShape(14.dp)).padding(10.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Box(Modifier.size(36.dp).clip(CircleShape).background(tint).clickable(onClick = onAction),
                contentAlignment = Alignment.Center) {
                Icon(if (player.isPlaying) Icons.Filled.Pause else Icons.Filled.PlayArrow, title,
                    tint = Color.White, modifier = Modifier.size(20.dp))
            }
            Column(Modifier.weight(1f)) {
                Text(title, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold, maxLines = 1,
                    overflow = TextOverflow.Ellipsis)
                Text(if (started) "${clock(player.currentTime)} / ${clock(seconds)}" else clock(seconds),
                    style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        Slider(value = min(player.currentTime, total).toFloat(),
            onValueChange = { v ->
                if (!dragging) {
                    dragging = true
                    onLoad()   // also makes this the one the script follows
                    resumeAfterDrag = player.isPlaying
                    if (player.isPlaying) player.pause()
                }
                player.seek(v.toDouble())
            },
            onValueChangeFinished = {
                dragging = false
                if (resumeAfterDrag) player.playSegment(player.currentTime, null)
            },
            valueRange = 0f..total.toFloat(),
            colors = SliderDefaults.colors(thumbColor = tint, activeTrackColor = tint),
            modifier = Modifier.height(20.dp))
    }
}
