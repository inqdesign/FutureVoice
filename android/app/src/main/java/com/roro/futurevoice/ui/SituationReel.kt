package com.roro.futurevoice.ui

import android.provider.Settings
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.wrapContentHeight
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import com.roro.futurevoice.R
import kotlin.math.abs
import kotlin.math.floor
import kotlin.math.roundToInt

/**
 * Example situations rolling slowly past the empty situation box (iOS
 * `SituationReel`, `9fe8cc7`).
 *
 * Two jobs, and the second is why it moves: it answers "what do I even put
 * here", and because every line is written at the length the field asks for,
 * it SHOWS what "the more detail, the better" means far better than a
 * sentence saying so.
 *
 * Touch FREEZES the roll and lifting picks the line the finger landed on —
 * hit-tested against the offset held at touch-down, so the line that was under
 * the finger is the one that lands, never the one that scrolled into its
 * place. A drag picks nothing. With animations turned off (the system's
 * reduce-motion) the same lines sit still and pick the same way.
 */
@Composable
fun SituationReel(lines: List<String>, onPick: (String) -> Unit, modifier: Modifier = Modifier) {
    val context = LocalContext.current
    val density = LocalDensity.current
    val rowHeight = 80.dp
    val visibleRows = 3
    /** How long one example takes to cross its own height — a thing to READ,
     *  not a ticker. */
    val secondsPerRow = 4.5f
    val reduceMotion = remember {
        runCatching {
            Settings.Global.getFloat(context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f
        }.getOrDefault(false)
    }
    val label = stringResource(R.string.example_situations)

    if (reduceMotion || lines.isEmpty()) {
        Column(modifier.fillMaxWidth().semantics { contentDescription = label }) {
            lines.take(visibleRows).forEach { line ->
                ReelRow(line, Modifier.height(rowHeight).clickable { onPick(line) })
            }
        }
        return
    }

    val rowPx = with(density) { rowHeight.toPx() }
    val loopPx = rowPx * lines.size
    var offset by remember { mutableFloatStateOf(0f) }
    var frozen by remember { mutableStateOf(false) }
    LaunchedEffect(lines, frozen) {
        if (frozen) return@LaunchedEffect
        var last = 0L
        val speed = rowPx / secondsPerRow
        while (true) {
            withFrameNanos { now ->
                if (last != 0L) offset = (offset + speed * (now - last) / 1e9f) % loopPx
                last = now
            }
        }
    }
    val slop = with(density) { 12.dp.toPx() }

    Box(
        modifier.fillMaxWidth().height(rowHeight * visibleRows).clipToBounds()
            .semantics { contentDescription = label }
            .graphicsLayer { compositingStrategy = CompositingStrategy.Offscreen }
            .drawWithContent {
                drawContent()
                drawRect(
                    Brush.verticalGradient(
                        0f to Color.Transparent, 0.25f to Color.Black,
                        0.75f to Color.Black, 1f to Color.Transparent),
                    blendMode = BlendMode.DstIn)
            }
            .pointerInput(lines) {
                awaitEachGesture {
                    val down = awaitFirstDown(requireUnconsumed = false)
                    frozen = true
                    val held = offset
                    var moved = false
                    var up: Offset? = null
                    while (true) {
                        val event = awaitPointerEvent()
                        val change = event.changes.firstOrNull { it.id == down.id } ?: break
                        val d = change.position - down.position
                        if (abs(d.x) > slop || abs(d.y) > slop) moved = true
                        if (!change.pressed) { up = change.position; break }
                    }
                    // Only a TAP picks. A drag was the learner doing something
                    // else, and filling the field from it would be a surprise.
                    if (up != null && !moved) {
                        val index = floor((held + down.position.y) / rowPx).toInt()
                        onPick(lines[((index % lines.size) + lines.size) % lines.size])
                    }
                    frozen = false
                }
            },
    ) {
        // Twice through, so the seam is always off-screen.
        Column(Modifier.wrapContentHeight(Alignment.Top, unbounded = true)
            .offset { IntOffset(0, -offset.roundToInt()) }) {
            repeat(lines.size * 2) { i ->
                ReelRow(lines[i % lines.size], Modifier.height(rowHeight))
            }
        }
    }
}

@Composable
private fun ReelRow(line: String, modifier: Modifier) {
    Box(modifier.fillMaxWidth().padding(horizontal = 24.dp), contentAlignment = Alignment.Center) {
        Text(line, style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center, maxLines = 2, overflow = TextOverflow.Ellipsis)
    }
}
