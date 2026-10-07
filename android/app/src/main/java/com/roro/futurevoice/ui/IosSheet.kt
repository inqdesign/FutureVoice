package com.roro.futurevoice.ui

import android.app.Activity
import androidx.compose.animation.core.animate
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.Orientation
import androidx.compose.foundation.gestures.draggable
import androidx.compose.foundation.gestures.rememberDraggableState
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.consumeWindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.nestedscroll.NestedScrollConnection
import androidx.compose.ui.input.nestedscroll.NestedScrollSource
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.Velocity
import androidx.compose.ui.unit.dp
import androidx.core.view.WindowCompat
import com.roro.futurevoice.ui.brand.AppSurfaces
import kotlinx.coroutines.launch
import kotlin.math.roundToInt

/**
 * iOS's page sheet at its large detent (`.sheet` with no detents — which is
 * how `MeTab` is presented from the Talk header).
 *
 * - It slides up from the bottom and stops just under the status bar, with
 *   large rounded top corners. No grabber: iOS draws none for a sheet with a
 *   single detent.
 * - The page it covers recedes behind it — shrinks from its top edge, takes
 *   rounded corners and dims a little over the black window — and comes back
 *   as the sheet leaves.
 * - Swipe down to dismiss follows the finger from anywhere in the sheet: on
 *   a part that doesn't scroll at once, inside a list once it is at its top
 *   (nested scroll). Let go past a third of the height, or with a flick, and
 *   it closes; otherwise it springs back. Pages pushed INSIDE the sheet keep
 *   their own edge swipe ([IosNavStack]); a swipe down closes the whole sheet
 *   from any of them, as iOS's does.
 * - Back (system back) is left to the content — the sheet's root page closes
 *   it with its own handler, a pushed page pops.
 *
 * [presented] is the caller's state. A sheet already up when this enters
 * composition (coming back from a page drawn over the tabs) is drawn up at
 * once, never animated in again.
 */
