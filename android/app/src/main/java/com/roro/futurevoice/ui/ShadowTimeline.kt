package com.roro.futurevoice.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Undo
import androidx.compose.material.icons.filled.PauseCircle
import androidx.compose.material.icons.filled.PlayCircle
import androidx.compose.material.icons.filled.Repeat
import androidx.compose.material.icons.filled.RepeatOn
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
                val maxX = with(density) { (wPx).toDp() } - 2.5.dp
                Box(Modifier.offset(x = minOf(maxX, maxOf(0.dp, xOf(position))), y = (-4).dp)
                    .width(2.5.dp).height(TL.trackHeight + 8.dp).clip(CircleShape)
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
        Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(20.dp)) {
                Icon(if (playing) Icons.Filled.PauseCircle else Icons.Filled.PlayCircle,
                    contentDescription = null, tint = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.size(44.dp).clip(CircleShape).clickable {
                        if (player.isPlaying) { player.pause(); return@clickable }
                        if (!player.isLoaded) player.load(audio)
                        player.rate = rate
                        val s = selectionMs(selection, timings)
                        if (s != null) player.playSegment(s.first, playbackEnd(s.second, selection, timings, player), loop)
                        else {
                            val start = if (player.positionMs < player.durationMs - 50) player.positionMs else 0
                            player.playSegment(start, null, loop)
                        }
                    })
                Icon(if (loop) Icons.Filled.RepeatOn else Icons.Filled.Repeat, contentDescription = null,
                    tint = if (loop) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.size(44.dp).clip(CircleShape)
                        .clickable { loop = !loop; player.loop = loop }.padding(6.dp))
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
                Icon(Icons.AutoMirrored.Filled.Undo, contentDescription = stringResource(R.string.previous_selection),
                    tint = if (canUndo) MaterialTheme.colorScheme.onSurfaceVariant
                    else MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.35f),
                    modifier = Modifier.size(44.dp).clip(CircleShape)
                        .clickable(enabled = canUndo) {
                            val prev = history.removeAt(history.lastIndex)
                            suppress = true
                            onSelection(prev)
                        }.border(2.dp, if (canUndo) MaterialTheme.colorScheme.onSurfaceVariant
                        else MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.35f), CircleShape)
                        .padding(9.dp))
            }
            mic()
        }
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
