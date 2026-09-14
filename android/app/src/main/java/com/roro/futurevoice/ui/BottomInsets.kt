package com.roro.futurevoice.ui

import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier

/**
 * The one rule for anything PINNED to the bottom of the screen.
 *
 * The app draws edge to edge (`enableEdgeToEdge` in `MainActivity`), so the
 * system draws its navigation bar OVER our content and nothing is padded for
 * us. A `Scaffold` passes that inset down to its content — but not to a
 * `bottomBar`, which is expected to handle its own. Three setup screens
 * didn't, and their Back/Next sat under the gesture pill with half the label
 * cut off.
 *
 * `safeDrawing` and not `navigationBarsPadding()`: when the keyboard is up it
 * covers the navigation bar too, and these bars sit under screens with text
 * fields. `safeDrawing` takes the LARGER of the two, so the bar rides the
 * keyboard without being pushed twice. `adjustResize` in the manifest does
 * nothing once the window stops fitting system windows — this is what
 * replaces it.
 */
@Composable
fun Modifier.bottomBarInsets(): Modifier =
    this.windowInsetsPadding(WindowInsets.safeDrawing.only(WindowInsetsSides.Bottom))
