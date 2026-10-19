package com.roro.futurevoice.ui

import android.os.Build
import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.Orientation
import androidx.compose.foundation.gestures.draggable
import androidx.compose.foundation.gestures.rememberDraggableState
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.background
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.FormatListBulleted
import androidx.compose.material.icons.filled.ClosedCaption
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Forum
import androidx.compose.material.icons.filled.GraphicEq
import androidx.compose.material.icons.filled.Headphones
import androidx.compose.material.icons.filled.Newspaper
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.outlined.Description
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.runtime.rememberCoroutineScope
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.launch
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material.icons.filled.PauseCircle
import androidx.compose.material.icons.filled.PlayCircle
import androidx.compose.material.icons.filled.Repeat
import androidx.compose.material.icons.filled.RepeatOne
import androidx.compose.material.icons.filled.Shuffle
import androidx.compose.material.icons.filled.SkipNext
import androidx.compose.material.icons.filled.SkipPrevious
import androidx.compose.material.icons.filled.Translate
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import com.roro.futurevoice.R
import com.roro.futurevoice.audio.PlaylistPlayer
import com.roro.futurevoice.data.LanguageCatalog
import com.roro.futurevoice.data.NewsShow
import com.roro.futurevoice.data.NewsShowEpisode
import com.roro.futurevoice.data.PlaylistLine
import com.roro.futurevoice.data.SceneLibrary
import com.roro.futurevoice.data.SceneTrack
import com.roro.futurevoice.data.ScenarioStore
import com.roro.futurevoice.data.WordSplitter
import com.roro.futurevoice.net.Translator
import com.roro.futurevoice.ui.brand.AppSurfaces
import com.roro.futurevoice.ui.brand.IosGlassButton
import com.roro.futurevoice.ui.brand.IosMenu
import com.roro.futurevoice.ui.brand.IosMenuDivider
import com.roro.futurevoice.ui.brand.IosMenuHeader
import com.roro.futurevoice.ui.brand.IosMenuItem
import kotlinx.coroutines.delay
import kotlin.math.roundToInt

// ── Talk tab button (iOS `PlaylistButton`) ──

/**
 * The listening door on the Talk tab: a glass circle at the bottom-left.
 * Resting, a pair of headphones; while situations play, a ring of how far
 * through the list it is. A tap brings up the player — the circle is too
 * small to mean two things.
 */
@Composable
fun PlaylistButton(onClick: () -> Unit, modifier: Modifier = Modifier) {
    val context = LocalContext.current
    LaunchedEffect(Unit) { PlaylistPlayer.attach(context) }
    val player = PlaylistPlayer
    val hasQueue = player.hasQueue
    // The ring follows the playhead, which is not observable state.
    var progress by remember { mutableStateOf(0f) }
    LaunchedEffect(hasQueue, player.isPlaying, player.isInGap, player.position) {
        progress = player.progress()
        while (player.isPlaying) { delay(200); progress = player.progress() }
    }
    val label = stringResource(R.string.my_situations)
    IosGlassButton(onClick, modifier.size(52.dp).semantics { contentDescription = label }, circle = true) {
        val accent = MaterialTheme.colorScheme.primary
        Box(Modifier.size(30.dp), contentAlignment = Alignment.Center) {
            if (hasQueue) {
                Canvas(Modifier.size(38.dp)) {
                    drawArc(accent, startAngle = -90f, sweepAngle = 360f * progress, useCenter = false,
                        style = Stroke(width = 2.5.dp.toPx(), cap = StrokeCap.Round))
                }
            }
            if (player.isPlaying) {
                PlayingBars(isAnimating = true, color = accent, modifier = Modifier.size(18.dp, 16.dp))
            } else {
                Icon(Icons.Filled.Headphones,
                    contentDescription = null, modifier = Modifier.size(22.dp),
                    tint = if (hasQueue) accent else MaterialTheme.colorScheme.onSurface)
            }
        }
    }
}

// ── Playing bars (iOS `PlayingBars`) ──

private val RESTING_BARS = listOf(0.2f, 0.35f, 0.28f, 0.18f)
/** The lowest a bar goes: about its own width, a dot. */
private const val BAR_FLOOR = 0.12f

