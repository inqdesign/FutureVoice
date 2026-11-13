package com.roro.futurevoice.ui.speech

import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.ui.input.pointer.pointerInput
import android.media.MediaPlayer
import androidx.annotation.ArrayRes
import androidx.annotation.StringRes
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.FactCheck
import androidx.compose.material.icons.filled.GpsFixed
import androidx.compose.material.icons.filled.GraphicEq
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PauseCircle
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Speed
import androidx.compose.material.icons.filled.Timelapse
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.BottomSheetScaffold
import androidx.compose.material3.TextButton
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import kotlinx.coroutines.delay
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SheetValue
import androidx.compose.material3.Text
import androidx.compose.material3.rememberBottomSheetScaffoldState
import androidx.compose.material3.rememberStandardBottomSheetState
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
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringArrayResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.roro.futurevoice.R
import com.roro.futurevoice.data.SpeechChallenges
import com.roro.futurevoice.data.SpeechScript
import com.roro.futurevoice.data.SpeechStore
import com.roro.futurevoice.data.SpeechTake
import com.roro.futurevoice.talk.SpeechAnalyzer
import com.roro.futurevoice.talk.SpeechDelivery
import com.roro.futurevoice.talk.SpeechReadingLevel
import com.roro.futurevoice.talk.SpeechReadingScore
import com.roro.futurevoice.talk.SpeechReading
import com.roro.futurevoice.ui.FormDivider
import com.roro.futurevoice.ui.FormSection
import com.roro.futurevoice.ui.SheetHeader
import com.roro.futurevoice.ui.brand.AppSurfaces
import com.roro.futurevoice.ui.brand.IosGlassButton
import com.roro.futurevoice.ui.brand.IosGlassTextButton
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.Locale
import kotlin.math.abs

/** The one line a Season 2 score comes with, the way a karaoke machine says
 *  something about yours — iOS `SpeechVerdict`. One byte of the take's id picks
 *  the line, so a take keeps its line when it is reopened. */
internal object SpeechVerdict {
    @ArrayRes fun lines(total: Int): Int = when {
        total >= 100 -> R.array.speech_verdict_100
        total >= 95 -> R.array.speech_verdict_95
        total >= 88 -> R.array.speech_verdict_88
        total >= 78 -> R.array.speech_verdict_78
        total >= 60 -> R.array.speech_verdict_60
        else -> R.array.speech_verdict_low
    }

    /** iOS `take.uuid.15`: the last byte of the id. */
    fun index(takeId: String, count: Int): Int =
        (takeId.takeLast(2).toIntOrNull(16) ?: 0) % count
}

@StringRes
private fun levelTitle(level: SpeechReadingLevel): Int = when (level) {
    SpeechReadingLevel.NEWS_ANCHOR -> R.string.speech_level_news_anchor
    SpeechReadingLevel.AUDIOBOOK -> R.string.speech_level_audiobook
    SpeechReadingLevel.BORN_AND_RAISED -> R.string.speech_level_born_and_raised
    SpeechReadingLevel.PASSES_AS_LOCAL -> R.string.speech_level_passes_as_local
    SpeechReadingLevel.OFFICE_ACE -> R.string.speech_level_office_ace
    SpeechReadingLevel.PRESENTER -> R.string.speech_level_presenter
    SpeechReadingLevel.THIRD_YEAR_ABROAD -> R.string.speech_level_third_year_abroad
    SpeechReadingLevel.FIRST_YEAR_ABROAD -> R.string.speech_level_first_year_abroad
    SpeechReadingLevel.LANGUAGE_SCHOOL -> R.string.speech_level_language_school
    SpeechReadingLevel.IMMIGRATION -> R.string.speech_level_immigration
    SpeechReadingLevel.RESTAURANT -> R.string.speech_level_restaurant
    SpeechReadingLevel.GESTURES -> R.string.speech_level_gestures
    SpeechReadingLevel.WARMING_UP -> R.string.speech_level_warming_up
}

@StringRes
private fun partTitle(part: SpeechReadingScore.Part): Int = when (part) {
    SpeechReadingScore.Part.SPEED -> R.string.speech_part_speed
    SpeechReadingScore.Part.RHYTHM -> R.string.speech_part_rhythm
    SpeechReadingScore.Part.PAUSES -> R.string.pauses
    SpeechReadingScore.Part.ACCURACY -> R.string.accuracy
    SpeechReadingScore.Part.PRONUNCIATION -> R.string.pronunciation
}

private fun partIcon(part: SpeechReadingScore.Part): ImageVector = when (part) {
    SpeechReadingScore.Part.SPEED -> Icons.Filled.Speed
    SpeechReadingScore.Part.RHYTHM -> Icons.Filled.Timelapse
    SpeechReadingScore.Part.PAUSES -> Icons.Filled.PauseCircle
    SpeechReadingScore.Part.ACCURACY -> Icons.Filled.FactCheck
    SpeechReadingScore.Part.PRONUNCIATION -> Icons.Filled.GraphicEq
}

private fun oneDecimal(value: Double) = "%.1f".format(Locale.US, value)
private fun quoted(words: List<String>) = words.joinToString(" ") { "“$it”" }
private fun soundsList(sounds: List<SpeechDelivery.Sound>) = sounds.joinToString(" · ") {
    if (it.phoneme.isEmpty()) "“${it.word}” ${it.score}" else "${it.phoneme} “${it.word}” ${it.score}"
}

/** Seconds, yours beside the native reading's. */
@Composable
private fun heldList(held: List<SpeechReadingScore.Held>): String =
    held.take(3).map { h ->
        val mine = h.seconds; val native = h.nativeSeconds
        if (mine == null || native == null) "“${h.word}”"
        else stringResource(R.string.speech_held_item, h.word, oneDecimal(mine), oneDecimal(native))
    }.joinToString(" · ")

