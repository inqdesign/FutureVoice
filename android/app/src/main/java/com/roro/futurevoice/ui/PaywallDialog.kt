package com.roro.futurevoice.ui

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.SideEffect
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.compose.ui.window.DialogWindowProvider
import androidx.core.view.WindowCompat

/**
 * The plans as a full-screen layer OVER whatever raised them — iOS presents
 * `PaywallView` as a sheet from the screen on top, so the page underneath
 * (a scene mid-play, a situation just written, a word card) survives being
 * told no. Edge to edge, with the status bar's icons dark on the light page
 * as the activity's are.
 */
@Composable
fun PaywallDialog(onDismiss: () -> Unit) {
    Dialog(
        onDismissRequest = onDismiss,
        properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false),
    ) {
        DialogSystemBarsLikeActivity()
        PaywallScreen(onDismiss = onDismiss)
    }
}

/**
 * A full-screen `Dialog` is its own window, and its system bars default to
 * LIGHT icons — white clock and battery on the light page, invisible (seen on
 * the chapter decks). Call first inside the dialog's content: the bars' icons
 * go dark on a light theme, as the activity's are.
 */
@Composable
fun DialogSystemBarsLikeActivity() {
    val dark = isSystemInDarkTheme()
    val window = (LocalView.current.parent as? DialogWindowProvider)?.window
    SideEffect {
        window?.let {
            val ctl = WindowCompat.getInsetsController(it, it.decorView)
            ctl.isAppearanceLightStatusBars = !dark
            ctl.isAppearanceLightNavigationBars = !dark
        }
    }
}
