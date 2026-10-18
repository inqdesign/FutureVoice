package com.roro.futurevoice.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.ui.layout.layout
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.requiredHeight
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Undo
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Repeat
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.positionChange
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.roro.futurevoice.R
import com.roro.futurevoice.audio.TargetPlayer
import com.roro.futurevoice.talk.WordTiming
import com.roro.futurevoice.ui.brand.iosFill
import kotlinx.coroutines.delay
import java.io.File
import java.util.Locale
import kotlin.math.abs

/**
 * The trimmer under the shadow line — iOS `ShadowTimelinePlayer`. The loop
 * region is a band with grabbable START and END handles; the selection is a
 * WORD range shared with the line above (tap words there, or drag here), so
 * either edit moves the loop. Play/pause and loop on the left, the mic in
 * the middle, speed and "previous selection" on the right.
 */
private object TL {
    val speeds = listOf(0.5f, 0.75f, 1f, 1.25f)
    val trackHeight = 54.dp
    val handleW = 14.dp
    val grab = 24.dp
    val playheadW = 2.5.dp
    /** SF Symbols' `*.circle` buttons at 44 pt: the circle IS the button. */
    val glyphButton = 44.dp
    /** The control row's design width; narrower bars scale it down. */
    val controlsWidth = 320.dp
    /** The ring of an outlined `*.circle` symbol (measured: 3.7 pt at 44). */
    val ring = 3.5.dp
    /** Played past a selection's last word so its release isn't clipped. */
    const val TAIL_RELEASE_MS = 140
}