@Composable
private fun extraPauseList(pauses: List<SpeechReadingScore.Pause>): String =
    pauses.take(3).map { stringResource(R.string.speech_pause_item, it.after, oneDecimal(it.seconds)) }.joinToString(" · ")

private fun percentOff(r: SpeechReadingScore) = SpeechReading.round(abs(1 - r.speed) * 100).toInt()

/** What one part measured, in one line, against the native reading. */
@Composable
private fun partDetail(part: SpeechReadingScore.Part, r: SpeechReadingScore): String = when (part) {
    SpeechReadingScore.Part.SPEED -> when {
        r.speed < 0.97 -> stringResource(R.string.speech_detail_slower, percentOff(r))
        r.speed > 1.15 -> stringResource(R.string.speech_detail_faster, percentOff(r))
        else -> stringResource(R.string.speech_detail_native_pace)
    }
    SpeechReadingScore.Part.RHYTHM ->
        if (r.held.isEmpty()) stringResource(R.string.speech_detail_held_ok)
        else stringResource(R.string.speech_detail_held, heldList(r.held))
    SpeechReadingScore.Part.PAUSES ->
        if (r.extraPauses.isEmpty()) stringResource(R.string.speech_detail_no_pauses)
        else stringResource(R.string.speech_detail_stopped, extraPauseList(r.extraPauses))
    SpeechReadingScore.Part.ACCURACY -> when {
        r.slips == 0 -> stringResource(R.string.speech_detail_every_word)
        r.missed.isEmpty() -> stringResource(R.string.speech_detail_slips, r.slips)
        else -> stringResource(R.string.speech_detail_slips_list, r.slips, quoted(r.missed))
    }
    SpeechReadingScore.Part.PRONUNCIATION ->
        if (r.weakest.isEmpty()) stringResource(R.string.speech_detail_no_wrong_sounds) else soundsList(r.weakest)
}

/** The one thing to work on next, as an instruction with its place. */
@Composable
private fun partFocus(part: SpeechReadingScore.Part, r: SpeechReadingScore): String = when (part) {
    SpeechReadingScore.Part.SPEED -> stringResource(R.string.speech_focus_faster, percentOff(r))
    SpeechReadingScore.Part.RHYTHM ->
        if (r.held.isEmpty()) stringResource(R.string.speech_focus_even_flow)
        else stringResource(R.string.speech_focus_dont_hold, heldList(r.held))
    SpeechReadingScore.Part.PAUSES ->
        if (r.extraPauses.isEmpty()) stringResource(R.string.speech_focus_one_breath)
        else stringResource(R.string.speech_focus_dont_stop, extraPauseList(r.extraPauses))
    SpeechReadingScore.Part.ACCURACY ->
        if (r.missed.isEmpty()) stringResource(R.string.speech_focus_every_word)
        else stringResource(R.string.speech_focus_every_word_list, quoted(r.missed))
    SpeechReadingScore.Part.PRONUNCIATION ->
        if (r.weakest.isEmpty()) stringResource(R.string.speech_focus_clear_sounds)
        else stringResource(R.string.speech_focus_sounds, soundsList(r.weakest))
}

