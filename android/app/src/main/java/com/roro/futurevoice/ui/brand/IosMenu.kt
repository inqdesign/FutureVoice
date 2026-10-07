package com.roro.futurevoice.ui.brand

import androidx.compose.animation.core.MutableTransitionState
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.rememberTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntRect
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Popup
import androidx.compose.ui.window.PopupPositionProvider
import androidx.compose.ui.window.PopupProperties

/**
 * iOS's pull-down menu — what `Picker` with `.menu` style and `Menu` open —
 * as ONE component, so every menu in the app opens from the same place and
 * wears the same surface.
 *
 * Material's `DropdownMenu` was used per call site, anchored to whatever Box
 * happened to wrap it: on a whole-row Box it opened at the row's LEFT edge,
 * on the trailing value it opened at the RIGHT, so two pickers on the same
 * Settings page popped from opposite sides (reported 2026-10-07). iOS has one
 * rule, read off the iOS 26 simulator: the menu's TRAILING edge lines up with
 * the control that opened it, and it grows UPWARD from that control's bottom
 * edge, covering it — unless there is no room above, when it hangs down from
 * the control's top instead. It is never centred and never left-aligned.
 *
 * The surface (measured @3x): ~250 pt wide, 44 pt rows, a 24 pt continuous
 * radius, a soft wide shadow and NO dimming behind. A picker's current item
 * carries the checkmark on the LEADING side, in ink, and every label is
 * indented past that column so the list doesn't shift when the tick moves.
 *
 * Place [IosMenu] inside a `Box` that wraps the ANCHOR — the trailing value
 * of a picker row, never the whole row — exactly as `DropdownMenu` is placed.
 */
@Composable
fun IosMenu(
    expanded: Boolean,
    onDismissRequest: () -> Unit,
    modifier: Modifier = Modifier,
    content: @Composable ColumnScope.() -> Unit,
) {
    val state = remember { MutableTransitionState(false) }
    state.targetState = expanded
    if (!state.currentState && !state.targetState) return

    val density = LocalDensity.current
    var growsUp by remember { mutableStateOf(true) }
    val provider = remember(density) {
        IosMenuPositionProvider(density) { growsUp = it }
    }
    Popup(
        popupPositionProvider = provider,
        onDismissRequest = onDismissRequest,
        properties = PopupProperties(focusable = true),
    ) {
        val transition = rememberTransition(state, label = "iosMenu")
        val scale by transition.animateFloat({ tween(if (state.targetState) 220 else 140) },
            label = "scale") { if (it) 1f else 0.6f }
        val alpha by transition.animateFloat({ tween(if (state.targetState) 160 else 120) },
            label = "alpha") { if (it) 1f else 0f }
        val dark = isSystemInDarkTheme()
        // iOS 26 menus are a near-opaque glass: white in light, a lifted
        // grey in dark. Opaque here — a blur under a Popup isn't available
        // to Compose, and a translucent fill without one reads as a smudge.
        val fill = if (dark) Color(0xFF252527) else Color(0xFFFCFCFD)
        Column(
            modifier
                .graphicsLayer {
                    scaleX = scale; scaleY = scale; this.alpha = alpha
                    // Morphs out of the control it came from: trailing edge,
                    // bottom when it grows up, top when it hangs down.
                    transformOrigin = TransformOrigin(1f, if (growsUp) 1f else 0f)
                }
                .padding(12.dp) // room for the shadow inside the popup window
                .shadow(28.dp, ContinuousShape(IosMenuRadius), clip = false,
                    ambientColor = Color.Black.copy(alpha = 0.18f),
                    spotColor = Color.Black.copy(alpha = 0.22f))
                .background(fill, ContinuousShape(IosMenuRadius))
                .widthIn(min = 250.dp, max = 300.dp)
                .width(IntrinsicSize.Max)
                .heightIn(max = 520.dp)
                .verticalScroll(rememberScrollState())
                .padding(vertical = 6.dp),
            content = content,
        )
    }
}

/** The corner the menu surface is cut with. */
val IosMenuRadius = 24.dp

/**
 * One item. [checked] draws the picker's leading tick; [icon] sits TRAILING,
 * the way iOS lays out a `Label` inside a `Menu`. [destructive] reads red.
 */
