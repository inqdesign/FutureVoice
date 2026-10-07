package com.roro.futurevoice.ui.brand

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.size
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/**
 * iOS's `ProgressView()` — the grey eight-spoke wheel, not Material's blue
 * arc. The spokes don't turn smoothly: the bright one steps round once a
 * second and the rest trail off behind it, as UIActivityIndicatorView does.
 */
@Composable
fun IosActivityIndicator(
    modifier: Modifier = Modifier,
    size: Dp = 20.dp,
    color: Color = MaterialTheme.colorScheme.onSurfaceVariant,
) {
    val spokes = 8
    val step by rememberInfiniteTransition(label = "iosSpinner").animateFloat(
        initialValue = 0f, targetValue = spokes.toFloat(),
        animationSpec = infiniteRepeatable(tween(1000, easing = LinearEasing), RepeatMode.Restart),
        label = "iosSpinnerStep",
    )
    val head = step.toInt() % spokes
    Canvas(modifier.size(size)) {
        val r = this.size.minDimension / 2
        val width = r * 0.24f
        for (i in 0 until spokes) {
            // How far behind the bright spoke this one is: 0 = brightest.
            val behind = (head - i + spokes) % spokes
            val alpha = 1f - behind * (0.75f / (spokes - 1))
            rotate(degrees = i * 360f / spokes, pivot = center) {
                drawLine(color.copy(alpha = alpha),
                    start = Offset(center.x, center.y - r * 0.45f),
                    end = Offset(center.x, center.y - r + width / 2),
                    strokeWidth = width, cap = StrokeCap.Round)
            }
        }
    }
}