/**
 * The "this is playing" mark: four bars driven by the LOUDNESS of what is
 * playing right now ([PlaylistPlayer.level], read off the audio itself), so
 * they rise with a voice and settle in the pause between lines (founder,
 * 2026-10-19: a made-up wave out of step with the sound read as random).
 * Every bar follows the SAME moment — each at its own share of it, re-drawn
 * as the voice moves — so the four rise and fall together and never lean
 * one way. Paused, they rest low; with animations off they keep still.
 */
@Composable
internal fun PlayingBars(isAnimating: Boolean, color: Color, modifier: Modifier = Modifier) {
    val context = LocalContext.current
    val reduceMotion = remember {
        android.provider.Settings.Global.getFloat(context.contentResolver,
            android.provider.Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f
    }
    var bars by remember { mutableStateOf(RESTING_BARS) }
    var loudness by remember { mutableStateOf(0.0) }
    val level = PlaylistPlayer.level
    LaunchedEffect(level) {
        if (!isAnimating || reduceMotion) return@LaunchedEffect
        // Fast up, slower down: a syllable shows, a pause eases out.
        loudness = maxOf(level.toDouble(), loudness * 0.8)
        // The meter rarely reads under ~0.3 while someone is talking, so that
        // much is taken off and the rest curved: quiet syllables sit near the
        // floor and only the loud ones reach the top.
        val shown = Math.pow(maxOf(0.0, (loudness - 0.25) / 0.75), 1.4).toFloat()
        bars = bars.indices.map {
            BAR_FLOOR + (1 - BAR_FLOOR) * shown * kotlin.random.Random.nextDouble(0.5, 1.0).toFloat()
        }
    }
    LaunchedEffect(isAnimating) {
        if (!isAnimating) { bars = RESTING_BARS; loudness = 0.0 }
    }
    val shown = bars.map {
        androidx.compose.animation.core.animateFloatAsState(it,
            tween(100, easing = androidx.compose.animation.core.LinearOutSlowInEasing), label = "bar").value
    }
    Canvas(modifier) {
        val count = shown.size
        val gap = size.width * 0.12f
        val width = (size.width - gap * (count - 1)) / count
        shown.forEachIndexed { i, h ->
            val barH = size.height * h
            drawRoundRect(color,
                topLeft = androidx.compose.ui.geometry.Offset(i * (width + gap), (size.height - barH) / 2),
                size = androidx.compose.ui.geometry.Size(width, barH),
                cornerRadius = androidx.compose.ui.geometry.CornerRadius(width / 2, width / 2))
        }
    }
}

// ── The player (iOS `ScenePlayerSheet`) ──

/**
 * A floating sheet that IS the player. The line being said fills the top,
 * the controls sit at the bottom and never move whatever the line's length
 * (a long line scrolls in its own space), and the situations are one tap
 * away behind the list button, opposite the options. Half height by
 * default, so the page stays visible — and usable — behind it (iOS
 * `.presentationDetents([.medium, .large])` with background interaction up
 * through medium); drag it up for the full height, down to put it away.
 *
 * Drawn by the page that hosts it, over everything, never as a modal window:
 * a Material bottom sheet would block the page behind, which iOS's doesn't.
 */
@Composable
fun ScenePlayerSheet(
    visible: Boolean,
    state: AppState,
    /** Room the sheet's large height leaves above it (the page header). */
    topInset: Dp,
    onDismiss: () -> Unit,
) {
    // Rises from the bottom edge and settles, and goes back down the same
    // way, like an iOS sheet (founder, 2026-10-19: it used to appear in one
    // frame and vanish in one). A critically damped spring: no bounce.
    AnimatedVisibility(
        visible = visible,
        enter = slideInVertically(spring(dampingRatio = 1f, stiffness = 380f)) { it },
        exit = slideOutVertically(spring(dampingRatio = 1f, stiffness = 520f)) { it },
    ) {
        ScenePlayerSheetContent(state, topInset, onDismiss)
    }
}

@Composable
private fun ScenePlayerSheetContent(
    state: AppState,
    topInset: Dp,
    onDismiss: () -> Unit,
) {
    val context = LocalContext.current
    val density = LocalDensity.current
    var tracks by remember { mutableStateOf<List<SceneTrack>>(emptyList()) }
    var shows by remember { mutableStateOf<List<NewsShowEpisode>>(emptyList()) }
    var loaded by remember { mutableStateOf(false) }
    var showingList by remember { mutableStateOf(false) }
    var large by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val listTitle = stringResource(R.string.my_situations)
    val showTitle = stringResource(R.string.nawana_podcast)
    val allLines = remember(tracks) { tracks.flatMap { it.lines } }

    LaunchedEffect(Unit) {
        PlaylistPlayer.attach(context)
        tracks = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
            SceneLibrary.tracks(context, ScenarioStore.shared(context).load(state.targetLanguage),
                state.voiceId, state.targetLanguage)
        }
        loaded = true
        shows = NewsShow.episodes(context, state.targetLanguage)
    }

    /** Every episode, newest first. Files are fetched when asked for. */
    suspend fun playAllShows() {
        kotlinx.coroutines.coroutineScope {
            shows.filter { !it.isReady }.map { e -> async { NewsShow.prepare(context, e) } }.awaitAll()
        }
        PlaylistPlayer.play(context, shows.flatMap { it.lines }, showTitle)
    }

    /** One episode on its own (founder: the whole show, or just the episode).
     *  Picked again while it is playing, it carries on rather than restarting. */
    suspend fun playShow(episode: NewsShowEpisode) {
        val p = PlaylistPlayer
        if (p.title == showTitle && p.current?.bookId == episode.id) return
        NewsShow.prepare(context, episode)
        p.play(context, episode.lines, showTitle)
    }

    fun playAll() {
        if (allLines.isEmpty()) scope.launch { playAllShows() }
        else PlaylistPlayer.play(context, allLines, listTitle)
    }

    /** Every situation plays on from the one picked, so picking a scene
     *  starts listening rather than ending at its last line. */
    fun play(from: SceneTrack) {
        val start = allLines.indexOfFirst { it.bookId == from.id }
        if (start < 0) return
        val p = PlaylistPlayer
        val at = p.lines.indexOfFirst { it.bookId == from.id }
        if (p.title == listTitle && p.lines.map { it.id } == allLines.map { it.id } && at >= 0) {
            p.jump(at)
        } else {
            p.play(context, allLines, listTitle, startAt = start)
        }
    }

    BackHandler { if (showingList) showingList = false else onDismiss() }

    BoxWithConstraints(Modifier.fillMaxSize()) {
        val full = maxHeight
        val medium = full * 0.5f
        val big = full - topInset - 10.dp
        val mediumPx = with(density) { medium.toPx() }
        val bigPx = with(density) { big.toPx() }
        // ONE number is the sheet: its visible height. A drag moves it under
        // the finger, a release carries the finger's speed into a spring to
        // the nearest detent (or away), so nothing jumps when the finger
        // lifts (founder, 2026-10-19: expanding and collapsing weren't
        // smooth — the drag was dropped to 0 on release, the sheet snapped
        // back by that much, then a fixed 320 ms tween started over).
        val sheet = remember { Animatable(mediumPx) }
        LaunchedEffect(mediumPx, bigPx) {
            if (!sheet.isRunning) sheet.snapTo(if (large) bigPx else mediumPx)
        }
        val settle = spring<Float>(dampingRatio = 1f, stiffness = 420f)
        val dragState = rememberDraggableState { delta ->
            scope.launch { sheet.snapTo((sheet.value - delta).coerceIn(0f, bigPx)) }
        }
        val shown = sheet.value
        // Below the half detent the sheet keeps its half height and slides
        // down instead of squashing its content.
        val drawnPx = maxOf(shown, mediumPx)
        val sinkPx = (mediumPx - shown).coerceAtLeast(0f)
        Column(
            Modifier.align(Alignment.BottomCenter)
                .offset { IntOffset(0, sinkPx.roundToInt()) }
                .fillMaxWidth()
                .height(with(density) { drawnPx.toDp() })
                .shadow(24.dp, RoundedCornerShape(topStart = 38.dp, topEnd = 38.dp),
                    ambientColor = Color.Black.copy(alpha = 0.2f), spotColor = Color.Black.copy(alpha = 0.2f))
                .clip(RoundedCornerShape(topStart = 38.dp, topEnd = 38.dp))
                .background(if (showingList) AppSurfaces.ground else AppSurfaces.card)
                // Swallow taps on the sheet itself, so they never reach the page.
                .clickable(remember { MutableInteractionSource() }, indication = null) {}
                .draggable(dragState, Orientation.Vertical, onDragStopped = { v ->
                    // v is downward; the height grows upward.
                    val h = sheet.value
                    val vDp = v / density.density
                    val dismissAt = mediumPx - with(density) { 80.dp.toPx() }
                    when {
                        vDp < -1000f -> { large = true; sheet.animateTo(bigPx, settle, -v) }
                        vDp > 1000f && h <= mediumPx + 1f -> onDismiss()
                        vDp > 1000f -> { large = false; sheet.animateTo(mediumPx, settle, -v) }
                        h < dismissAt -> onDismiss()
                        h > (mediumPx + bigPx) / 2 -> { large = true; sheet.animateTo(bigPx, settle, -v) }
                        else -> { large = false; sheet.animateTo(mediumPx, settle, -v) }
                    }
                }),
        ) {
            // The grabber, as iOS draws one on a sheet with two detents.
            Box(Modifier.fillMaxWidth().padding(top = 6.dp), contentAlignment = Alignment.Center) {
                Box(Modifier.size(36.dp, 5.dp).clip(RoundedCornerShape(3.dp))
                    .background(MaterialTheme.colorScheme.onSurface.copy(alpha = 0.18f)))
            }
            if (showingList) {
                PlayerLibrary(tracks, shows, state, onBack = { showingList = false },
                    onPick = { play(it); showingList = false },
                    onPickShow = { playShow(it) }, onPlayAllShows = { playAllShows() })
            } else {
                SheetHeader(stringResource(R.string.player),
                    leading = {
                        val enabled = tracks.isNotEmpty() || shows.isNotEmpty()
                        IosGlassButton({ if (enabled) showingList = true }, circle = true) {
                            Icon(Icons.AutoMirrored.Filled.FormatListBulleted,
                                contentDescription = stringResource(R.string.situations),
                                tint = MaterialTheme.colorScheme.onSurface.copy(alpha = if (enabled) 1f else 0.3f))
                        }
                    },
                    trailing = { PlayerOptionsMenu() },
                    modifier = Modifier.padding(horizontal = 16.dp).padding(top = 4.dp, bottom = 4.dp))
                Column(Modifier.weight(1f).fillMaxWidth().padding(horizontal = 24.dp).padding(top = 4.dp)) {
                    Box(Modifier.weight(1f).fillMaxWidth()) {
                        NowPlayingCaption(isEmpty = loaded && tracks.isEmpty() && shows.isEmpty(), state = state)
                    }
                    PlayerControls(onPlayAll = { playAll() }, canPlay = tracks.isNotEmpty() || shows.isNotEmpty(),
                        modifier = Modifier.padding(top = 12.dp, bottom = 20.dp))
                }
                Spacer(Modifier.height(with(density) {
                    androidx.compose.foundation.layout.WindowInsets.Companion.navigationBars.getBottom(density).toDp()
                }))
            }
        }
    }
}

