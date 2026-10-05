package com.roro.futurevoice.ui

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch
import kotlin.math.roundToInt

/** One button behind a row — iOS `swipeActions` `Button`. */
class IosSwipeAction(
    val icon: ImageVector,
    val label: String,
    val color: Color,
    val onClick: () -> Unit,
)

/**
 * iOS `.swipeActions(edge: .trailing)` on a list row: swiping left reveals
 * the buttons, the FIRST declared one outermost (at the right edge), each
 * the full height of the row. A tap on a button runs it; a FULL swipe (past
 * ~60% of the row, `allowsFullSwipe` — iOS's default) runs the first one, the
 * way a long swipe deletes on iOS. A tap on the row while it is open closes
 * it. No actions = no swipe.
 */
@Composable
fun IosSwipeActions(
    trailing: List<IosSwipeAction>,
    background: Color,
    modifier: Modifier = Modifier,
    allowsFullSwipe: Boolean = true,
    content: @Composable () -> Unit,
) {
    if (trailing.isEmpty()) { Box(modifier) { content() }; return }
    val density = LocalDensity.current
    val scope = rememberCoroutineScope()
    val offset = remember { Animatable(0f) }
    BoxWithConstraints(modifier.clipToBounds()) {
        val rowWidth = constraints.maxWidth.toFloat()
        val buttonPx = with(density) { 74.dp.toPx() }
        val reveal = buttonPx * trailing.size
        fun settle(target: Float) = scope.launch { offset.animateTo(target, tween(220)) }
        fun close() = settle(0f)

        // The buttons, under the row, filling what the row has uncovered.
        val shown = -offset.value
        if (shown > 0f) {
            Row(Modifier.matchParentSize(), horizontalArrangement = androidx.compose.foundation.layout.Arrangement.End) {
                // Past the full reveal the outermost (first) button stretches.
                val extra = (shown - reveal).coerceAtLeast(0f)
                val scale = (shown / reveal).coerceAtMost(1f)
                trailing.asReversed().forEachIndexed { i, action ->
                    val first = i == trailing.size - 1
                    val w = buttonPx * scale + if (first) extra else 0f
                    Box(
                        Modifier.width(with(density) { w.toDp() }).fillMaxHeight()
                            .background(action.color)
                            .clickable { close(); action.onClick() },
                        contentAlignment = Alignment.Center,
                    ) {
                        Icon(action.icon, contentDescription = action.label, tint = Color.White,
                            modifier = Modifier.size(22.dp))
                    }
                }
            }
        }
        Box(
            Modifier.offset { IntOffset(offset.value.roundToInt(), 0) }
                .background(background)
                .pointerInput(trailing.size, rowWidth) {
                    detectHorizontalDragGestures(
                        onHorizontalDrag = { change, delta ->
                            change.consume()
                            scope.launch { offset.snapTo((offset.value + delta).coerceIn(-rowWidth, 0f)) }
                        },
                        onDragEnd = {
                            val pulled = -offset.value
                            when {
                                allowsFullSwipe && pulled > rowWidth * 0.6f -> scope.launch {
                                    offset.animateTo(-rowWidth, tween(180))
                                    trailing.first().onClick()
                                    offset.snapTo(0f)
                                }
                                pulled > reveal / 2 -> settle(-reveal)
                                else -> close()
                            }
                        },
                        onDragCancel = { close() },
                    )
                },
        ) {
            content()
            // Open: the first tap on the row only closes it, as on iOS.
            if (offset.value != 0f) {
                Box(Modifier.matchParentSize().clickable(
                    interactionSource = remember { androidx.compose.foundation.interaction.MutableInteractionSource() },
                    indication = null) { close() })
            }
        }
    }
}