/**
 * A take's page — iOS `SpeechResultView` / `SpeechResultSheetPage`: the
 * reader fills the page (the camera looping a few seconds without sound, or
 * the score's colour for a take with no camera video), the big score with its
 * one-line verdict and nickname over it, and the details on a sheet that
 * opens on a summary of the part scores. Play fades everything out and plays
 * the whole take; a tap pauses and brings it back. While it plays, the script
 * can roll over the picture, each word lit as it was said.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun SpeechTakePage(take: SpeechTake, script: SpeechScript, pendingVideo: Boolean,
                            entry: SpeechChallenges.Entry?, standing: SpeechChallenges.Standing?,
                            onBack: () -> Unit, onAgain: (() -> Unit)?,
                            /** Every take of the script, oldest first (the takes' pager): a
                             *  swipe across the picture goes to the one beside it while the
                             *  score, the sheet and the buttons stay and change to it. */
                            pages: List<String>? = null, onPage: ((String) -> Unit)? = null,
                            /** Where you are among the takes, at the top centre. */
                            indicator: (@Composable () -> Unit)? = null) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val density = LocalDensity.current
    val m = take.metrics
    val reading = m.reading
    val prefs = remember { context.getSharedPreferences("futurevoice", android.content.Context.MODE_PRIVATE) }

    // The take's video on this phone, once it is put together.
    val stored = remember(take.videoFilename, pendingVideo) {
        take.videoFilename?.takeIf { !pendingVideo }?.let { SpeechStore.mediaFile(context, it) }?.takeIf { it.exists() }
    }
    // What is behind the score: the camera and nothing else. A take whose
    // video has the script burned into it has a plain ground.
    val heroFile = stored?.takeIf { take.videoIsCameraOnly }
    val hero = remember(take.id) { SpeechHeroPlayer() }
    LaunchedEffect(hero, heroFile?.path) { hero.show(heroFile) }
    LaunchedEffect(hero) { while (true) { delay(100); hero.tick() } }
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    DisposableEffect(hero, lifecycle) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_STOP) hero.background()
            else if (event == Lifecycle.Event.ON_START) hero.foreground()
        }
        lifecycle.addObserver(observer)
        onDispose { lifecycle.removeObserver(observer); hero.stop() }
    }
    /** The script rolling over the camera while the take plays. */
    var showScript by remember { mutableStateOf(prefs.getBoolean("speech.replayShowsScript", false)) }

    var player by remember { mutableStateOf<MediaPlayer?>(null) }
    DisposableEffect(take.id) { onDispose { player?.release(); player = null } }
    fun stop() { player?.release(); player = null }
    fun play() {
        player = runCatching {
            MediaPlayer().apply {
                setDataSource(SpeechStore.mediaFile(context, take.audioFilename).path)
                setOnCompletionListener { it.release(); player = null }
                prepare(); start()
            }
        }.getOrNull()
    }
    // Playing, everything but the reader steps aside.
    val playing = hero.isPlaying || player != null

    val saving = remember(take.id) { SpeechVideoSaveState() }
    var showingVideo by remember { mutableStateOf(false) }
    /** A take from before the camera was kept: its video has the script in it. */
    var watching by remember { mutableStateOf<java.io.File?>(null) }
    val scaffold = rememberBottomSheetScaffoldState(
        bottomSheetState = rememberStandardBottomSheetState(SheetValue.PartiallyExpanded, skipHiddenState = true))
    val isOpen = scaffold.bottomSheetState.targetValue == SheetValue.Expanded
    var summaryPx by remember { mutableIntStateOf(0) }
    val navBar = with(density) { WindowInsets.navigationBars.getBottom(this).toDp() }
    val peek = with(density) { summaryPx.toDp() } + HANDLE_HEIGHT + navBar
    val heroAlpha by animateFloatAsState(if (playing || isOpen) 0f else 1f, label = "hero")
    val shadeAlpha by animateFloatAsState(if (playing) 0f else 1f, label = "shade")
    val tint = scoreColor(m.overall)

    BottomSheetScaffold(
        scaffoldState = scaffold,
        sheetPeekHeight = if (playing) 0.dp else peek,
        sheetSwipeEnabled = !playing,
        sheetContainerColor = AppSurfaces.ground,
        sheetShape = RoundedCornerShape(topStart = 24.dp, topEnd = 24.dp),
        sheetDragHandle = {
            Box(Modifier.fillMaxWidth().height(HANDLE_HEIGHT), contentAlignment = Alignment.Center) {
                Box(Modifier.width(40.dp).height(5.dp)
                    .background(MaterialTheme.colorScheme.outlineVariant, CircleShape))
            }
        },
        containerColor = Color.Black,
        sheetContent = {
            Column(Modifier.fillMaxHeight(0.92f)) {
                Column(Modifier.fillMaxWidth()
                    .onSizeChanged { summaryPx = it.height }
                    .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) {
                        scope.launch {
                            if (isOpen) scaffold.bottomSheetState.partialExpand() else scaffold.bottomSheetState.expand()
                        }
                    }) {
                    Column(Modifier.padding(horizontal = 20.dp)) {
                        Text(script.title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold,
                            maxLines = 1, overflow = TextOverflow.Ellipsis)
                        val date = takeDateLabel(take.createdAt)
                        Text(if (script.isChallenge) stringResource(R.string.challenge) + " · " + date else date,
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    Spacer(Modifier.height(10.dp))
                    ScoreStrip(scoreTiles(m))
                }
                Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).navigationBarsPadding()
                    .padding(horizontal = 16.dp).padding(bottom = 32.dp)) {
                    Details(take, script, reading, pendingVideo, entry, standing)
                }
            }
        },
    ) {
        // Older to the left, like Photos (iOS `TakesBackdrop`).
        val swipe = if (pages != null && pages.size > 1 && onPage != null && !playing) {
            Modifier.pointerInput(take.id, pages) {
                var dx = 0f
                detectHorizontalDragGestures(
                    onDragStart = { dx = 0f },
                    onHorizontalDrag = { change, amount -> change.consume(); dx += amount },
                    onDragEnd = {
                        val i = pages.indexOf(take.id)
                        val limit = 56.dp.toPx()
                        if (dx > limit && i > 0) onPage(pages[i - 1])
                        else if (dx < -limit && i in 0 until pages.lastIndex) onPage(pages[i + 1])
                    })
            }
        } else Modifier
        Box(Modifier.fillMaxSize().background(Color.Black).then(swipe)) {
            if (heroFile != null) {
                HeroVideo(hero, Modifier.fillMaxSize())
            } else {
                Box(Modifier.fillMaxSize().background(Brush.verticalGradient(listOf(tint.copy(alpha = 0.75f), Color.Black))))
            }
            // Keeps the white text readable on any picture.
            Box(Modifier.fillMaxSize().alpha(shadeAlpha).background(Brush.verticalGradient(
                0.45f to Color.Transparent, 1f to Color.Black.copy(alpha = 0.7f))))
            val record = take.prompter
            if (showScript && hero.isFull && record != null && heroFile != null) {
                // Kept while paused, unseen: laying the column out takes a moment.
                SpeechScriptOverlay(record, hero, Modifier.alpha(if (hero.isPlaying) 1f else 0f))
            }
            Row(Modifier.align(Alignment.BottomCenter).fillMaxWidth().alpha(heroAlpha)
                .padding(horizontal = 20.dp).padding(bottom = peek + 20.dp),
                verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text("${m.overall}", color = Color.White, fontSize = 96.sp, lineHeight = 100.sp, fontWeight = FontWeight.Bold)
                    if (reading != null) {
                        val lines = stringArrayResource(SpeechVerdict.lines(reading.total))
                        Text(lines[SpeechVerdict.index(take.id, lines.size)], color = Color.White,
                            style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold)
                        Text(stringResource(R.string.speech_level_format, stringResource(levelTitle(reading.level))),
                            color = Color.White, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                    }
                }
                Box(Modifier.size(64.dp).background(Color.White.copy(alpha = 0.18f), CircleShape)
                    .clickable(enabled = heroAlpha > 0.5f) {
                        if (heroFile != null) hero.toggle() else if (player != null) stop() else play()
                    },
                    contentAlignment = Alignment.Center) {
                    Icon(if (playing) Icons.Filled.Pause else Icons.Filled.PlayArrow,
                        stringResource(if (playing) R.string.pause else R.string.play), tint = Color.White,
                        modifier = Modifier.size(30.dp))
                }
            }
            if (playing) {
                // A tap on the picture pauses it, and everything comes back.
                Box(Modifier.fillMaxSize().clickable(interactionSource = remember { MutableInteractionSource() },
                    indication = null) { if (hero.isPlaying) hero.toggle() else stop() })
                if (take.prompter != null && hero.isFull) {
                    ScriptToggle(showScript, onClick = {
                        showScript = !showScript
                        prefs.edit().putBoolean("speech.replayShowsScript", showScript).apply()
                    }, modifier = Modifier.align(Alignment.BottomEnd).navigationBarsPadding().padding(20.dp))
                }
            } else {
                SheetHeader("",
                    leading = { IosGlassTextButton(stringResource(R.string.done), onClick = onBack) },
                    trailing = {
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            if (stored != null) {
                                IosGlassButton(onClick = { showingVideo = true }) {
                                    Icon(Icons.Filled.Download, stringResource(R.string.save_to_photos),
                                        tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(18.dp))
                                }
                            }
                            onAgain?.let { again ->
                                IosGlassButton(onClick = again) {
                                    Icon(Icons.Filled.Refresh, null, tint = MaterialTheme.colorScheme.primary,
                                        modifier = Modifier.size(18.dp))
                                    Spacer(Modifier.width(4.dp))
                                    Text(stringResource(R.string.again), color = MaterialTheme.colorScheme.primary,
                                        fontWeight = FontWeight.SemiBold)
                                }
                            }
                        }
                    },
                    modifier = Modifier.align(Alignment.TopCenter).statusBarsPadding()
                        .padding(horizontal = 16.dp, vertical = 8.dp),
                )
                indicator?.let {
                    Box(Modifier.align(Alignment.TopCenter).statusBarsPadding().padding(top = 14.dp)) { it() }
                }
            }
        }
    }

    if (showingVideo && stored != null) {
        SpeechVideoSheet(take, stored, saving, scope, onWatch = { watching = stored },
            onDeleted = { hero.stop() }, onDismiss = { showingVideo = false })
    }
    watching?.let { file ->
        Dialog(onDismissRequest = { watching = null },
            properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
            Box(Modifier.fillMaxSize().background(Color.Black), contentAlignment = Alignment.Center) {
                TakeVideo(file, Modifier.fillMaxSize(), autoplay = true)
                SheetHeader("", trailing = {
                    IosGlassTextButton(stringResource(R.string.done), bold = true, onClick = { watching = null })
                }, modifier = Modifier.align(Alignment.TopCenter).statusBarsPadding().padding(horizontal = 16.dp, vertical = 8.dp))
            }
        }
    }
    saving.error?.let { message ->
        AlertDialog(onDismissRequest = { saving.error = null },
            title = { Text(stringResource(R.string.couldn_t_save_to_photos)) }, text = { Text(message) },
            confirmButton = { TextButton(onClick = { saving.error = null }) { Text(stringResource(R.string.ok)) } })
    }
}