private const val LIBRARY_TAB_KEY = "futurevoice.playlist.tab"

/**
 * What there is to hear, behind two tabs: the nawana Podcast (the platform's
 * daily episodes) and the learner's own situations. Picking one plays it and
 * goes back to the player.
 */
@Composable
private fun PlayerLibrary(
    tracks: List<SceneTrack>,
    shows: List<NewsShowEpisode>,
    state: AppState,
    onBack: () -> Unit,
    onPick: (SceneTrack) -> Unit,
    onPickShow: suspend (NewsShowEpisode) -> Unit,
    onPlayAllShows: suspend () -> Unit,
) {
    val context = LocalContext.current
    val prefs = remember { context.getSharedPreferences("futurevoice", 0) }
    var podcastTab by remember { mutableStateOf(prefs.getString(LIBRARY_TAB_KEY, "podcast") != "situations") }
    /** What is being fetched right now: an episode, or [ALL_ID] for Play all. */
    var fetching by remember { mutableStateOf<String?>(null) }
    var reading by remember { mutableStateOf<NewsShowEpisode?>(null) }
    val scope = rememberCoroutineScope()

    /** Fetch, play, then back to the player. One fetch at a time. */
    fun fetch(id: String, action: suspend () -> Unit) {
        if (fetching != null) return
        fetching = id
        scope.launch {
            action()
            fetching = null
            onBack()
        }
    }

    SheetHeader(stringResource(R.string.listen),
        leading = { com.roro.futurevoice.ui.brand.IosBackButton(onBack, Modifier) },
        modifier = Modifier.padding(end = 16.dp).padding(top = 4.dp, bottom = 4.dp))
    // The two tabs sit under the bar at full width, the system's own segmented
    // row (founder: squeezed into the bar beside Back, it looked off).
    com.roro.futurevoice.ui.brand.IosSegmented(
        listOf(stringResource(R.string.podcast), stringResource(R.string.my_situations)),
        selected = if (podcastTab) 0 else 1,
        onSelect = { i ->
            podcastTab = i == 0
            prefs.edit().putString(LIBRARY_TAB_KEY, if (podcastTab) "podcast" else "situations").apply()
        },
        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp))
    Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(16.dp)) {
        if (podcastTab) {
            if (shows.isEmpty()) {
                LibraryEmpty(Icons.Filled.Newspaper, stringResource(R.string.nawana_podcast),
                    stringResource(R.string.a_new_episode_every_day_in_english_for_now))
            } else {
                GroupedCard {
                    Row(Modifier.fillMaxWidth().clickable { fetch(ALL_ID) { onPlayAllShows() } }
                        .padding(horizontal = 16.dp, vertical = 11.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        Icon(Icons.Filled.PlayArrow, contentDescription = null,
                            tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(22.dp))
                        Text(stringResource(R.string.play_all), style = MaterialTheme.typography.bodyLarge,
                            color = MaterialTheme.colorScheme.primary, modifier = Modifier.weight(1f))
                        if (fetching == ALL_ID) CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
                    }
                    shows.forEach { episode ->
                        GroupedRowDivider()
                        Row(Modifier.fillMaxWidth().padding(end = 8.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            Box(Modifier.weight(1f).clickable { fetch(episode.id) { onPickShow(episode) } }
                                .padding(start = 16.dp, top = 11.dp, bottom = 11.dp)) {
                                EpisodeRow(episode, fetching == episode.id)
                            }
                            // The script, on the Speech tab's own page, with Study.
                            val scriptLabel = stringResource(R.string.script)
                            Box(Modifier.size(36.dp).clip(androidx.compose.foundation.shape.CircleShape)
                                .clickable {
                                    com.roro.futurevoice.core.Analytics.capture("podcast_script_opened",
                                        mapOf("episode" to episode.number, "category" to (episode.category ?: "")))
                                    reading = episode
                                }
                                .semantics { contentDescription = scriptLabel },
                                contentAlignment = Alignment.Center) {
                                Icon(Icons.Outlined.Description, contentDescription = null,
                                    tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(22.dp))
                            }
                        }
                    }
                }
            }
        } else if (tracks.isEmpty()) {
            LibraryEmpty(Icons.Filled.Headphones, stringResource(R.string.no_situations_to_hear_yet),
                stringResource(R.string.watch_a_situation_once_and_it_plays_here_both_voices_wheneve_11cd3e))
        } else {
            val player = PlaylistPlayer
            GroupedCard {
                tracks.forEachIndexed { i, track ->
                    if (i > 0) GroupedRowDivider()
                    val playing = player.hasQueue && player.current?.bookId == track.id
                    Row(
                        Modifier.fillMaxWidth().clickable { onPick(track) }
                            .padding(horizontal = 16.dp, vertical = 11.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        Box(Modifier.width(24.dp), contentAlignment = Alignment.Center) {
                            if (playing) {
                                PlayingBars(player.isPlaying || player.isInGap, MaterialTheme.colorScheme.primary,
                                    Modifier.size(16.dp, 14.dp))
                            } else {
                                Icon(Icons.Filled.Forum, contentDescription = null,
                                    tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(22.dp))
                            }
                        }
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                            Text(track.title, style = MaterialTheme.typography.bodyLarge,
                                color = if (playing) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface,
                                maxLines = 2, overflow = TextOverflow.Ellipsis)
                            Text(track.otherName, style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                }
            }
        }
    }
    reading?.let { episode ->
        com.roro.futurevoice.ui.speech.SpeechScriptSheet(episode.script, state.nativeLanguage,
            onEdited = {}, onDismiss = { reading = null },
            initialStudy = episode.study(state.nativeLanguage), shipped = true)
    }
}

private const val ALL_ID = "all"

/** iOS `ContentUnavailableView`, as a list row. */
@Composable
private fun LibraryEmpty(icon: androidx.compose.ui.graphics.vector.ImageVector, title: String, description: String) {
    Column(Modifier.fillMaxWidth().padding(top = 40.dp, start = 16.dp, end = 16.dp),
        horizontalAlignment = Alignment.CenterHorizontally) {
        Icon(icon, contentDescription = null, modifier = Modifier.size(44.dp),
            tint = MaterialTheme.colorScheme.onSurfaceVariant)
        Spacer(Modifier.height(12.dp))
        Text(title, style = MaterialTheme.typography.titleLarge.copy(fontWeight = FontWeight.Bold),
            textAlign = TextAlign.Center)
        Spacer(Modifier.height(6.dp))
        Text(description, style = MaterialTheme.typography.bodyMedium, textAlign = TextAlign.Center,
            color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun EpisodeRow(episode: NewsShowEpisode, fetching: Boolean) {
    val context = LocalContext.current
    val player = PlaylistPlayer
    val playing = player.hasQueue && player.current?.bookId == episode.id
    val locale = java.util.Locale.forLanguageTag(
        com.roro.futurevoice.core.UILanguage.current(context) ?: java.util.Locale.getDefault().toLanguageTag())
    val day = java.text.SimpleDateFormat(
        android.text.format.DateFormat.getBestDateTimePattern(locale, "MMMd"), locale).format(java.util.Date(episode.date))
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Box(Modifier.width(24.dp), contentAlignment = Alignment.Center) {
            when {
                fetching -> CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
                playing -> PlayingBars(player.isPlaying || player.isInGap, MaterialTheme.colorScheme.primary,
                    Modifier.size(16.dp, 14.dp))
                else -> Icon(categoryIcon(episode.category), contentDescription = null,
                    tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(22.dp))
            }
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(episode.title, style = MaterialTheme.typography.bodyLarge,
                color = if (playing) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface,
                maxLines = 2, overflow = TextOverflow.Ellipsis)
            // The hosts are the same on every episode; how long it is helps choose.
            Text(stringResource(R.string.lld_min_a6e2ff, "EP ${episode.number} · $day", episode.minutes),
                style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

// ── Now playing (iOS `NowPlayingCaption`) ──

private const val CAPTIONS_KEY = "futurevoice.playlist.captions"
private const val TRANSLATION_KEY = "futurevoice.playlist.translation"

/** The two caption switches, shared by the caption and the options menu
 *  (iOS `@AppStorage`). */
private object CaptionPrefs {
    var showCaptions by mutableStateOf<Boolean?>(null)
    var showTranslation by mutableStateOf<Boolean?>(null)

    fun load(context: android.content.Context) {
        if (showCaptions != null) return
        val p = context.getSharedPreferences("futurevoice", 0)
        showCaptions = p.getBoolean(CAPTIONS_KEY, true)
        showTranslation = p.getBoolean(TRANSLATION_KEY, false)
    }

    fun setCaptions(context: android.content.Context, on: Boolean) {
        showCaptions = on
        context.getSharedPreferences("futurevoice", 0).edit().putBoolean(CAPTIONS_KEY, on).apply()
    }

    fun setTranslation(context: android.content.Context, on: Boolean) {
        showTranslation = on
        context.getSharedPreferences("futurevoice", 0).edit().putBoolean(TRANSLATION_KEY, on).apply()
    }
}

/**
 * Who is speaking and the line in karaoke — words already said in full
 * colour, the word being said in the accent, the rest dimmed — with its
 * meaning in the learner's own language when they want it. A long line
 * scrolls here so the controls below it never move.
 */
@Composable
private fun NowPlayingCaption(isEmpty: Boolean, state: AppState) {
    val context = LocalContext.current
    CaptionPrefs.load(context)
    val showCaptions = CaptionPrefs.showCaptions ?: true
    val showTranslation = CaptionPrefs.showTranslation ?: false
    val player = PlaylistPlayer
    val line = player.current
    var translation by remember { mutableStateOf<String?>(null) }
    var revealed by remember { mutableStateOf<String?>(null) }
    var nowMs by remember { mutableIntStateOf(0) }

    LaunchedEffect(line?.id, player.isPlaying) {
        nowMs = player.positionMs()
        while (player.isPlaying) { delay(40); nowMs = player.positionMs() }
    }

    LaunchedEffect(line?.id, showTranslation) {
        translation = null
        if (!showTranslation || line == null ||
            LanguageCatalog.sameLanguage(state.nativeLanguage, state.targetLanguage)) return@LaunchedEffect
        // A podcast line is shown only in the translations it shipped with:
        // made once by the publisher and read by everyone. It never asks for
        // a new one per phone (founder, 2026-10-19: API cost).
        line.translations?.let { shipped -> translation = shipped[state.nativeLanguage]; return@LaunchedEffect }
        Translator.cached(context, line.text, state.nativeLanguage)?.let { translation = it; return@LaunchedEffect }
        val t = Translator.translate(context, line.text, state.nativeLanguage)
        if (player.current?.id == line.id) translation = t
    }

    when {
        line != null -> Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(line.speaker, style = MaterialTheme.typography.labelLarge.copy(fontWeight = FontWeight.SemiBold),
                    color = if (line.isFluentSelf) MaterialTheme.colorScheme.primary
                        else MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
                Text("${player.position + 1} / ${player.order.size}",
                    style = MaterialTheme.typography.bodySmall.copy(
                        fontFeatureSettings = "tnum"),
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Column(Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(8.dp)) {
                val hidden = !showCaptions && revealed != line.id
                Text(caption(line, nowMs, state.targetLanguage),
                    style = MaterialTheme.typography.titleLarge.copy(fontWeight = FontWeight.Medium),
                    modifier = Modifier
                        .then(if (hidden) {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) Modifier.blur(7.dp)
                            else Modifier.alpha(0.12f)
                        } else Modifier)
                        .clickable(remember { MutableInteractionSource() }, indication = null) {
                            if (!showCaptions) revealed = line.id
                        }
                        .semantics { contentDescription = line.text })
                val t = translation
                if (showTranslation && t != null) {
                    Text(t, style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            Text(line.bookTitle, style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f),
                maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        isEmpty -> Column(Modifier.fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center) {
            // iOS `ContentUnavailableView`.
            Icon(Icons.Filled.Headphones, contentDescription = null, modifier = Modifier.size(44.dp),
                tint = MaterialTheme.colorScheme.onSurfaceVariant)
            Spacer(Modifier.height(12.dp))
            Text(stringResource(R.string.no_situations_to_hear_yet),
                style = MaterialTheme.typography.titleLarge.copy(fontWeight = FontWeight.Bold),
                textAlign = TextAlign.Center)
            Spacer(Modifier.height(6.dp))
            Text(stringResource(R.string.watch_a_situation_once_and_it_plays_here_both_voices_wheneve_11cd3e),
                style = MaterialTheme.typography.bodyMedium, textAlign = TextAlign.Center,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        else -> Column(Modifier.fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center) {
            Icon(Icons.Filled.Forum, contentDescription = null, modifier = Modifier.size(40.dp),
                tint = MaterialTheme.colorScheme.primary)
            Spacer(Modifier.height(10.dp))
            Text(stringResource(R.string.press_play_to_hear_every_situation_or_pick_one_from_the_list),
                style = MaterialTheme.typography.bodyMedium, textAlign = TextAlign.Center,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
private fun caption(line: PlaylistLine, nowMs: Int, language: String): AnnotatedString {
    val player = PlaylistPlayer
    val timings = player.timings
    if (timings.isEmpty()) return AnnotatedString(line.text)
    val finished = !player.isPlaying || player.isInGap
    val separator = if (WordSplitter.spaced(language)) " " else ""
    val ink = MaterialTheme.colorScheme.onSurface
    val accent = MaterialTheme.colorScheme.primary
    val dim = MaterialTheme.colorScheme.onSurfaceVariant
    return buildAnnotatedString {
        timings.forEachIndexed { i, t ->
            val color = when {
                finished || nowMs >= t.endMs -> ink
                nowMs >= t.startMs -> accent
                else -> dim
            }
            withStyle(SpanStyle(color = color)) { append(t.word) }
            if (i < timings.size - 1) append(separator)
        }
    }
}

// ── Controls (iOS `PlayerControls`) ──

/** Shuffle · previous · play/pause · next · repeat. Always the same row in
 *  the same place; before anything is loaded, play starts every situation. */
@Composable
private fun PlayerControls(onPlayAll: () -> Unit, canPlay: Boolean, modifier: Modifier = Modifier) {
    val player = PlaylistPlayer
    val ink = MaterialTheme.colorScheme.onSurface
    val accent = MaterialTheme.colorScheme.primary
    val secondary = MaterialTheme.colorScheme.onSurfaceVariant
    @Composable
    fun control(icon: androidx.compose.ui.graphics.vector.ImageVector, label: String, tint: Color,
                enabled: Boolean = true, size: Dp = 28.dp, onClick: () -> Unit) {
        Box(Modifier.clip(androidx.compose.foundation.shape.CircleShape)
            .clickable(enabled = enabled, onClick = onClick).padding(6.dp)) {
            Icon(icon, contentDescription = label, modifier = Modifier.size(size),
                tint = if (enabled) tint else tint.copy(alpha = 0.3f))
        }
    }
    Row(modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween) {
        control(Icons.Filled.Shuffle, stringResource(R.string.shuffle),
            if (player.shuffle) accent else secondary) { player.toggleShuffle(!player.shuffle) }
        control(Icons.Filled.SkipPrevious, stringResource(R.string.previous), ink,
            enabled = player.hasQueue) { player.previous() }
        val active = player.isPlaying || player.isInGap
        control(if (active) Icons.Filled.PauseCircle else Icons.Filled.PlayCircle,
            stringResource(if (player.isPlaying) R.string.pause else R.string.play), ink,
            enabled = player.hasQueue || canPlay, size = 60.dp) {
            if (player.hasQueue) player.togglePlayPause() else onPlayAll()
        }
        control(Icons.Filled.SkipNext, stringResource(R.string.next), ink,
            enabled = player.hasQueue) { player.next() }
        control(if (player.repeatMode == PlaylistPlayer.RepeatMode.ONE) Icons.Filled.RepeatOne else Icons.Filled.Repeat,
            stringResource(R.string.repeat),
            if (player.repeatMode == PlaylistPlayer.RepeatMode.OFF) secondary else accent) { player.cycleRepeat() }
    }
}

// ── Options (iOS `PlayerOptionsMenu`) ──

/** Captions, translation, the pause between lines, and Stop. */
@Composable
private fun PlayerOptionsMenu() {
    val context = LocalContext.current
    CaptionPrefs.load(context)
    val player = PlaylistPlayer
    var open by remember { mutableStateOf(false) }
    Box {
        IosGlassButton({ open = true }, circle = true) {
            Icon(Icons.Filled.MoreHoriz, contentDescription = stringResource(R.string.options),
                tint = MaterialTheme.colorScheme.onSurface)
        }
        IosMenu(open, { open = false }) {
            IosMenuItem(stringResource(R.string.captions), checked = CaptionPrefs.showCaptions == true,
                icon = Icons.Filled.ClosedCaption,
                onClick = { open = false; CaptionPrefs.setCaptions(context, CaptionPrefs.showCaptions != true) })
            IosMenuItem(stringResource(R.string.translation), checked = CaptionPrefs.showTranslation == true,
                icon = Icons.Filled.Translate,
                onClick = { open = false; CaptionPrefs.setTranslation(context, CaptionPrefs.showTranslation != true) })
            IosMenuDivider()
            // iOS nests the picker as a submenu; it is drawn inline here.
            IosMenuHeader(stringResource(R.string.pause_between_lines))
            listOf(PlaylistPlayer.Gap.NONE to R.string.no_pause,
                PlaylistPlayer.Gap.SHORT to R.string.s_1_second,
                PlaylistPlayer.Gap.ECHO to R.string.time_to_say_it_back).forEach { (g, label) ->
                IosMenuItem(stringResource(label), checked = player.gap == g,
                    onClick = { open = false; player.chooseGap(g) })
            }
            IosMenuDivider()
            IosMenuHeader(stringResource(R.string.speed))
            player.speeds.forEach { sp ->
                IosMenuItem(if (sp == 1f) "1×" else "${java.math.BigDecimal(sp.toString()).stripTrailingZeros().toPlainString()}×",
                    checked = player.speed == sp,
                    onClick = { open = false; player.chooseSpeed(sp) })
            }
            if (player.hasQueue) {
                IosMenuDivider()
                IosMenuItem(stringResource(R.string.stop_playing), icon = Icons.Filled.Close, destructive = true,
                    onClick = { open = false; player.close() })
            }
        }
    }
}
