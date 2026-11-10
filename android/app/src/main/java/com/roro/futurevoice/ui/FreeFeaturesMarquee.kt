package com.roro.futurevoice.ui

import android.provider.Settings
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.wrapContentWidth
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Abc
import androidx.compose.material.icons.filled.Assessment
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Checklist
import androidx.compose.material.icons.filled.FormatQuote
import androidx.compose.material.icons.filled.GraphicEq
import androidx.compose.material.icons.filled.Headphones
import androidx.compose.material.icons.filled.Layers
import androidx.compose.material.icons.filled.MenuBook
import androidx.compose.material.icons.filled.PlayCircle
import androidx.compose.material.icons.filled.RecordVoiceOver
import androidx.compose.material.icons.filled.Replay
import androidx.compose.material.icons.filled.ViewAgenda
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.roro.futurevoice.R

/**
 * Everything a plan does NOT meter, rolling past under the paywall's
 * subtitle (iOS `FreeFeaturesMarquee`, 2026-11-03, founder: "show how much
 * is free"). Each chip is an icon and the feature's own name. A scene and a
 * speech voiceover are paid out of the talk minutes and are left out on
 * purpose; their price is said on their own buttons.
 */
@Composable
fun FreeFeaturesMarquee(modifier: Modifier = Modifier) {
    val items: List<Pair<ImageVector, Int>> = listOf(
        Icons.Filled.MenuBook to R.string.review_book,
        Icons.Filled.Abc to R.string.words,
        Icons.Filled.FormatQuote to R.string.expressions,
        Icons.Filled.ViewAgenda to R.string.sentences,
        Icons.Filled.GraphicEq to R.string.shadowing,
        Icons.Filled.Replay to R.string.say_it_again,
        Icons.Filled.PlayCircle to R.string.replay,
        Icons.Filled.Layers to R.string.drills,
        Icons.Filled.Checklist to R.string.weekly_test,
        Icons.Filled.Assessment to R.string.your_week,
        Icons.Filled.RecordVoiceOver to R.string.pronunciation,
        Icons.Filled.Headphones to R.string.listening,
    )
    Column(modifier, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.Top) {
            Icon(Icons.Filled.CheckCircle, contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.size(18.dp).padding(top = 2.dp))
            Text(stringResource(R.string.paywall_unlimited_every_plan),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        // Animations switched off on the phone: every chip, in rows, still
        // (iOS `FlowChips` under Reduce Motion).
        val context = LocalContext.current
        val still = remember {
            runCatching {
                Settings.Global.getFloat(context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f
            }.getOrDefault(false)
        }
        if (still) {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                items.chunked(4).forEach { row ->
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) { row.forEach { Chip(it.first, it.second) } }
                }
            }
            return@Column
        }
        var stripPx by remember { mutableIntStateOf(0) }
        val density = LocalDensity.current
        val gapPx = with(density) { 8.dp.roundToPx() }
        // 28 dp a second, like iOS: slow enough to read a chip as it passes.
        // Moved by the frame clock, as iOS moves it by elapsed time. An
        // infinite transition keeps the duration it started with (a changed
        // spec is ignored), so the whole strip crossed in the 10 s it was
        // given before the strip was measured: four to five times too fast.
        val speedPx = with(density) { 28.dp.toPx() }
        var shift by remember { mutableFloatStateOf(0f) }
        LaunchedEffect(stripPx) {
            if (stripPx <= 0) return@LaunchedEffect
            val loop = (stripPx + gapPx).toFloat()
            var last = 0L
            while (true) {
                withFrameNanos { now ->
                    if (last != 0L) shift = (shift + speedPx * (now - last) / 1e9f) % loop
                    last = now
                }
            }
        }
        Box(
            Modifier.fillMaxWidth().clipToBounds()
                // The chips fade in and out at the edges, like iOS.
                .graphicsLayer { compositingStrategy = CompositingStrategy.Offscreen }
                .drawWithContent {
                    drawContent()
                    drawRect(
                        Brush.horizontalGradient(
                            0f to Color.Transparent, 0.05f to Color.Black,
                            0.95f to Color.Black, 1f to Color.Transparent),
                        blendMode = BlendMode.DstIn)
                },
        ) {
            Row(
                Modifier.wrapContentWidth(Alignment.Start, unbounded = true)
                    .graphicsLayer { translationX = -shift },
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Row(Modifier.onSizeChanged { stripPx = it.width },
                    horizontalArrangement = Arrangement.spacedBy(8.dp)) { items.forEach { Chip(it.first, it.second) } }
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) { items.forEach { Chip(it.first, it.second) } }
            }
        }
    }
}

@Composable
private fun Chip(icon: ImageVector, label: Int) {
    Row(
        Modifier.background(MaterialTheme.colorScheme.onSurface.copy(alpha = 0.07f), CircleShape)
            .padding(horizontal = 10.dp, vertical = 6.dp),
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(icon, contentDescription = null, modifier = Modifier.size(14.dp))
        Text(stringResource(label), style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.Medium, maxLines = 1)
    }
}
