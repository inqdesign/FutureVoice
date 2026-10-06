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
        val dark = isSystemInDarkTheme()
        val window = (LocalView.current.parent as? DialogWindowProvider)?.window
        SideEffect {
            window?.let {
                WindowCompat.getInsetsController(it, it.decorView).isAppearanceLightStatusBars = !dark
            }
        }
        PaywallScreen(onDismiss = onDismiss)
    }
}
