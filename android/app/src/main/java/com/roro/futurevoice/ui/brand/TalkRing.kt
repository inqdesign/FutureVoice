package com.roro.futurevoice.ui.brand

import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.boundsInWindow
import androidx.compose.ui.layout.onGloballyPositioned
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
    diameter: Dp = 280.dp,
    strokeWidth: Dp = 20.dp,
    /** The call pill's height — pins the mosaic's cell size across sizes. */
    pixelHeight: Float = 64f,
    /** 0 while the free-talk morph's proxy stands in for the surface. */
    surfaceAlpha: Float = 1f,
    /** Where the surface circle is, in window coordinates (the morph's start). */
    onSurfaceBounds: ((androidx.compose.ui.geometry.Rect) -> Unit)? = null,
    content: @Composable () -> Unit = {},
) {
    val p = progress.coerceIn(0f, 1f)
    val track = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.015f)
    Box(modifier.size(diameter), contentAlignment = Alignment.Center) {
        // The stroke is CENTRED on the circle that fills [diameter], as a
        // SwiftUI `Circle().stroke` is — half of it lies outside the frame,
        // so the drawn ring is `diameter + strokeWidth` across (300 on the
        // home) and its inner edge is exactly where the surface ends. An
        // inset stroke drew a 280 ring around a smaller surface with a strip
        // of page showing between them.
        Canvas(Modifier.size(diameter)) {
            val stroke = strokeWidth.toPx()
            val d = min(size.width, size.height)
            val topLeft = Offset((size.width - d) / 2f, (size.height - d) / 2f)
            val arcSize = Size(d, d)
            val c = Offset(size.width / 2f, size.height / 2f)
            drawArc(color = track, startAngle = 0f, sweepAngle = 360f,
                useCenter = false, topLeft = topLeft, size = arcSize,
                style = Stroke(width = stroke))
            if (p > 0.005f) {
                // iOS `talkRing`: below `solidBelow` the arc is plain accent (a
                // crisp dot); above it the last `fadeSpan` of the tail — at
                // most 60° of circle, never more than two fifths of the arc —
                // fades in from 40% accent. The gradient starts one cap-width
                // BEFORE 12 o'clock, so the tail's round cap is painted at the
                // floor colour rather than clamped to a solid block.
                val solidBelow = 0.12f
                val fadeSpan = min(60f / 360f, p * 0.4f)
                val fadeEnd = if (p > solidBelow) fadeSpan / maxOf(p, 0.001f) else 0f
                val capFrac = (stroke / 2f) / (2f * Math.PI.toFloat() * (d / 2f))
                val brush: Brush = if (fadeEnd <= 0f) androidx.compose.ui.graphics.SolidColor(accent) else {
                    val floor = accent.copy(alpha = 0.4f)
                    // iOS's angular range runs -cap … p; mapped onto a sweep
                    // gradient's 0 … 1 circle.
                    val solidAt = -capFrac + fadeEnd * (p + capFrac)
                    val atZero = androidx.compose.ui.graphics.lerp(floor, accent, capFrac / (solidAt + capFrac))
                    val headEnd = min(p + capFrac, 1f - capFrac)
                    Brush.sweepGradient(
                        *buildList {
                            add(0f to atZero)
                            add(solidAt to accent)
                            if (headEnd > solidAt) add(headEnd to accent)
                            // The wrap just before 12 is the tail cap's own
                            // floor colour (outside the range iOS clamps to it).
                            add((1f - capFrac) to floor)
                            add(1f to atZero)
                        }.toTypedArray(),
                        center = c,
                    )
                }
                // A sweep gradient starts at 3 o'clock; rotating the CANVAS
                // carries both the arc's 0° and the gradient's origin to 12.
                rotate(-90f, pivot = c) {
                    drawArc(brush = brush, startAngle = 0f, sweepAngle = 360f * p,
                        useCenter = false, topLeft = topLeft, size = arcSize,
                        style = Stroke(width = stroke, cap = StrokeCap.Round))
                    // At full progress the circle closes and its caps meet in
                    // a butt seam at 12; iOS re-draws the last sliver in solid
                    // accent with a round cap so the head pokes over the tail.
                    if (p > 0.97f) {
                        val from = maxOf(p - 0.02f, 0f)
                        drawArc(color = accent, startAngle = 360f * from,
                            sweepAngle = 360f * (p - from), useCenter = false,
                            topLeft = topLeft, size = arcSize,
                            style = Stroke(width = stroke, cap = StrokeCap.Round))
                    }
                }
            }
        }
        Box(
            Modifier
                .size(diameter - strokeWidth)
                .then(if (onSurfaceBounds != null) Modifier.onGloballyPositioned {
                    onSurfaceBounds(it.boundsInWindow()) } else Modifier)
                .graphicsLayer { alpha = surfaceAlpha }
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
