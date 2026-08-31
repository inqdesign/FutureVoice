package com.roro.futurevoice.ui.brand

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.unit.dp

/**
 * The effort strip: one column per day, drawn straight on a Canvas.
 *
 * No chart library. These are bars with a rule line on them — the whole
 * drawing is twenty lines — and pulling in a charting dependency to get it
 * would hand the app's most-looked-at picture to someone else's idea of what
 * a bar should look like.
 */
object EffortCharts {

    /** One day's stack, in the order the segments are drawn (bottom up). */
    data class DayBar(val label: String, val segments: List<Pair<Color, Float>>) {
        val total: Float get() = segments.sumOf { it.second.toDouble() }.toFloat()
    }

    /**
     * @param goal a dashed rule at this value — the daily goal. Null draws none.
     *   It is a LINE and never a cap: a day above it still draws above it.
     */
    @Composable
    fun Bars(
        days: List<DayBar>,
        goal: Float? = null,
        modifier: Modifier = Modifier,
        height: androidx.compose.ui.unit.Dp = 120.dp,
    ) {
        if (days.isEmpty()) return
        val axis = MaterialTheme.colorScheme.onSurfaceVariant
        // The scale includes the goal, so a week under target still shows the
        // line — a rule drawn off the top of the panel says nothing.
        val peak = maxOf(days.maxOf { it.total }, goal ?: 0f, 1f)
        Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Canvas(Modifier.fillMaxWidth().height(height)) {
                val slot = size.width / days.size
                val barWidth = slot * 0.62f
                val gap = (slot - barWidth) / 2
                val radius = androidx.compose.ui.geometry.CornerRadius(3.dp.toPx())
                days.forEachIndexed { i, day ->
                    var y = size.height
                    // Bottom up, and only the TOP segment is rounded — a
                    // rounded cap inside a stack draws a notch between two
                    // colours that reads as a gap in the day.
                    val drawn = day.segments.filter { it.second > 0f }
                    drawn.forEachIndexed { j, (color, value) ->
                        val h = (value / peak) * size.height
                        val top = y - h
                        if (j == drawn.lastIndex) {
                            drawRoundRect(color, topLeft = Offset(i * slot + gap, top),
                                size = Size(barWidth, h), cornerRadius = radius)
                        } else {
                            drawRect(color, topLeft = Offset(i * slot + gap, top),
                                size = Size(barWidth, h))
                        }
                        y = top
                    }
                }
                if (goal != null && goal > 0f) {
                    val y = size.height - (goal / peak) * size.height
                    drawLine(axis.copy(alpha = 0.5f), Offset(0f, y), Offset(size.width, y),
                        strokeWidth = 1.dp.toPx(),
                        pathEffect = PathEffect.dashPathEffect(
                            floatArrayOf(6.dp.toPx(), 4.dp.toPx())))
                }
            }
            // Every third day is labelled: fourteen numbers in a row is a
            // smear, and the shape is what the strip is for.
            Row(Modifier.fillMaxWidth()) {
                days.forEachIndexed { i, d ->
                    Text(
                        if (i % 3 == 0) d.label else "",
                        style = MaterialTheme.typography.labelSmall,
                        color = axis,
                        modifier = Modifier.weight(1f),
                    )
                }
            }
        }
    }

    /** The key under a stacked strip. Without it a colour means nothing. */
    @Composable
    fun Legend(entries: List<Pair<String, Color>>, modifier: Modifier = Modifier) {
        Row(modifier, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            entries.forEach { (label, color) ->
                Row(verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    Canvas(Modifier.size(8.dp)) { drawRect(color) }
                    Text(label, style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
    }
}
