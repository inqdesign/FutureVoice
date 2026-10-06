package com.roro.futurevoice.ui

import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

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

/**
 * A full-screen step whose actions are PINNED to the bottom, iOS's
 * `VStack { Spacer(minLength: 0); content; Spacer(minLength: 0); buttons }`.
 *
 * The content scrolls and is centred while it fits; the action column never
 * shrinks and always clears the navigation bar (and the keyboard). Without
 * the scroll a non-scrolling column with weighted spacers measured the
 * buttons LAST, so on a short phone or a large font they got whatever height
 * was left — the daily-call CTA drew as a thin bar.
 */
@Composable
fun BottomActionLayout(
    modifier: Modifier = Modifier,
    contentPadding: androidx.compose.ui.unit.Dp = 28.dp,
    spacing: androidx.compose.ui.unit.Dp = 20.dp,
    content: @Composable ColumnScope.() -> Unit,
    actions: @Composable ColumnScope.() -> Unit,
) {
    Column(modifier.fillMaxSize().statusBarsPadding()) {
        BoxWithConstraints(Modifier.weight(1f).fillMaxWidth()) {
            val minH = maxHeight
            Column(
                Modifier.fillMaxWidth().verticalScroll(rememberScrollState())
                    .heightIn(min = minH).padding(horizontal = contentPadding, vertical = 16.dp),
                verticalArrangement = Arrangement.spacedBy(spacing, Alignment.CenterVertically),
                horizontalAlignment = Alignment.CenterHorizontally,
                content = content,
            )
        }
        Column(
            Modifier.fillMaxWidth().bottomBarInsets()
                .padding(start = contentPadding, end = contentPadding, top = 8.dp, bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            content = actions,
        )
    }
}

/**
 * The one body every bottom sheet's content goes in: scrolls when the sheet
 * is taller than the screen (a short phone, a 1.3 font), and keeps its foot
 * clear of the navigation bar and the keyboard. ModalBottomSheet caps itself
 * at the window height, and a non-scrolling body past that is simply CUT —
 * the age check's Continue sat under the nav bar that way.
 */
@Composable
fun Modifier.sheetBody(): Modifier =
    this.fillMaxWidth().verticalScroll(rememberScrollState()).bottomBarInsets()
