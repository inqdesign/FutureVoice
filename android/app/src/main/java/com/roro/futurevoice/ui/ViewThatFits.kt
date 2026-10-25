package com.roro.futurevoice.ui

import androidx.compose.foundation.layout.Box
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.SubcomposeLayout
import androidx.compose.ui.unit.Constraints

/**
 * SwiftUI's `ViewThatFits`: the first candidate whose ideal size fits the
 * offered space on [vertical] (or horizontal) axis, else the last one. A
 * candidate is only composed when the ones before it didn't fit.
 *
 * Vertically the layout takes the whole offered height (so a card's footer
 * can sit under it) and puts the chosen candidate at the top.
 */
@Composable
internal fun ViewThatFits(
    vertical: Boolean,
    modifier: Modifier = Modifier,
    candidates: List<@Composable () -> Unit>,
) {
    SubcomposeLayout(modifier) { constraints ->
        val ideal = if (vertical) constraints.copy(minHeight = 0, maxHeight = Constraints.Infinity)
            else constraints.copy(minWidth = 0, maxWidth = Constraints.Infinity)
        val limit = if (vertical) constraints.maxHeight else constraints.maxWidth
        var placeables = emptyList<androidx.compose.ui.layout.Placeable>()
        for (i in candidates.indices) {
            placeables = subcompose(i) { Box { candidates[i]() } }.map { it.measure(ideal) }
            val size = placeables.maxOfOrNull { if (vertical) it.height else it.width } ?: 0
            if (size <= limit) break
        }
        val w = if (vertical) constraints.maxWidth
            else (placeables.maxOfOrNull { it.width } ?: 0).coerceIn(constraints.minWidth, constraints.maxWidth)
        val contentH = placeables.maxOfOrNull { it.height } ?: 0
        val h = if (vertical && constraints.hasBoundedHeight) maxOf(constraints.minHeight, contentH.coerceAtMost(constraints.maxHeight))
            else contentH.coerceIn(constraints.minHeight, constraints.maxHeight)
        layout(w, h) { placeables.forEach { it.place(0, 0) } }
    }
}
