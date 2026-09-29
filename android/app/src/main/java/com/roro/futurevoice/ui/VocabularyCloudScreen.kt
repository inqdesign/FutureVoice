package com.roro.futurevoice.ui

import android.content.Context
import androidx.activity.compose.BackHandler
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.EaseOut
import androidx.compose.animation.core.VectorConverter
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Bookmark
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.FilterList
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.util.VelocityTracker
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.roro.futurevoice.R
import com.roro.futurevoice.data.CefrLevel
import com.roro.futurevoice.data.CloudLayout
import com.roro.futurevoice.data.CoreVocabulary
import com.roro.futurevoice.data.SessionStore
import com.roro.futurevoice.data.StoreEvents
import com.roro.futurevoice.data.VocabLemmas
import com.roro.futurevoice.data.VocabStore
import com.roro.futurevoice.talk.TurnRole
import com.roro.futurevoice.ui.brand.AppSurfaces
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlin.math.floor
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * The word cloud — the whole core vocabulary of the target language, floating
 * in space. Port of iOS's `VocabularyView`: the same packing
 * ([CloudLayout]), the same parallax pan with momentum and rubber-banding,
 * the same elliptical vignette, the same level filter and "hide words I know"
 * toggle, and the same title ("B1 · 1 / 4078").
 *
 * **Size encodes DIFFICULTY, not familiarity.** [sizeFor] is
 * `VocabularyView.size(for:)` unchanged — A1 biggest, C2 smallest — which is
 * what gives the "All levels" cloud its depth; inside a single level every
 * word is the same difficulty, so one comfortable reading size is used
 * instead. What a word's STATE changes is its weight and colour (met →
 * regular and secondary; unmet → semibold and primary) plus the corner badge,
 * exactly as iOS draws it.
 *
 * Two places the port diverges, both platform rather than design:
 *
 *  - **Culling is indexed, not linear.** iOS filters its whole node array
 *    inside the `ForEach` on every frame; at 8,000 words Compose cannot walk
 *    that on the main thread per frame, so [CloudLayout] returns its nodes
 *    y-sorted and the viewport is taken as a binary-searched SLICE of them.
 *    The visible set is re-derived only every [CULL_QUANTUM] px of pan (a
 *    `derivedStateOf`, so a drag is layout + draw and not recomposition), and
 *    the cull margin carries matching head-room so nothing pops in late.
 *  - **"Met" is re-derived from the talks.** Android's `VocabStore` exposes no
 *    bulk read of its records — one word per file read — so probing 8,000 of
 *    them is not an option. This is the constraint `LibraryScreen` already
 *    works under and it takes the same answer: one pass over the finished
 *    sessions rebuilds exactly what `VocabStore.ingest` wrote, and only the
 *    notebook (short) is probed word by word.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun VocabularyCloudScreen(
    language: String,
    /** Shadowing runs its own screen; the word card hands it one line. */
    onShadow: (String) -> Unit = {},
    onBack: () -> Unit,
) {
    BackHandler(onBack = onBack)
    val context = LocalContext.current
    val density = LocalDensity.current
    val revision by StoreEvents.revision.collectAsStateWithLifecycle()
    val prefs = remember { context.getSharedPreferences("futurevoice", Context.MODE_PRIVATE) }

    /**
     * Start at the learner's own level. iOS also honours a jump from Progress
     * ("See C1 words"); Android has no such entry point yet, so the band is
     * simply where the learner is.
     */
    var level by remember {
        mutableStateOf<CefrLevel?>(CefrLevel.from(prefs.getString(LEVEL_KEY, "b1")))
    }
    var hideKnown by remember { mutableStateOf(prefs.getBoolean(HIDE_KNOWN_KEY, true)) }
    var filterOpen by remember { mutableStateOf(false) }

    var marks by remember(language) { mutableStateOf(Marks()) }
    var cloud by remember(language) { mutableStateOf(CloudLayout.Cloud()) }
    /** The tapped word's card; null while the cloud has the screen to itself. */
    var openWord by remember { mutableStateOf(
        com.roro.futurevoice.capture.flags.PracticeCaptureFlags.cloudOpenWord) }

    /** The word the always-up notebook peek shows (iOS `NotebookSheet` at its
     *  resting height). Null = the notebook's first word. */
    var peekWord by remember(language) { mutableStateOf<String?>(null) }

    LaunchedEffect(language, revision) { marks = loadMarks(context, language) }

    // Off the main thread, as iOS lays out on a detached task — opening the
    // page and changing the filter must not stutter.
    LaunchedEffect(language, level, density.density, density.fontScale) {
        cloud = withContext(Dispatchers.Default) {
            CloudLayout.layout(itemsFor(level, language), density.density, density.fontScale)
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                colors = AppSurfaces.topBarColors(),
                title = {
                    // The header reflects the active filter: a specific level
                    // shows its label and how many of THAT level's words you
                    // have met; "All levels" shows the overall pool.
                    val lv = level
                    if (lv != null) {
                        Text("${lv.code.uppercase()} · ${marks.metAt[lv] ?: 0} / " +
                            "${marks.totals[lv] ?: 0}")
                    } else {
                        Text(stringResource(R.string.cloud_words_total,
                            marks.met.size, marks.poolSize))
                    }
                },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = null)
                    }
                },
                actions = {
                    Box {
                        IconButton(onClick = { filterOpen = true }) {
                            Icon(Icons.Filled.FilterList,
                                contentDescription = stringResource(R.string.level_7c7f5d))
                        }
                        DropdownMenu(expanded = filterOpen,
                            onDismissRequest = { filterOpen = false }) {
                            DropdownMenuItem(
                                text = { Text(stringResource(R.string.hide_words_i_know)) },
                                trailingIcon = {
                                    Switch(checked = hideKnown, onCheckedChange = null)
                                },
                                onClick = {
                                    hideKnown = !hideKnown
                                    prefs.edit().putBoolean(HIDE_KNOWN_KEY, hideKnown).apply()
                                },
                            )
                            HorizontalDivider()
                            LevelRow(null, level == null) { level = null; filterOpen = false }
                            CefrLevel.entries.forEach { lv ->
                                LevelRow(lv, level == lv) { level = lv; filterOpen = false }
                            }
                        }
                    }
                },
            )
        }
    ) { padding ->
        Box(Modifier.padding(padding).fillMaxSize()) {
            Cloud(
                modifier = Modifier.fillMaxSize().background(AppSurfaces.ground),
                cloud = cloud,
                marks = marks,
                hideKnown = hideKnown,
                // Stay on the peek — it shows the meaning, so tapping through
                // the cloud is a quick-check loop with no sheet to close.
                onTap = { peekWord = it },
            )
            NotebookPeek(
                word = peekWord ?: marks.studyingOrder.firstOrNull(),
                studyingCount = marks.studyingOrder.size,
                language = language,
                onOpen = { openWord = it },
                modifier = Modifier.align(Alignment.BottomCenter),
            )
        }
    }

    openWord?.let { word ->
        // The card walks the NOTEBOOK, as iOS's `WordCard` does — a cloud of
        // 8,000 words is a place to FIND one, not a list to page through. A
        // word not yet kept leads the list, so previous/next still goes
        // somewhere and the card opens on the word that was tapped.
        val terms = remember(word, marks) {
            if (word in marks.studying) marks.studyingOrder
            else listOf(word) + marks.studyingOrder
        }
        WordCardSheet(
            terms = terms,
            initialTerm = word,
            kind = LibraryKind.WORDS,
            language = language,
            onShadow = { line -> openWord = null; onShadow(line) },
            onDismiss = { openWord = null },
        )
    }
}