private val HANDLE_HEIGHT = 25.dp

/** The parts of the score, what the sheet shows before it is opened. A take
 *  from before Season 2's scoring has no parts of its own, so it shows the
 *  sub-scores its old total was made of — iOS `scoreTiles`. A price-list take
 *  (scoring 8) shows each area out of 100, in the receipt's order, its colour
 *  on a dot by the name. */
@Composable
private fun scoreTiles(m: com.roro.futurevoice.data.SpeechMetrics): List<Triple<String, Int, Color?>> {
    m.reading?.let { r ->
        if (r.version >= 8) return r.deductions.map { Triple(stringResource(partTitle(it.part)), r.areaScore(it), speechPartColor(it.part)) }
        return r.parts.all.map { (part, score) -> Triple(stringResource(partTitle(part)), score, null) }
    }
    val tiles = mutableListOf<Triple<String, Int, Color?>>(Triple(stringResource(R.string.accuracy), m.accuracy, null))
    m.pronunciation?.let { tiles += Triple(stringResource(R.string.pronunciation), it, null) }
    tiles += Triple(stringResource(R.string.pace), m.paceScore, null)
    tiles += Triple(stringResource(R.string.pauses), m.pauseScore, null)
    tiles += Triple(stringResource(R.string.fillers), m.fillerScore, null)
    tiles += Triple(stringResource(R.string.steady_voice), m.steadiness, null)
    return tiles
}

/** One colour per area of the price list, the same on the tiles, the receipt
 *  and the marked script (iOS `SpeechReadingScore.Part.color`). */
internal fun speechPartColor(part: SpeechReadingScore.Part): Color = when (part) {
    SpeechReadingScore.Part.PAUSES -> Color(0xFFFF9500)
    SpeechReadingScore.Part.ACCURACY -> Color(0xFFFF3B30)
    SpeechReadingScore.Part.PRONUNCIATION -> Color(0xFFAF52DE)
    SpeechReadingScore.Part.RHYTHM -> Color(0xFF007AFF)
    SpeechReadingScore.Part.SPEED -> Color(0xFF30B0C7)
}

@Composable
private fun ScoreStrip(tiles: List<Triple<String, Int, Color?>>) {
    Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp).padding(bottom = 14.dp),
        horizontalArrangement = Arrangement.spacedBy(2.dp), verticalAlignment = Alignment.Top) {
        tiles.forEach { (title, score, area) ->
            val color = scoreColor(score)
            Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text("$score", style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold, color = color)
                LinearProgressIndicator(progress = { score.coerceIn(0, 100) / 100f }, color = color,
                    trackColor = MaterialTheme.colorScheme.outlineVariant,
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 10.dp))
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    if (area != null) Box(Modifier.size(6.dp).background(area, CircleShape))
                    Text(title, style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
            }
        }
    }
}