@Composable
fun ShadowTimeline(
    audio: File,
    timings: List<WordTiming>,
    selection: IntRange?,
    onSelection: (IntRange?) -> Unit,
    player: TargetPlayer,
    mic: @Composable () -> Unit,
) {
    var loop by remember { mutableStateOf(false) }
    var rate by remember { mutableFloatStateOf(1f) }
    var playing by remember { mutableStateOf(false) }
    var position by remember { mutableIntStateOf(0) }
    var duration by remember { mutableIntStateOf(0) }
    var speedMenu by remember { mutableStateOf(false) }
    // Every committed change pushes the region being left; back pops one.
    val history = remember { mutableStateListOf<IntRange>() }
    var lastSeen by remember { mutableStateOf(selection) }
    var dragging by remember { mutableStateOf(false) }
    var dragStart by remember { mutableStateOf<IntRange?>(null) }
    var suppress by remember { mutableStateOf(false) }
    val currentSelection by androidx.compose.runtime.rememberUpdatedState(selection)

    LaunchedEffect(audio) {
        player.load(audio)
        duration = player.durationMs
        // Whole line selected by default: visible handles teach at a glance
        // that the loop region can be moved.
        if (selection == null && timings.isNotEmpty()) onSelection(0..timings.lastIndex)
    }
    // Playhead + state, polled — MediaPlayer has no observable clock.
    LaunchedEffect(Unit) {
        while (true) {
            playing = player.isPlaying
            position = player.positionMs
            if (duration == 0) duration = player.durationMs
            delay(33)
        }
    }
    // Word-tap selections land in history too (drags commit on release).
    LaunchedEffect(selection) {
        if (!dragging) {
            if (suppress) suppress = false
            else lastSeen?.let { old -> if (old != selection) history.add(old) }
        }
        lastSeen = selection
        if (player.isPlaying) selectionMs(selection, timings)?.let { (s, e) ->
            player.updateSegment(s, playbackEnd(e, selection, timings, player))
        }
    }

    // The track ends where the SPEECH does, not the file's silent tail.
    val trackEnd: Int = run {
        val spoken = (timings.lastOrNull()?.endMs ?: 0) + TL.TAIL_RELEASE_MS
        // Before the player reports a length, the words are the length.
        val file = if (duration > 0) duration else maxOf(spoken, 1_000)
        if (spoken in 1 until file) spoken else file
    }
    val sel = selectionMs(selection, timings)

    Column(
        Modifier.fillMaxWidth()
            .shadow(10.dp, RoundedCornerShape(28.dp), ambientColor = Color.Black.copy(alpha = 0.12f),
                spotColor = Color.Black.copy(alpha = 0.12f))
            .clip(RoundedCornerShape(28.dp))
            .background(MaterialTheme.colorScheme.surface)
            .border(0.5.dp, MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.4f), RoundedCornerShape(28.dp))
            .padding(horizontal = 18.dp, vertical = 20.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        BoxWithConstraints(Modifier.fillMaxWidth().padding(horizontal = 4.dp).height(TL.trackHeight)) {
            val wPx = constraints.maxWidth.toFloat()
            val density = LocalDensity.current
            fun xOf(ms: Int): Dp = with(density) { (ms.coerceIn(0, trackEnd).toFloat() / trackEnd * wPx).toDp() }
            fun msAt(x: Float): Int = (x / wPx * trackEnd).toInt().coerceIn(0, trackEnd)
            val grabPx = with(density) { TL.grab.toPx() }
            Box(
                Modifier.fillMaxWidth().height(TL.trackHeight)
                    .pointerInput(timings, trackEnd) {
                        awaitEachGesture {
                            val down = awaitFirstDown()
                            val startX = down.position.x
                            val now = selectionMs(currentSelection, timings)
                            val sx = now?.let { it.first.toFloat() / trackEnd * wPx }
                            val ex = now?.let { it.second.toFloat() / trackEnd * wPx }
                            val mode = when {
                                sx != null && abs(startX - sx) < grabPx -> 0
                                ex != null && abs(startX - ex) < grabPx -> 1
                                else -> 2
                            }
                            dragging = true
                            dragStart = currentSelection
                            var moved = 0f
                            var x = startX
                            while (true) {
                                val ev = awaitPointerEvent()
                                val ch = ev.changes.firstOrNull() ?: break
                                if (!ch.pressed) break
                                moved += abs(ch.positionChange().x)
                                x = ch.position.x
                                ch.consume()
                                val i = wordIndexAt(timings, msAt(x)) ?: continue
                                val r = currentSelection ?: (i..i)
                                when (mode) {
                                    0 -> onSelection(minOf(i, r.last)..r.last)
                                    1 -> onSelection(r.first..maxOf(i, r.first))
                                    else -> {
                                        val j = wordIndexAt(timings, msAt(startX)) ?: i
                                        if (moved >= 6) onSelection(minOf(i, j)..maxOf(i, j))
                                    }
                                }
                            }
                            // A tap only moves the playhead — collapsing the
                            // selection to one word would silently turn the
                            // next take into a one-word shadow.
                            if (mode == 2 && moved < 6) player.seek(msAt(x))
                            dragging = false
                            dragStart?.let { from -> if (from != currentSelection) history.add(from) }
                            dragStart = null
                        }
                    },
            ) {
                Box(Modifier.fillMaxWidth().height(TL.trackHeight).clip(RoundedCornerShape(8.dp))
                    .background(iosFill()))
                timings.forEach { t ->
                    Box(Modifier.offset(x = xOf(t.startMs), y = (TL.trackHeight - 16.dp) / 2)
                        .width(1.5.dp).height(16.dp)
                        .background(MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.3f)))
                }
                if (sel != null) {
                    val sxd = xOf(sel.first); val exd = xOf(sel.second)
                    Box(Modifier.offset(x = sxd).width(maxOf(0.dp, exd - sxd)).height(TL.trackHeight)
                        .clip(RoundedCornerShape(8.dp))
                        .background(MaterialTheme.colorScheme.primary.copy(alpha = 0.18f)))
                    Handle(sxd); Handle(exd)
                }
                // Playhead — iOS: a 2.5-wide capsule, 8 taller than the track
                // and CENTRED on it (4 over, 4 under), its left edge at the
                // time, kept inside the track, ringed in the page colour.
                // `requiredHeight`, not `height`: the track box caps its
                // children at its own 54, which squashed the capsule to the
                // track's height and the -4 then lifted it off the bottom.
                val maxX = with(density) { (wPx).toDp() } - TL.playheadW
                val halo = MaterialTheme.colorScheme.surface
                Box(Modifier.offset(x = minOf(maxX, maxOf(0.dp, xOf(position))))
                    .width(TL.playheadW).requiredHeight(TL.trackHeight + 8.dp)
                    .drawBehind {
                        val r = 1.dp.toPx()
                        drawRoundRect(halo.copy(alpha = 0.8f), topLeft = Offset(-r, -r),
                            size = Size(size.width + 2 * r, size.height + 2 * r),
                            cornerRadius = CornerRadius(size.width / 2 + r))
                    }
                    .clip(CircleShape)
                    .background(MaterialTheme.colorScheme.onSurface))
            }
        }
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            val style = MaterialTheme.typography.labelMedium
            val muted = MaterialTheme.colorScheme.onSurfaceVariant
            Text(timeLabel(position), style = style, color = muted)
            Spacer(Modifier.weight(1f))
            if (sel != null) Text(stringResource(R.string.loop, timeLabel(sel.first), timeLabel(sel.second)),
                style = style, color = MaterialTheme.colorScheme.primary)
            else Text(stringResource(R.string.full_line), style = style, color = muted)
            Spacer(Modifier.weight(1f))
            Text(timeLabel(trackEnd), style = style, color = muted)
        }
        // The row is built for TL.controlsWidth: four 44 dp circles and the
        // speed chip around a 60 dp mic laid over the middle. On a narrower
        // bar (the phone's display size turned up) the mic sat on the loop
        // button, so there the whole row is drawn smaller instead — same
        // arrangement, same proportions, nothing overlapping.
        Box(Modifier.fillMaxWidth().shrinkToFit(TL.controlsWidth), contentAlignment = Alignment.Center) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(20.dp)) {
                // `play.circle.fill` / `pause.circle.fill`: a filled accent
                // circle, the glyph cut out of it.
                CircleGlyph(if (playing) Icons.Filled.Pause else Icons.Filled.PlayArrow,
                    filled = true, color = MaterialTheme.colorScheme.primary, glyph = if (playing) 26.dp else 30.dp) {
                    if (player.isPlaying) { player.pause(); return@CircleGlyph }
                    if (!player.isLoaded) player.load(audio)
                    player.rate = rate
                    val s = selectionMs(selection, timings)
                    if (s != null) player.playSegment(s.first, playbackEnd(s.second, selection, timings, player), loop)
                    else {
                        val start = if (player.positionMs < player.durationMs - 50) player.positionMs else 0
                        player.playSegment(start, null, loop)
                    }
                }
                // `repeat.circle.fill` (accent) when on, `repeat.circle`
                // (secondary ring) when off — the same circle as play.
                CircleGlyph(Icons.Filled.Repeat, filled = loop,
                    color = if (loop) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
                    glyph = 30.dp) { loop = !loop; player.loop = loop }
                Spacer(Modifier.weight(1f))
                Box {
                    Text(speedLabel(rate), style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.SemiBold,
                        color = if (rate == 1f) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.primary,
                        modifier = Modifier.clip(CircleShape).background(iosFill())
                            .clickable { speedMenu = true }.padding(horizontal = 12.dp, vertical = 9.dp))
                    com.roro.futurevoice.ui.brand.IosDropdownMenu(expanded = speedMenu, onDismissRequest = { speedMenu = false }) {
                        TL.speeds.forEach { r ->
                            com.roro.futurevoice.ui.brand.IosMenuItem(speedLabel(r), checked = rate == r,
                                onClick = { rate = r; player.rate = r; speedMenu = false })
                        }
                    }
                }
                val canUndo = history.isNotEmpty()
                // `arrow.uturn.backward.circle`: a secondary ring, tertiary
                // until there is a region to step back to.
                CircleGlyph(Icons.AutoMirrored.Filled.Undo, filled = false,
                    color = if (canUndo) MaterialTheme.colorScheme.onSurfaceVariant
                    else MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.3f),
                    glyph = 26.dp, enabled = canUndo,
                    contentDescription = stringResource(R.string.previous_selection)) {
                    val prev = history.removeAt(history.lastIndex)
                    suppress = true
                    onSelection(prev)
                }
            }
            mic()
        }
    }
}

