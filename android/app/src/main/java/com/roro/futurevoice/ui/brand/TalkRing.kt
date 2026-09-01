package com.roro.futurevoice.ui.brand

import androidx.compose.foundation.Canvas
import androidx.compose.material3.MaterialTheme
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.fillMaxSize
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
import androidx.compose.ui.graphics.drawscope.rotate
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
 *
 * [content] is drawn OVER the surface, inside the circle — on the home that
 * is the call's label and the day's minutes, which belong in the ring rather
 * than under it (iOS `talkRing`).
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
    content: @Composable () -> Unit = {},
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
                val tail = accent.copy(alpha = 0.15f)
                val brush = Brush.sweepGradient(
                    0f to tail,
                    (fadeEnd * p) to accent,
                    // The ROUND CAP at the arc's start overhangs BACKWARDS,
                    // past 0° — which in a sweep gradient wraps to position
                    // 1.0. With full accent parked there, that overhang came
                    // out as a solid dark half-disc sitting on the faded
                    // tail. The wrap point has to be the tail's own colour.
                    // The head cap overhangs the other way, just past `p`,
                    // where the ramp is still essentially full accent.
                    1f to tail,
                    center = Offset(size.width / 2f, size.height / 2f),
                )
                // A sweep gradient always starts at 3 o'clock; the arc has to
                // start at 12. Left in phase the faded tail landed a quarter
                // turn from the arc's start, so the ring read as a solid head
                // with a washed-out stretch through its middle.
                //
                // Rotating the CANVAS by -90° moves both together — so the
                // arc is drawn from 0° (which the rotation carries to 12
                // o'clock on screen), and the gradient's own origin lands
                // there with it. Drawing at -90° INSIDE the rotation would
                // start the arc at 9 o'clock, which is the same bug turned
                // the other way.
                rotate(-90f, pivot = Offset(size.width / 2f, size.height / 2f)) {
                    drawArc(brush = brush, startAngle = 0f, sweepAngle = 360f * p,
                        useCenter = false, topLeft = topLeft, size = arcSize,
                        style = Stroke(width = stroke, cap = StrokeCap.Round))
                }
            }
        }
        Box(
            Modifier
                .size(diameter - strokeWidth * 2 - 4.dp)
                .clip(CircleShape)
                // A hairline rim, so the circle has an edge rather than
                // dissolving into the page.
                .border(0.5.dp, MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.4f),
                    CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            Futureself(mode = mode, level = level, theme = theme,
                virtualHeight = pixelHeight, modifier = Modifier.fillMaxSize())
            // An inner vignette hugging the rim, so the circle reads as a
            // curved surface rather than a flat disc.
            //
            // NO page-colour wash here, unlike iOS. There it exists because
            // the Metal shader's base runs BRIGHTER than the grouped
            // background; the AGSL port already sits at page brightness, so
            // washing it again only turned the mosaic to mud. Tight spread
            // too — a vignette that reaches inward reads as a hole punched in
            // the page instead of a sphere.
            val dark = isSystemInDarkTheme()
            Canvas(Modifier.fillMaxSize()) {
                val r = size.minDimension / 2f
                drawCircle(
                    brush = Brush.radialGradient(
                        0.86f to Color.Transparent,
                        1f to Color.Black.copy(alpha = if (dark) 0.38f else 0.10f),
                        center = center,
                        radius = r,
                    ),
                    radius = r,
                )
            }
            content()
        }
    }
}