@Composable
fun IosMenuItem(
    text: String,
    onClick: () -> Unit,
    checked: Boolean = false,
    icon: ImageVector? = null,
    destructive: Boolean = false,
    enabled: Boolean = true,
    /** Picker menus reserve the tick column on every row; a plain action
     *  menu (no item can be checked) doesn't. */
    reserveCheck: Boolean = true,
) {
    val ink = when {
        destructive -> MaterialTheme.colorScheme.error
        else -> MaterialTheme.colorScheme.onSurface
    }.copy(alpha = if (enabled) 1f else 0.35f)
    Row(
        Modifier.fillMaxWidth()
            .then(if (enabled) Modifier.clickable(onClick = onClick) else Modifier)
            .heightIn(min = 44.dp)
            .padding(start = if (reserveCheck) 14.dp else 20.dp, end = 20.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (reserveCheck) {
            Box(Modifier.width(26.dp), contentAlignment = Alignment.CenterStart) {
                if (checked) Icon(Icons.Filled.Check, contentDescription = null,
                    modifier = Modifier.size(17.dp), tint = ink)
            }
        }
        Text(text, Modifier.weight(1f, fill = false).padding(vertical = 10.dp),
            style = MaterialTheme.typography.bodyLarge, color = ink,
            maxLines = 2, overflow = TextOverflow.Ellipsis)
        if (icon != null) {
            Spacer(Modifier.weight(1f).widthIn(min = 16.dp))
            Icon(icon, contentDescription = null, modifier = Modifier.size(19.dp), tint = ink)
        }
    }
}

/** A section break inside a menu — iOS draws a thicker grey band. */
@Composable
fun IosMenuDivider() {
    HorizontalDivider(Modifier.padding(vertical = 4.dp), thickness = 6.dp,
        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.05f))
}

/** A small grey caption over a group of items (iOS `Section("…")` in a Menu). */
@Composable
fun IosMenuHeader(text: String) {
    Text(text, Modifier.padding(start = 20.dp, end = 20.dp, top = 8.dp, bottom = 4.dp),
        style = MaterialTheme.typography.bodySmall, fontWeight = FontWeight.Normal,
        color = MaterialTheme.colorScheme.onSurfaceVariant)
}

/**
 * The whole `Picker(.menu)`: its options, the current one ticked, a pick
 * closes the menu. Place inside the Box wrapping the trailing value.
 */
@Composable
fun <T> IosPickerMenu(
    expanded: Boolean,
    onDismissRequest: () -> Unit,
    options: List<Pair<T, String>>,
    selected: T?,
    onPick: (T) -> Unit,
) {
    IosMenu(expanded, onDismissRequest) {
        options.forEach { (value, label) ->
            IosMenuItem(label, checked = value == selected,
                onClick = { onDismissRequest(); onPick(value) })
        }
    }
}

/**
 * Trailing edge on the anchor's trailing edge; bottom on the anchor's
 * bottom (grows up, covering it) when the menu fits above, else top on the
 * anchor's top (hangs down). Always kept inside the window with a margin.
 */
private class IosMenuPositionProvider(
    private val density: Density,
    private val onDirection: (growsUp: Boolean) -> Unit,
) : PopupPositionProvider {
    override fun calculatePosition(
        anchorBounds: IntRect,
        windowSize: IntSize,
        layoutDirection: LayoutDirection,
        popupContentSize: IntSize,
    ): IntOffset {
        val shadowPad = with(density) { 12.dp.roundToPx() }
        val margin = with(density) { 8.dp.roundToPx() }
        // Flush with the anchor's trailing edge (the value's chevron), as iOS.
        val nudge = 0
        val right = if (layoutDirection == LayoutDirection.Ltr) anchorBounds.right + nudge + shadowPad
            else anchorBounds.left - nudge - shadowPad + popupContentSize.width
        val x = (right - popupContentSize.width)
            .coerceIn(margin - shadowPad, windowSize.width - popupContentSize.width - margin + shadowPad)
        val topLimit = with(density) { 40.dp.roundToPx() }
        val upY = anchorBounds.bottom + shadowPad - popupContentSize.height
        val growsUp = upY >= topLimit - shadowPad
        onDirection(growsUp)
        val y = if (growsUp) upY else (anchorBounds.top - shadowPad)
            .coerceAtMost(windowSize.height - popupContentSize.height - margin + shadowPad)
        return IntOffset(x, y)
    }
}
