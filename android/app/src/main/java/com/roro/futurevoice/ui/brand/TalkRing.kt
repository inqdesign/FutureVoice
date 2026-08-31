package com.roro.futurevoice.ui.brand

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import kotlin.math.min

/**
 * The Talk home's goal ring, wrapping the Futureself surface
 * (`ConversationHome.talkRing`).
 *
 * The track is a WHISPER — primary at 1.5%, all but invisible: the full
 * circle is merely sensed against the background, never seen as a shape of
 * its own. The progress arc is one comet-style stroke whose tail fades in
 * from near-transparent at 12 o'clock, and the fade covers at most the REAR
 * of the arc so a short arc reads as a crisp little comet rather than a
 * smeared translucent pill.
 */
@Composable
fun TalkRing(
    progress: Float,
    mode: FutureselfMode,
    level: Float,
    theme: FutureselfTheme,
    accent: Color,
    modifier: Modifier = Modifier,
    diameter: Dp = 236.dp,
    strokeWidth: Dp = 14.dp,
    /** The call pill's height — pins the mosaic's cell size across sizes. */
    pixelHeight: Float = 64f,
) {
    val p = progress.coerceIn(0f, 1f)
    Box(modifier.size(diameter), contentAlignment = Alignment.Center) {
        Canvas(Modifier.size(diameter)) {
            val stroke = strokeWidth.toPx()
            val inset = stroke / 2f
            val d = min(size.width, size.height) - stroke
            val topLeft = Offset(inset, inset)
            val arcSize = Size(d, d)
            drawArc(color = Color.Black.copy(alpha = 0.015f), startAngle = 0f, sweepAngle = 360f,
                useCenter = false, topLeft = topLeft, size = arcSize,
                style = Stroke(width = stroke))
            if (p > 0.005f) {
                // The tail always fades, but only over the rear: at most 90°
                // of circle, never past the arc's halfway point.
                val fadeEnd = min(0.5f, 0.25f / maxOf(p, 0.001f))
                val brush = Brush.sweepGradient(
                    0f to accent.copy(alpha = 0.15f),
                    (fadeEnd * p) to accent,
                    1f to accent,
                    center = Offset(size.width / 2f, size.height / 2f),
                )
                drawArc(brush = brush, startAngle = -90f, sweepAngle = 360f * p,
                    useCenter = false, topLeft = topLeft, size = arcSize,
                    style = Stroke(width = stroke, cap = StrokeCap.Round))
            }
        }
        Futureself(
            mode = mode, level = level, theme = theme,
            virtualHeight = pixelHeight,
            modifier = Modifier.size(diameter - strokeWidth * 2 - 10.dp).clip(CircleShape),
        )
    }
}
