package com.roro.futurevoice.ui

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
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
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.onSizeChanged
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
        var stripPx by remember { mutableIntStateOf(0) }
        val density = LocalDensity.current
        val gapPx = with(density) { 8.dp.roundToPx() }
        // 28 dp a second, like iOS: slow enough to read a chip as it passes.
        val speedPx = with(density) { 28.dp.toPx() }
        val periodMs = if (stripPx > 0) ((stripPx + gapPx) / speedPx * 1000).toInt() else 10_000
        val transition = rememberInfiniteTransition(label = "freeFeatures")
        val phase by transition.animateFloat(
            initialValue = 0f, targetValue = 1f,
            animationSpec = infiniteRepeatable(tween(periodMs, easing = LinearEasing), RepeatMode.Restart),
            label = "shift")
        Box(Modifier.fillMaxWidth().clipToBounds()) {
            Row(
                Modifier.wrapContentWidth(Alignment.Start, unbounded = true)
                    .graphicsLayer { translationX = -phase * (stripPx + gapPx) },
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