@Composable
fun IosSheetHost(
    presented: Boolean,
    onDismiss: () -> Unit,
    background: @Composable () -> Unit,
    sheet: @Composable () -> Unit,
) {
    /** 0 = fully up, 1 = fully down (gone). */
    var hide by rememberSaveable { mutableStateOf(if (presented) 0f else 1f) }
    var composed by rememberSaveable { mutableStateOf(presented) }
    var dragging by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val density = LocalDensity.current

    LaunchedEffect(presented) {
        if (presented) {
            composed = true
            // The sheet's first composition (a whole Settings page) can take
            // longer than the slide on a cold open; start the clock once it
            // has drawn, or the slide is spent before the first frame.
            if (hide > 0f) { withFrameNanos { }; withFrameNanos { } }
            if (hide > 0f) animate(hide, 0f, animationSpec = tween(SHEET_MS, easing = PushEasing)) { v, _ -> hide = v }
        } else if (composed) {
            animate(hide, 1f, animationSpec = tween(
                (SHEET_MS * (1f - hide)).roundToInt().coerceAtLeast(160), easing = PushEasing)) { v, _ -> hide = v }
            composed = false
        }
    }

    // While the sheet is up the status bar sits over the black window: light
    // icons, as iOS turns them.
    val view = LocalView.current
    val overBlack = composed && hide < 0.5f
    DisposableEffect(overBlack) {
        val window = (view.context as? Activity)?.window
        val ctl = window?.let { WindowCompat.getInsetsController(it, view) }
        val old = ctl?.isAppearanceLightStatusBars
        if (overBlack) ctl?.isAppearanceLightStatusBars = false
        onDispose { if (overBlack) old?.let { ctl.isAppearanceLightStatusBars = it } }
    }

    BoxWithConstraints(Modifier.fillMaxSize().background(if (composed) Color.Black else Color.Transparent)) {
        val fullH = constraints.maxHeight.toFloat()
        val statusPx = WindowInsets.statusBars.getTop(density).toFloat()
        val sheetTopPx = statusPx + with(density) { SheetGap.toPx() }
        val sheetH = (fullH - sheetTopPx).coerceAtLeast(1f)
        val q = if (composed) (1f - hide) else 0f

        fun settle(velocityPx: Float) {
            dragging = false
            val vDp = velocityPx / density.density
            val close = vDp > FLICK_DP_S || (vDp > -FLICK_DP_S && hide > 0.3f)
            if (close) onDismiss()
            else scope.launch {
                animate(hide, 0f, animationSpec = tween((SHEET_MS * hide).roundToInt().coerceAtLeast(160),
                    easing = PushEasing)) { v, _ -> hide = v }
            }
        }

        // The page underneath, receding.
        Box(
            Modifier.fillMaxSize().graphicsLayer {
                val s = 1f - RECEDE * q
                scaleX = s; scaleY = s
                transformOrigin = TransformOrigin(0.5f, 0f)
                translationY = statusPx * q
                if (q > 0f) {
                    clip = true
                    shape = RoundedCornerShape((CORNER.value * q).dp)
                }
            },
        ) {
            background()
            if (q > 0f) Box(Modifier.fillMaxSize().graphicsLayer { alpha = DIM * q }.background(Color.Black))
        }

        if (composed) {
            // Nothing under the sheet answers a touch while it is up.
            Box(Modifier.fillMaxSize().pointerInput(Unit) {
                awaitPointerEventScope { while (true) awaitPointerEvent().changes.forEach { it.consume() } }
            })
            val dragState = rememberDraggableState { delta ->
                dragging = true
                hide = (hide + delta / sheetH).coerceIn(0f, 1f)
            }
            val nested = remember(sheetH) {
                object : NestedScrollConnection {
                    override fun onPreScroll(available: Offset, source: NestedScrollSource): Offset {
                        // Pulled down and now going back up: the sheet takes
                        // it before the list does.
                        if (hide > 0f && available.y < 0f && source == NestedScrollSource.UserInput) {
                            val before = hide
                            hide = (hide + available.y / sheetH).coerceAtLeast(0f)
                            return Offset(0f, (hide - before) * sheetH)
                        }
                        return Offset.Zero
                    }
                    override fun onPostScroll(consumed: Offset, available: Offset, source: NestedScrollSource): Offset {
                        // The list is at its top and the finger keeps pulling.
                        if (available.y > 0f && source == NestedScrollSource.UserInput) {
                            dragging = true
                            hide = (hide + available.y / sheetH).coerceIn(0f, 1f)
                            return Offset(0f, available.y)
                        }
                        return Offset.Zero
                    }
                    override suspend fun onPreFling(available: Velocity): Velocity {
                        if (hide > 0f) { settle(available.y); return available }
                        return Velocity.Zero
                    }
                }
            }
            Box(
                Modifier
                    .offset { IntOffset(0, (sheetTopPx + sheetH * hide).roundToInt()) }
                    .fillMaxWidth()
                    .height(with(density) { sheetH.toDp() })
                    .clip(RoundedCornerShape(topStart = CORNER, topEnd = CORNER))
                    .background(AppSurfaces.ground)
                    // The sheet starts below the status bar: its pages must
                    // not pad for it again.
                    .consumeWindowInsets(WindowInsets.statusBars)
                    .nestedScroll(nested)
                    .draggable(dragState, Orientation.Vertical,
                        onDragStopped = { v -> if (dragging || hide > 0f) settle(v) }),
            ) {
                sheet()
            }
        }
    }
}

private const val SHEET_MS = 420
/** How far the covered page shrinks (iOS's card stack: ~8%). */
private const val RECEDE = 0.08f
private const val DIM = 0.12f
private const val FLICK_DP_S = 1000f
/** The sheet's top corners — iOS 26's large sheet, concentric with the screen. */
private val CORNER = 38.dp
/** Gap between the status bar and the sheet's top edge. */
private val SheetGap = 10.dp