/** An SF `*.circle` / `*.circle.fill` symbol at 44 pt: a 44 circle, filled
 *  with [color] and the glyph white, or a [color] ring around a [color]
 *  glyph. Play, loop and undo all draw through it so the row matches. */
@Composable
private fun CircleGlyph(
    icon: ImageVector,
    filled: Boolean,
    color: Color,
    glyph: Dp,
    enabled: Boolean = true,
    contentDescription: String? = null,
    onClick: () -> Unit,
) {
    Box(Modifier.size(TL.glyphButton).clip(CircleShape)
        .then(if (filled) Modifier.background(color) else Modifier.border(TL.ring, color, CircleShape))
        .clickable(enabled = enabled, onClick = onClick),
        contentAlignment = Alignment.Center) {
        Icon(icon, contentDescription = contentDescription,
            tint = if (filled) Color.White else color, modifier = Modifier.size(glyph))
    }
}

@Composable
private fun Handle(x: Dp) {
    Box(Modifier.offset(x = x - TL.handleW / 2).width(TL.handleW).height(TL.trackHeight)
        .clip(RoundedCornerShape(5.dp)).background(MaterialTheme.colorScheme.primary),
        contentAlignment = Alignment.Center) {
        Box(Modifier.width(2.dp).height(16.dp).clip(CircleShape).background(Color.White.copy(alpha = 0.9f)))
    }
}

