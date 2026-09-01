package com.roro.futurevoice.ui.brand

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.TopAppBarColors
import androidx.compose.material3.TopAppBarDefaults
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
@OptIn(ExperimentalMaterial3Api::class)
object AppSurfaces {
    /** The page ground — content sits ON this. */
    val ground: Color
        @Composable get() = if (isSystemInDarkTheme()) MaterialTheme.colorScheme.surface
        else MaterialTheme.colorScheme.surfaceContainer

    /** A card / row raised off the ground. */
    val card: Color
        @Composable get() = if (isSystemInDarkTheme()) MaterialTheme.colorScheme.surfaceContainerHigh
        else MaterialTheme.colorScheme.surface

    /**
     * The page header, on the SAME ground as the content under it.
     *
     * Material's default gives a top bar its own container colour, which
     * draws a horizontal seam across every screen at the exact height the
     * bar ends — a line that means nothing, since the header and the page
     * are one surface. One page, one ground.
     *
     * Every `TopAppBar` in the app takes this. Restyling the header has to
     * stay a single-file change; a bar that sets its own colours locally is
     * how the seam comes back on one screen.
     */
    @Composable
    fun topBarColors(): TopAppBarColors = TopAppBarDefaults.topAppBarColors(
        containerColor = ground,
        scrolledContainerColor = ground,
    )
}
