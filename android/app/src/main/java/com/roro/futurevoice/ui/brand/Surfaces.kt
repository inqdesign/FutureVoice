package com.roro.futurevoice.ui.brand

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

/**
 * The grouped-background PAIR iOS builds every screen on: a slightly recessed
 * ground with cards raised off it (`systemGroupedBackground` /
 * `secondarySystemGroupedBackground`).
 *
 * Material's tonal ramp runs in OPPOSITE directions in light and dark — a
 * higher container is darker in light and lighter in dark — so one token pair
 * cannot hold "card is lighter than ground" in both. The mode is read here
 * once, and every surface asks for these two instead of guessing a token.
 */
object AppSurfaces {
    /** The page ground — content sits ON this. */
    val ground: Color
        @Composable get() = if (isSystemInDarkTheme()) MaterialTheme.colorScheme.surface
        else MaterialTheme.colorScheme.surfaceContainer

    /** A card / row raised off the ground. */
    val card: Color
        @Composable get() = if (isSystemInDarkTheme()) MaterialTheme.colorScheme.surfaceContainerHigh
        else MaterialTheme.colorScheme.surface
}