private fun selectionMs(r: IntRange?, timings: List<WordTiming>): Pair<Int, Int>? {
    if (r == null || r.first < 0 || r.last >= timings.size) return null
    return timings[r.first].startMs to timings[r.last].endMs
}

/** A selection running to the last word plays the file out; otherwise the
 *  release window keeps the last word's tail. */
private fun playbackEnd(endMs: Int, r: IntRange?, timings: List<WordTiming>, player: TargetPlayer): Int? =
    if (r != null && r.last == timings.lastIndex) null else endMs + TL.TAIL_RELEASE_MS

private fun wordIndexAt(timings: List<WordTiming>, ms: Int): Int? {
    if (timings.isEmpty()) return null
    timings.forEachIndexed { i, t -> if (ms in t.startMs..t.endMs) return i }
    return timings.indices.minByOrNull { abs(timings[it].startMs - ms) }
}

private fun timeLabel(ms: Int): String {
    val s = ms / 1000.0
    return String.format(Locale.US, "%d:%04.1f", (s / 60).toInt(), s % 60)
}

private fun speedLabel(r: Float): String =
    if (r == 1f) "1×" else String.format(Locale.US, "%s×", r.toString().trimEnd('0').trimEnd('.'))

/** Lay the content out at [designWidth] and draw it scaled down to fit when
 *  the space is narrower; at or above it, nothing changes. */
private fun Modifier.shrinkToFit(designWidth: Dp): Modifier = this.then(
    Modifier.layout { measurable, constraints ->
        val design = designWidth.roundToPx()
        if (!constraints.hasBoundedWidth || constraints.maxWidth >= design) {
            val p = measurable.measure(constraints)
            return@layout layout(p.width, p.height) { p.place(0, 0) }
        }
        val p = measurable.measure(constraints.copy(minWidth = design, maxWidth = design))
        val k = constraints.maxWidth.toFloat() / design
        layout(constraints.maxWidth, (p.height * k).toInt()) {
            p.placeWithLayer(0, 0) {
                transformOrigin = androidx.compose.ui.graphics.TransformOrigin(0f, 0f)
                scaleX = k; scaleY = k
            }
        }
    })