/**
 * The notebook, always up under the cloud (iOS `NotebookSheet` at its
 * `peekHeight`): the word, its part of speech and its FIRST meaning. A tap
 * opens the full card — dragging a sheet is the slowest way to ask for more.
 * Docked rather than a modal sheet, because a modal one would take the cloud's
 * pan away (iOS lets the background through; Compose's sheet does not).
 */
@Composable
private fun NotebookPeek(
    word: String?,
    studyingCount: Int,
    language: String,
    onOpen: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val lore = remember { com.roro.futurevoice.net.WordLore(com.roro.futurevoice.data.AuthRepository()) }
    val nativeLanguage = remember {
        context.getSharedPreferences("futurevoice", 0).getString("futurevoice.nativeLanguage", null) ?: "en"
    }
    var entry by remember { mutableStateOf<com.roro.futurevoice.net.WordLore.Entry?>(null) }
    var loading by remember { mutableStateOf(false) }
    LaunchedEffect(word, language) {
        // `loading` FIRST: clearing the entry before it flashes "no entry".
        loading = true
        entry = null
        entry = word?.let { runCatching { lore.entry(it, nativeLanguage, language) }.getOrNull() }
        loading = false
    }
    androidx.compose.material3.Surface(
        modifier = modifier.fillMaxWidth().height(220.dp)
            .then(if (word != null) Modifier.clickable { onOpen(word) } else Modifier),
        shape = androidx.compose.foundation.shape.RoundedCornerShape(topStart = 22.dp, topEnd = 22.dp),
        color = MaterialTheme.colorScheme.surface,
        shadowElevation = 8.dp,
    ) {
        Column(Modifier.fillMaxSize().padding(horizontal = 22.dp)) {
            Box(Modifier.fillMaxWidth().padding(top = 8.dp, bottom = 6.dp), contentAlignment = Alignment.Center) {
                Box(Modifier.size(width = 36.dp, height = 5.dp).background(
                    MaterialTheme.colorScheme.outlineVariant, androidx.compose.foundation.shape.CircleShape))
            }
            Text(stringResource(R.string.my_words_lld, studyingCount),
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.fillMaxWidth(), textAlign = androidx.compose.ui.text.style.TextAlign.Center)
            if (word == null) {
                Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.Center,
                    horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(stringResource(R.string.tap_a_word_in_the_cloud_to_start_your_notebook),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        textAlign = androidx.compose.ui.text.style.TextAlign.Center)
                }
                return@Column
            }
            Spacer(Modifier.height(8.dp))
            Text(word, fontSize = 30.sp, fontWeight = FontWeight.Bold, maxLines = 1,
                color = MaterialTheme.colorScheme.onSurface)
            val sub = listOfNotNull(CoreVocabulary.reading(word, language),
                entry?.pos?.takeIf { it.isNotBlank() }).joinToString(" · ")
            if (sub.isNotEmpty()) Text(sub, style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1)
            Spacer(Modifier.height(10.dp))
            val first = entry?.senses?.firstOrNull()
            when {
                first != null -> {
                    Text(first.meaning, style = MaterialTheme.typography.bodyLarge, maxLines = 2,
                        color = MaterialTheme.colorScheme.onSurface)
                    // More than one sense: say so, rather than letting the peek
                    // read as the whole truth.
                    val extra = (entry?.senses?.size ?: 1) - 1
                    if (extra > 0) Text(
                        if (extra == 1) stringResource(R.string.s_1_more_meaning)
                        else stringResource(R.string.lld_more_meanings, extra),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                loading -> androidx.compose.material3.CircularProgressIndicator(
                    Modifier.size(20.dp), strokeWidth = 2.dp)
                else -> Text(stringResource(R.string.no_dictionary_entry_yet_tap_to_open_the_card),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

private const val LEVEL_KEY = "futurevoice.proficiency"
private const val HIDE_KNOWN_KEY = "futurevoice.vocab.hideKnown"

@Composable
private fun LevelRow(level: CefrLevel?, checked: Boolean, onClick: () -> Unit) {
    DropdownMenuItem(
        text = { Text(level?.code?.uppercase() ?: stringResource(R.string.all_levels)) },
        leadingIcon = {
            // The column stays reserved whether or not the row is the chosen
            // one, so picking another doesn't shuffle the labels sideways.
            Icon(Icons.Filled.Check, contentDescription = null,
                modifier = Modifier.size(18.dp),
                tint = if (checked) MaterialTheme.colorScheme.primary else Color.Transparent)
        },
        onClick = onClick,
    )
}

// ── The cloud itself ──

/** How far the canvas edge may travel into the screen, as a fraction of it. */
private const val OVERSCROLL = 0.35f

/** Cull margin — iOS's 70pt. */
private const val CULL_MARGIN_DP = 70f

/**
 * The visible set is re-derived only when the pan has moved this far (px), so
 * a drag recomposes a handful of times a second rather than every frame. The
 * cull margin absorbs the slack, so nothing appears late.
 */
private const val CULL_QUANTUM = 96f

/**
 * Momentum carried past the finger. iOS takes 40% of the flick's PROJECTION,
 * and UIKit projects at `v * decelerationRate / (1 - decelerationRate) / 1000`
 * ≈ `v * 0.5` — so 40% of that is a fifth of the velocity.
 */
private const val FLICK_CARRY = 0.2f

@Composable
private fun Cloud(
    modifier: Modifier,
    cloud: CloudLayout.Cloud,
    marks: Marks,
    hideKnown: Boolean,
    onTap: (String) -> Unit,
) {
    val density = LocalDensity.current
    val scope = rememberCoroutineScope()

    BoxWithConstraints(modifier.clipToBounds()) {
        val viewport = Offset(constraints.maxWidth.toFloat(), constraints.maxHeight.toFloat())
        val margin = with(density) { CULL_MARGIN_DP.dp.toPx() } + CULL_QUANTUM

        val pan = remember { Animatable(Offset.Zero, Offset.VectorConverter) }
        /** The un-rubber-banded accumulation, so a drag past the edge tracks. */
        var raw by remember { mutableStateOf(Offset.Zero) }

        // Centre a fresh canvas, as iOS's `rebuild(center: true)` does.
        LaunchedEffect(cloud, viewport) {
            if (cloud.nodes.isEmpty() || viewport == Offset.Zero) return@LaunchedEffect
            val start = clampPan(
                Offset(viewport.x / 2f - cloud.width / 2f, viewport.y / 2f - cloud.height / 2f),
                viewport, cloud,
            )
            pan.snapTo(start)
            raw = start
        }

        // Quantized pan. `derivedStateOf` is what keeps a drag out of
        // recomposition: the value only changes once per CULL_QUANTUM px.
        val quantized by remember(cloud) {
            derivedStateOf {
                Offset(floor(pan.value.x / CULL_QUANTUM) * CULL_QUANTUM,
                    floor(pan.value.y / CULL_QUANTUM) * CULL_QUANTUM)
            }
        }
        val visible = remember(cloud, viewport, quantized, hideKnown, marks) {
            visibleNodes(cloud, quantized, viewport, margin, hideKnown, marks.met)
        }

        Layout(
            modifier = Modifier
                .fillMaxSize()
                .pointerInput(cloud, viewport) {
                    val tracker = VelocityTracker()
                    detectDragGestures(
                        onDragStart = { tracker.resetTracking(); raw = pan.value },
                        onDrag = { change, drag ->
                            tracker.addPosition(change.uptimeMillis, change.position)
                            raw += drag
                            // snapTo takes the mutex, which cancels any
                            // momentum animation still running.
                            scope.launch { pan.snapTo(rubberBanded(raw, viewport, cloud)) }
                        },
                        onDragEnd = {
                            // Carry a fraction of the flick so the cloud keeps
                            // drifting briefly after the finger lifts, then
                            // eases to rest inside the canvas bounds.
                            val v = tracker.calculateVelocity()
                            val target = clampPan(
                                pan.value + Offset(v.x * FLICK_CARRY, v.y * FLICK_CARRY),
                                viewport, cloud,
                            )
                            raw = target
                            scope.launch { pan.animateTo(target, tween(600, easing = EaseOut)) }
                        },
                        onDragCancel = {
                            val target = clampPan(pan.value, viewport, cloud)
                            raw = target
                            scope.launch { pan.animateTo(target, tween(250, easing = EaseOut)) }
                        },
                    )
                },
            content = {
                visible.forEach { node ->
                    key(node.word) { CloudWord(node, pan, viewport, marks, onTap) }
                }
            },
        ) { measurables, constraints ->
            val placeables = measurables.map { it.measure(Constraints()) }
            layout(constraints.maxWidth, constraints.maxHeight) {
                val cx = constraints.maxWidth / 2f
                val cy = constraints.maxHeight / 2f
                // A layout-phase read: panning re-PLACES, it never re-composes.
                val p = pan.value
                placeables.forEachIndexed { i, placeable ->
                    val n = visible[i]
                    val sx = cx + (n.x + p.x - cx) * n.depth
                    val sy = cy + (n.y + p.y - cy) * n.depth
                    placeable.place((sx - placeable.width / 2f).roundToInt(),
                        (sy - placeable.height / 2f).roundToInt())
                }
            }
        }
    }
}

/**
 * One word. Parallax: its offset from the viewport centre is scaled by its
 * depth, so near words sweep faster than far ones as you drag — but the drift
 * stays bounded by the screen, so the collision-free packing survives panning.
 * The fade reads `pan` inside a draw-phase lambda, so a drag never recomposes
 * it.
 */
@Composable
private fun CloudWord(
    node: CloudLayout.Node,
    pan: Animatable<Offset, *>,
    viewport: Offset,
    marks: Marks,
    onTap: (String) -> Unit,
) {
    val met = node.word in marks.met
    val studying = node.word in marks.studying
    val interaction = remember { MutableInteractionSource() }
    val badge = with(LocalDensity.current) { max(8f, node.sizeSp * 0.42f).sp.toDp() }

    Box(
        Modifier
            .graphicsLayer {
                // Elliptical vignette: full strength in the middle, gently
                // fading toward the screen edges — not a min-dimension circle
                // that leaves the top/bottom of tall screens empty.
                val cx = viewport.x / 2f
                val cy = viewport.y / 2f
                if (cx <= 0f || cy <= 0f) return@graphicsLayer
                val p = pan.value
                val sx = cx + (node.x + p.x - cx) * node.depth
                val sy = cy + (node.y + p.y - cy) * node.depth
                alpha = (1.25f - hypot((sx - cx) / cx, (sy - cy) / cy)).coerceIn(0f, 1f)
            }
            .clickable(interactionSource = interaction, indication = null) { onTap(node.word) }
    ) {
        Text(
            node.word,
            fontSize = node.sizeSp.sp,
            fontWeight = if (met) FontWeight.Normal else FontWeight.SemiBold,
            color = if (met) MaterialTheme.colorScheme.onSurfaceVariant
            else MaterialTheme.colorScheme.onSurface,
            maxLines = 1,
        )
        // Status badge, floating just off the word's leading top corner — the
        // same grammar as the word card's toolbar: bookmark = studying,
        // check = met. Drawn outside the box, so it never widens the node.
        if (studying || met) {
            Icon(
                if (studying) Icons.Filled.Bookmark else Icons.Filled.Check,
                contentDescription = null,
                modifier = Modifier
                    .size(badge)
                    .graphicsLayer {
                        translationX = -4.dp.toPx()
                        translationY = -badge.toPx()
                    },
                tint = if (studying) MaterialTheme.colorScheme.primary else KNOWN_GREEN,
            )
        }
    }
}

/** The retirement tick, the same green `LibraryScreen`'s rows use. */
private val KNOWN_GREEN = Color(0xFF34C759)

// ── Pan bounds (the canvas is finite — never show blank space past its edge) ──

/**
 * Overscroll head-room: the canvas edge can travel ~a third of the way into
 * the screen, so words in the outermost rows and columns are readable — not
 * stuck clipped at the viewport edge or faded out by the vignette — without
 * ever exposing more than a sliver of empty space past the cloud. A canvas
 * SMALLER than the viewport (a tiny level filter) is pinned centred.
 */
private fun panRange(span: Float, pad: Float): ClosedFloatingPointRange<Float> =
    if (span < 0f) (span - pad)..pad else (span / 2f)..(span / 2f)

private fun bounds(viewport: Offset, cloud: CloudLayout.Cloud):
    Pair<ClosedFloatingPointRange<Float>, ClosedFloatingPointRange<Float>>? {
    if (cloud.width <= 0f || cloud.height <= 0f || viewport == Offset.Zero) return null
    return panRange(viewport.x - cloud.width, viewport.x * OVERSCROLL) to
        panRange(viewport.y - cloud.height, viewport.y * OVERSCROLL)
}

private fun clampPan(p: Offset, viewport: Offset, cloud: CloudLayout.Cloud): Offset {
    val b = bounds(viewport, cloud) ?: return p
    return Offset(p.x.coerceIn(b.first), p.y.coerceIn(b.second))
}

/**
 * During a drag, movement past the edge is allowed but resisted; the release
 * clamp then settles it back inside — the familiar rubber-band feel.
 */
private fun rubberBanded(p: Offset, viewport: Offset, cloud: CloudLayout.Cloud): Offset {
    val b = bounds(viewport, cloud) ?: return p
    fun soft(v: Float, r: ClosedFloatingPointRange<Float>): Float = when {
        v < r.start -> r.start + (v - r.start) * 0.25f
        v > r.endInclusive -> r.endInclusive + (v - r.endInclusive) * 0.25f
        else -> v
    }
    return Offset(soft(p.x, b.first), soft(p.y, b.second))
}

// ── Culling ──

/**
 * The nodes that can reach the screen at this pan. The canvas is y-sorted, so
 * the viewport is one binary-searched slice of it and only that slice is
 * tested for x. Depth shifts a word by up to ±10% of its distance from the
 * centre, so the slice is widened to cover the whole depth band.
 */
private fun visibleNodes(
    cloud: CloudLayout.Cloud,
    pan: Offset,
    viewport: Offset,
    margin: Float,
    hideKnown: Boolean,
    met: Set<String>,
): List<CloudLayout.Node> {
    if (cloud.nodes.isEmpty() || viewport == Offset.Zero) return emptyList()

    // screen = c + (node + pan - c) * depth  →  node = c + (screen - c) / depth - pan
    fun span(lo: Float, hi: Float, c: Float, p: Float): Pair<Float, Float> {
        var mn = Float.MAX_VALUE
        var mx = -Float.MAX_VALUE
        for (s in floatArrayOf(lo, hi)) for (d in floatArrayOf(0.9f, 1.1f)) {
            val v = c + (s - c) / d - p
            mn = min(mn, v); mx = max(mx, v)
        }
        return mn to mx
    }

    val (yLo, yHi) = span(-margin, viewport.y + margin, viewport.y / 2f, pan.y)
    val (xLo, xHi) = span(-margin, viewport.x + margin, viewport.x / 2f, pan.x)

    val out = ArrayList<CloudLayout.Node>(96)
    var i = CloudLayout.firstIndexAtOrAfter(cloud.nodes, yLo)
    while (i < cloud.nodes.size) {
        val n = cloud.nodes[i]
        if (n.y > yHi) break
        if (n.x >= xLo && n.x <= xHi && (!hideKnown || n.word !in met)) out.add(n)
        i++
    }
    return out
}

// ── The words, and what the learner has done with them ──

/**
 * Easier (A1) words bigger, harder (C2) smaller — size encodes difficulty,
 * giving depth when "All levels" is shown. Verbatim from
 * `VocabularyView.size(for:)`.
 */
private fun sizeFor(level: CefrLevel): Float = when (level) {
    CefrLevel.A1 -> 28f
    CefrLevel.A2 -> 24f
    CefrLevel.B1 -> 20.5f
    CefrLevel.B2 -> 18f
    CefrLevel.C1 -> 16f
    CefrLevel.C2 -> 14.5f
}

/**
 * Pure and thread-safe (the pool is an immutable map behind a lazy read), so
 * the heavy layout can run off the main thread without blocking the screen.
 *
 * Within a single level every word is the same difficulty, so grading the
 * font by level would just make the whole cloud uniformly huge (A1) or tiny
 * (C2) — one comfortable reading size instead.
 */
private fun itemsFor(level: CefrLevel?, language: String): List<CloudLayout.Item> {
    val all = CoreVocabulary.wordsAtOrAbove(CefrLevel.A1, language)
    return if (level == null) {
        all.mapNotNull { w ->
            CoreVocabulary.level(w, language)?.let { CloudLayout.Item(w, sizeFor(it)) }
        }
    } else {
        all.filter { CoreVocabulary.level(it, language) == level }
            .map { CloudLayout.Item(it, 21f) }
    }
}

/**
 * What the learner has done with the pool: which words they have MET (said in
 * a talk, or retired by hand) and which they are keeping. Both sets are tiny
 * next to the cloud, so membership is one hash lookup per drawn word. The
 * per-level tallies the title needs are counted here too — off the main
 * thread, once per language — rather than re-counted on every recomposition.
 */
private data class Marks(
    val met: Set<String> = emptySet(),
    val studying: Set<String> = emptySet(),
    /** Notebook order (newest first) — what the word card pages through. */
    val studyingOrder: List<String> = emptyList(),
    val totals: Map<CefrLevel, Int> = emptyMap(),
    val metAt: Map<CefrLevel, Int> = emptyMap(),
    val poolSize: Int = 0,
)

/**
 * See the screen's note: `VocabStore` has no bulk read, so the said-words half
 * is rebuilt from the talks the way `ingest` wrote it — one pass over the
 * finished sessions — and only the notebook is probed word by word.
 */
private suspend fun loadMarks(context: Context, language: String): Marks =
    withContext(Dispatchers.Default) {
        val vocab = VocabStore.shared(context)
        val core = CoreVocabulary.set(language)

        val met = HashSet<String>()
        for (session in SessionStore.shared(context).load(language)) {
            if (session.endedAt == null) continue
            val texts = session.turns.filter { it.role == TurnRole.USER }.map { it.transcript }
            for (word in VocabLemmas.lemmas(texts)) if (word in core) met.add(word)
        }

        val keys = ArrayList<String>(0)
        for (word in vocab.studying(language)) {
            val key = word.trim().lowercase()
            if (key.isEmpty()) continue
            keys.add(key)
            // Retired by hand: a record with no talk behind it is still a word
            // the learner has met, which is what "hide words I know" hides.
            if (vocab.state(key, language) != null) met.add(key)
        }

        val totals = HashMap<CefrLevel, Int>()
        for (word in core) CoreVocabulary.level(word, language)?.let {
            totals[it] = (totals[it] ?: 0) + 1
        }
        val metAt = HashMap<CefrLevel, Int>()
        for (word in met) CoreVocabulary.level(word, language)?.let {
            metAt[it] = (metAt[it] ?: 0) + 1
        }

        Marks(met = met, studying = keys.toHashSet(), studyingOrder = keys,
            totals = totals, metAt = metAt, poolSize = core.size)
    }