@Composable
private fun Details(take: SpeechTake, script: SpeechScript, r: SpeechReadingScore?, pendingVideo: Boolean,
                    entry: SpeechChallenges.Entry?, standing: SpeechChallenges.Standing?) {
    FormSection(null) {
        val coaching = take.coaching
        if (coaching != null) {
            Text(coaching.headline, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.Medium,
                modifier = Modifier.padding(16.dp))
        } else {
            Row(Modifier.padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
                CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
                Spacer(Modifier.width(8.dp))
                Text(stringResource(R.string.writing_feedback), color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        coaching?.tips?.forEach { tip ->
            FormDivider()
            Row(Modifier.padding(horizontal = 16.dp, vertical = 10.dp)) {
                Icon(Icons.AutoMirrored.Filled.ArrowForward, null, tint = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.size(18.dp))
                Spacer(Modifier.width(10.dp))
                Text(tip, style = MaterialTheme.typography.bodyMedium)
            }
        }
    }

    if (script.isChallenge) SpeechChallengeEntrySection(entry, standing)

    // The video is the page itself; here only while it is being put together.
    if (pendingVideo) {
        FormSection(null) {
            Row(Modifier.padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
                CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
                Spacer(Modifier.width(10.dp))
                Text(stringResource(R.string.preparing_your_video), color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }

    if (r != null) ReadingSection(r) else MeasuredSection(take, script)

    // Scored against the old pair: judged again against the one reading, and
    // a camera take goes back on the board with it (iOS cddddcc0). Then the
    // fluent reading's sounds: a price-list take scored before they were kept
    // loses what it counted for sounds the reading itself says the same way.
    val context = LocalContext.current
    var fluentWords by remember(take.id) { mutableStateOf<List<com.roro.futurevoice.talk.SpeechReference.Word>?>(null) }
    LaunchedEffect(take.id) {
        com.roro.futurevoice.talk.SpeechReadingRejudge.run(context, take, script)?.let { judged ->
            SpeechChallenges.shared(context).enter(judged, script,
                recordedOnCamera = judged.videoFilename != null || judged.prompter != null)
        }
        fluentWords = spareFluentSounds(context, take, script)
    }
    var soundFocus by remember(take.id) { mutableStateOf<Int?>(null) }
    /** The mark whose phrase is being practised. */
    var drillMark by remember(take.id) { mutableStateOf<com.roro.futurevoice.talk.SpeechPhraseMark?>(null) }
    /** The word being heard while one of the two players plays. */
    var hearing by remember(take.id) { mutableStateOf<Int?>(null) }
    val scriptAudio = remember(take.id) { SpeechAudioPlayer("speech_take_script") }
    val futureAudio = remember(take.id) { SpeechAudioPlayer("speech_voiceover") }
    DisposableEffect(take.id) { onDispose { scriptAudio.stop(); futureAudio.stop() } }

    var marks by remember(take.id) { mutableStateOf<Pair<Boolean, List<List<SpeechAnalyzer.ScriptMark>>?>>(false to null) }
    LaunchedEffect(take.id) {
        val made = withContext(Dispatchers.Default) {
            SpeechAnalyzer.marks(script.body, take.transcript, script.language)
        }
        marks = true to made
    }
    val (ready, paragraphs) = marks
    if (paragraphs != null) {
        if (r != null) {
            val (held, pauses) = remember(paragraphs, r) { readingTiming(r, paragraphs) }
            val sounds = remember(paragraphs, r, fluentWords, take.assessments) {
                if (r.version >= 8) soundsByWord(take, script.body, paragraphs, fluentWords) else emptyMap()
            }
            FormSection(stringResource(R.string.script)) {
                // The take's own voice and the future self's under the marked
                // script, the word being heard highlighted (iOS cddddcc0).
                SpeechScriptListening(take, script, scriptAudio, futureAudio, onCurrent = { hearing = it })
                MarkedScript(paragraphs, script.language, held, pauses,
                    onMark = if (com.roro.futurevoice.talk.SpeechListenService.available(script)) ({ drillMark = it }) else null,
                    sounds = sounds, onSound = { soundFocus = it }, current = hearing)
            }
            drillMark?.let { mark ->
                SpeechPhraseDrillSheet(script, take, mark, onDismiss = { drillMark = null })
            }
            if (r.version >= 8) PriceListLegend() else Legend()
            soundFocus?.let { focus ->
                SpeechSoundsSheet(take, script, paragraphs, fluentWords, focus, onDismiss = { soundFocus = null })
            }
        } else {
            FormSection(stringResource(R.string.script),
                footer = if (take.metrics.missed.isNotEmpty()) stringResource(R.string.red_skipped_or_read_differently_the_small_red_words_are_what_c3dcaa) else null) {
                SpeechScriptListening(take, script, scriptAudio, futureAudio, onCurrent = { hearing = it })
                MarkedScript(paragraphs, script.language, current = hearing)
            }
        }
    } else if (ready && take.metrics.missed.isNotEmpty()) {
        FormSection(stringResource(R.string.skipped_or_changed)) {
            Text(take.metrics.missed.joinToString("  ·  "), color = RED,
                style = MaterialTheme.typography.bodyLarge, modifier = Modifier.padding(16.dp))
        }
    }
    if (ready && paragraphs == null) {
        var heard by remember { mutableStateOf(false) }
        FormSection(null) {
            Disclosure(stringResource(R.string.what_the_mic_heard), heard) { heard = !heard }
            if (heard) {
                SelectionContainer {
                    Text(take.transcript, style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(start = 16.dp, end = 16.dp, bottom = 16.dp))
                }
            }
        }
    }
}

private val RED = Color(0xFFFF3B30)
private val ORANGE = Color(0xFFFF9500)

@Composable
private fun Disclosure(title: String, open: Boolean, toggle: () -> Unit) {
    Row(Modifier.fillMaxWidth().clickable(onClick = toggle).padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(title, modifier = Modifier.weight(1f), style = MaterialTheme.typography.bodyLarge)
        Icon(if (open) Icons.Filled.ExpandLess else Icons.Filled.ExpandMore, null, tint = MaterialTheme.colorScheme.primary)
    }
}

@Composable
private fun ReadingSection(r: SpeechReadingScore) {
    val footer = listOfNotNull(
        if (r.version >= 8) stringResource(R.string.speech8_footer) else null,
        stringResource(R.string.speech_names_for_fun),
        stringResource(R.string.speech_native_average, SpeechReading.NATIVE_AVERAGE),
        stringResource(R.string.speech_like_karaoke),
        stringResource(R.string.speech_each_word_compared,
            stringResource(if (r.gender == "female") R.string.speech_voice_female else R.string.speech_voice_male)),
    ).joinToString("\n")
    FormSection(stringResource(R.string.speech_compared_native), footer = footer) {
        val focus = r.focus
        if (focus != null) {
            Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Filled.GpsFixed, null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(20.dp))
                    Spacer(Modifier.width(8.dp))
                    Text(stringResource(R.string.speech_next_format, stringResource(partTitle(focus))),
                        style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                }
                Text(partFocus(focus, r), style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        } else {
            Row(Modifier.padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Filled.Verified, null, tint = GREEN, modifier = Modifier.size(20.dp))
                Spacer(Modifier.width(8.dp))
                Text(stringResource(R.string.speech_narrator_read), color = GREEN)
            }
        }
        if (r.version >= 8) {
            // The receipt (scoring 8): every area what it counted and what is left.
            r.deductions.forEach { d ->
                FormDivider()
                ReceiptRow(d, r)
            }
            FormDivider()
            Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp),
                verticalAlignment = Alignment.CenterVertically) {
                Text(stringResource(R.string.speech8_total), style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
                Text("${r.total}", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
            }
        } else SpeechReadingScore.Part.entries.forEach { part ->
            FormDivider()
            Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp),
                verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(partIcon(part), null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(22.dp))
                    Spacer(Modifier.width(14.dp))
                    Text(stringResource(partTitle(part)), style = MaterialTheme.typography.bodyLarge, modifier = Modifier.weight(1f))
                    if (r.parts.score(part) >= SpeechReadingScore.BAR) {
                        Icon(Icons.Filled.Verified, stringResource(R.string.speech_at_narrator_level), tint = GREEN,
                            modifier = Modifier.size(16.dp))
                    }
                }
                Text(partDetail(part, r), style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        FormDivider()
        var bands by remember { mutableStateOf(false) }
        Disclosure(stringResource(R.string.speech_what_the_scores_mean), bands) { bands = !bands }
        if (bands) {
            Column(Modifier.fillMaxWidth().padding(start = 16.dp, end = 16.dp, bottom = 14.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)) {
                SpeechReadingLevel.entries.forEach { level ->
                    val mine = level == r.level
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(if (level.range.first == level.range.last) "${level.range.first}"
                            else "${level.range.first}–${level.range.last}",
                            style = MaterialTheme.typography.bodyMedium, modifier = Modifier.width(56.dp))
                        Text(stringResource(levelTitle(level)), style = MaterialTheme.typography.bodyMedium,
                            fontWeight = if (mine) FontWeight.SemiBold else FontWeight.Normal, modifier = Modifier.weight(1f))
                        if (mine) {
                            Text(stringResource(R.string.you), style = MaterialTheme.typography.labelMedium,
                                fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.primary)
                        }
                    }
                }
            }
        }
    }
}

private val GREEN = Color(0xFF34C759)

/** One legend for everything the script shows. */
@Composable
private fun Legend() {
    val red = stringResource(R.string.speech_legend_red)
    val added = stringResource(R.string.speech_legend_added)
    val orange = stringResource(R.string.speech_legend_orange)
    val pause = "⏸︎"
    val text = stringResource(R.string.speech_legend, red, added, orange, pause)
    val colored = listOf(red to RED, added to RED, orange to ORANGE, pause to ORANGE)
    Text(buildAnnotatedString {
        var at = 0
        for ((part, color) in colored) {
            val found = text.indexOf(part, at)
            if (found < 0) continue
            append(text.substring(at, found))
            withStyle(SpanStyle(color = color)) { append(part) }
            at = found + part.length
        }
        append(text.substring(at))
    }, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.padding(start = 16.dp, end = 16.dp, top = 7.dp))
}

/** Season 2's per-token findings laid onto the script's words: a word owns as
 *  many scoring tokens as `SpeechDelivery.referenceTokens` makes of it (a
 *  hyphenated word two, a lone dash none) — iOS `SpeechMarkedScript.timing`. */
internal fun readingTiming(r: SpeechReadingScore, marks: List<List<SpeechAnalyzer.ScriptMark>>):
    Pair<Map<Int, Double>, Map<Int, Double>> {
    val wordOfToken = HashMap<Int, Int>()
    var t = 0
    marks.flatten().forEachIndexed { w, mark ->
        repeat(SpeechDelivery.referenceTokens(mark.word).size) { wordOfToken[t] = w; t++ }
    }
    val held = HashMap<Int, Double>()
    val pauses = HashMap<Int, Double>()
    for (h in r.held) {
        val w = h.index?.let { wordOfToken[it] } ?: continue
        h.seconds?.let { held[w] = it }
    }
    for (p in r.extraPauses) {
        val w = p.index?.let { wordOfToken[it] } ?: continue
        pauses[w] = p.seconds
    }
    return held to pauses
}

/** "6.5", "4": points without a needless ".0" (iOS `points`). */
private fun points(value: Double): String =
    if (value == SpeechReading.round(value)) "${value.toInt()}" else "%.1f".format(Locale.US, value)

/** One line of the receipt: the area, what it counted, what is left of it. */
@Composable
private fun ReceiptRow(d: SpeechReadingScore.Deduction, r: SpeechReadingScore) {
    Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp),
        verticalArrangement = Arrangement.spacedBy(3.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(partIcon(d.part), null, tint = speechPartColor(d.part), modifier = Modifier.size(22.dp))
            Spacer(Modifier.width(14.dp))
            Text(stringResource(partTitle(d.part)), style = MaterialTheme.typography.bodyLarge, modifier = Modifier.weight(1f))
            if (d.points > 0) {
                Text("−" + points(kotlin.math.min(d.points, SpeechReadingScore.AREA_SHARE)),
                    style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Spacer(Modifier.width(8.dp))
            }
            Text("${r.areaScore(d)}", style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.SemiBold,
                color = scoreColor(r.areaScore(d)))
        }
        Text(receiptDetail(d, r), style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun receiptDetail(d: SpeechReadingScore.Deduction, r: SpeechReadingScore): String = when (d.part) {
    SpeechReadingScore.Part.PAUSES ->
        if (d.count == 0) stringResource(R.string.speech8_no_stops)
        else stringResource(R.string.speech8_stops_mid, d.count, extraPauseList(r.extraPauses))
    SpeechReadingScore.Part.ACCURACY -> if (d.count == 0) stringResource(R.string.speech8_every_word) else {
        val unread = r.unreadWords
        val changed = d.count - unread
        val parts = mutableListOf<String>()
        if (changed > 0) parts += stringResource(R.string.speech8_changed, changed)
        if (unread > 0) parts += stringResource(R.string.speech8_not_reached, unread)
        if (r.missed.isNotEmpty()) parts += quoted(r.missed)
        parts.joinToString(" · ")
    }
    SpeechReadingScore.Part.PRONUNCIATION -> when {
        r.weakSounds == null -> stringResource(R.string.speech8_sounds_unchecked)
        d.count == 0 -> stringResource(R.string.speech8_no_wrong_sounds)
        else -> stringResource(R.string.speech8_sounds_wrong, d.count) +
            (if (r.weakest.isEmpty()) "" else " · " + soundsList(r.weakest))
    }
    SpeechReadingScore.Part.RHYTHM ->
        stringResource(R.string.speech8_rhythm, "%.2f".format(Locale.US, r.rhythm)) +
            (if (r.held.isEmpty()) "" else " · " + stringResource(R.string.speech8_held, heldList(r.held)))
    SpeechReadingScore.Part.SPEED -> stringResource(R.string.speech8_pace_pct, r.speedPoint)
}

/** One colour per area, the same on the tiles, the receipt and here. */
@Composable
private fun PriceListLegend() {
    val orange = stringResource(R.string.speech8_orange)
    val red = stringResource(R.string.speech8_red)
    val purple = stringResource(R.string.speech8_purple)
    val blue = stringResource(R.string.speech8_blue)
    val text = stringResource(R.string.speech8_legend, orange, red, purple, blue)
    val colored = listOf(orange to speechPartColor(SpeechReadingScore.Part.PAUSES),
        red to speechPartColor(SpeechReadingScore.Part.ACCURACY),
        purple to speechPartColor(SpeechReadingScore.Part.PRONUNCIATION),
        blue to speechPartColor(SpeechReadingScore.Part.RHYTHM))
    Text(buildAnnotatedString {
        var at = 0
        for ((part, color) in colored) {
            val found = text.indexOf(part, at)
            if (found < 0) continue
            append(text.substring(at, found))
            withStyle(SpanStyle(color = color)) { append(part) }
            at = found + part.length
        }
        append(text.substring(at))
    }, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.padding(start = 16.dp, end = 16.dp, top = 7.dp))
}

/** By the script's written word: a token-indexed map moved onto the words that
 *  own the tokens (a hyphenated word owns two). */
private fun <T> byWrittenWord(marks: List<List<SpeechAnalyzer.ScriptMark>>, tokens: Map<Int, T>,
                              merge: (T, T) -> T): Map<Int, T> {
    val wordOfToken = HashMap<Int, Int>()
    var t = 0
    marks.flatten().forEachIndexed { w, mark ->
        repeat(SpeechDelivery.referenceTokens(mark.word).size) { wordOfToken[t] = w; t++ }
    }
    val out = LinkedHashMap<Int, T>()
    for ((token, value) in tokens) {
        val w = wordOfToken[token] ?: continue
        out[w] = out[w]?.let { merge(it, value) } ?: value
    }
    return out
}

/** The weak sounds of a take, by the script's written word (iOS `soundsByWord`). */
internal fun soundsByWord(take: SpeechTake, script: String, marks: List<List<SpeechAnalyzer.ScriptMark>>,
                          fluent: List<com.roro.futurevoice.talk.SpeechReference.Word>?):
    Map<Int, List<SpeechReading.WeakSound>> {
    val pieces = take.assessments
    if (pieces.isNullOrEmpty()) return emptyMap()
    return byWrittenWord(marks, SpeechReading.weakSounds(pieces, script, fluent)) { a, b -> a + b }
}

/** Loads the fluent reading's sounds and, on a price-list take scored before
 *  they were kept, takes off what it counted for sounds the reading itself
 *  says the same way (this phone's copy; a board entry stands until a better
 *  take) — iOS `spareFluentSounds`. */
private suspend fun spareFluentSounds(context: android.content.Context, take: SpeechTake,
                                      script: SpeechScript): List<com.roro.futurevoice.talk.SpeechReference.Word>? {
    val r = take.metrics.reading ?: return null
    val pieces = take.assessments
    if (r.version < 8 || pieces.isNullOrEmpty()) return null
    val fluent = com.roro.futurevoice.talk.SpeechListenService.words(context, script) ?: return null
    val count = withContext(Dispatchers.Default) {
        SpeechReading.weakSounds(pieces, script.body, fluent).values.sumOf { it.size }
    }
    if (count != r.weakSounds) {
        SpeechStore.shared(context).update(take.id) { current ->
            val reading = current.metrics.reading ?: return@update current
            val next = reading.copy(weakSounds = count)
            current.copy(metrics = current.metrics.copy(reading = next, overall = next.total))
        }
    }
    return fluent
}

/**
 * The sounds behind the purple marks (iOS `SpeechSoundsSheet`): the tapped
 * word's sounds first, then the pronunciation area and every counted sound in
 * reading order. Azure's full report stays one tap further.
 */
@Composable
private fun SpeechSoundsSheet(take: SpeechTake, script: SpeechScript, marks: List<List<SpeechAnalyzer.ScriptMark>>,
                              fluent: List<com.roro.futurevoice.talk.SpeechReference.Word>?, initialFocus: Int,
                              onDismiss: () -> Unit) {
    var focus by remember { mutableStateOf(initialFocus) }
    var showingFull by remember { mutableStateOf(false) }
    val words = remember(marks) { marks.flatten().map { it.word } }
    val spared = remember(marks, fluent) {
        byWrittenWord(marks, SpeechReading.fluentLowSounds(fluent, script.body)) { a, b -> a + b }
    }
    val judged = remember(marks, take.assessments) {
        byWrittenWord(marks, SpeechReading.judgedWords(take.assessments.orEmpty(), script.body)) { a, _ -> a }
    }
    val bar = SpeechReadingScore.Price.WEAK_SOUND_BELOW
    val purple = speechPartColor(SpeechReadingScore.Part.PRONUNCIATION)
    val counted = judged.keys.sorted().mapNotNull { w ->
        val weak = judged.getValue(w).phonemes.filter {
            (it.accuracy ?: 100) < bar && spared[w]?.contains(it.phoneme) != true
        }
        if (weak.isEmpty()) null else w to weak
    }
    val total = counted.sumOf { it.second.size }
    SpeechSheet(onDismiss) {
        SheetHeader(stringResource(R.string.pronunciation),
            trailing = { IosGlassTextButton(stringResource(R.string.done), onClick = onDismiss, bold = true) })
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 16.dp)
            .padding(bottom = 32.dp)) {
            judged[focus]?.let { word ->
                FormSection("“${words.getOrNull(focus) ?: word.word}”", footer = stringResource(R.string.speech8_sound_rule)) {
                    word.phonemes.forEachIndexed { i, p ->
                        if (i > 0) FormDivider()
                        SoundRow(p, spared = spared[focus]?.contains(p.phoneme) == true, bar = bar, purple = purple)
                    }
                }
            }
            FormSection(null) {
                Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp),
                    verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Filled.GraphicEq, null, tint = purple, modifier = Modifier.size(22.dp))
                    Spacer(Modifier.width(14.dp))
                    Text(stringResource(R.string.pronunciation), style = MaterialTheme.typography.bodyLarge,
                        modifier = Modifier.weight(1f))
                    val r = take.metrics.reading
                    val d = r?.deductions?.firstOrNull { it.part == SpeechReadingScore.Part.PRONUNCIATION }
                    if (r != null && d != null) {
                        Text("${r.areaScore(d)}", style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.SemiBold, color = scoreColor(r.areaScore(d)))
                    }
                }
                FormDivider()
                Text(stringResource(R.string.speech8_sounds_counted, total), color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp))
            }
            if (counted.isNotEmpty()) {
                FormSection(stringResource(R.string.speech8_counted_sounds)) {
                    counted.forEachIndexed { i, (w, weak) ->
                        if (i > 0) FormDivider()
                        Row(Modifier.fillMaxWidth()
                            .background(if (w == focus) Color.Yellow.copy(alpha = 0.2f) else Color.Transparent)
                            .clickable { focus = w }.padding(horizontal = 16.dp, vertical = 12.dp),
                            verticalAlignment = Alignment.CenterVertically) {
                            Text(words.getOrNull(w).orEmpty(), modifier = Modifier.weight(1f))
                            Text(weak.joinToString(" · ") { "${it.phoneme.ifEmpty { "·" }} ${it.accuracy ?: 0}" },
                                style = MaterialTheme.typography.bodyMedium, color = purple)
                        }
                    }
                }
            }
            if (!take.assessments.isNullOrEmpty()) {
                FormSection(null, footer = stringResource(R.string.speech8_full_footer)) {
                    Text(stringResource(R.string.speech8_full_assessment), color = MaterialTheme.colorScheme.primary,
                        modifier = Modifier.fillMaxWidth().clickable { showingFull = true }.padding(16.dp))
                }
            }
        }
    }
    if (showingFull) {
        com.roro.futurevoice.ui.PronunciationDetailSheet(take.assessments.orEmpty(), script.language,
            onDismiss = { showingFull = false })
    }
}

@Composable
private fun SoundRow(p: com.roro.futurevoice.talk.PronunciationResult.Phoneme, spared: Boolean, bar: Int, purple: Color) {
    val score = p.accuracy ?: 0
    val low = (p.accuracy ?: 100) < bar
    val isCounted = low && !spared
    val heard = p.heard?.firstOrNull()?.takeIf { it.phoneme != p.phoneme && it.score >= 50 }?.phoneme
    Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(p.phoneme.ifEmpty { "·" }, fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace)
        if (heard != null) {
            Text(stringResource(R.string.speech8_sounded_like, heard), style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Spacer(Modifier.weight(1f))
        if (spared && low) {
            Text(stringResource(R.string.speech8_fluent_too), style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = androidx.compose.ui.text.style.TextAlign.End,
                modifier = Modifier.weight(2f, fill = false))
        } else if (isCounted) {
            Text(stringResource(R.string.speech8_counted), style = MaterialTheme.typography.bodySmall,
                fontWeight = FontWeight.SemiBold, color = purple)
        }
        Text("$score", color = if (isCounted) purple else MaterialTheme.colorScheme.onSurfaceVariant)
    }
}
