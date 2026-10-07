package com.roro.futurevoice.ui

import android.content.res.Configuration
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.roro.futurevoice.data.AppAppearance

/**
 * Wears the learner's Appearance pick (iOS `.preferredColorScheme`): System
 * passes the phone's mode through; Light / Dark rewrite the night bits of the
 * configuration every composable reads, so `isSystemInDarkTheme()` — and
 * with it the colour scheme, the surfaces and the Futureself palettes —
 * follows without a single screen knowing. [onDark] lets the host re-tint
 * the system bars.
 */
@Composable
fun AppearanceHost(onDark: (Boolean) -> Unit = {}, content: @Composable () -> Unit) {
    val context = LocalContext.current
    val mode by AppAppearance.live(context).collectAsStateWithLifecycle()
    val base = LocalConfiguration.current
    val systemDark = (base.uiMode and Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES
    val dark = when (mode ?: AppAppearance.SYSTEM) {
        AppAppearance.SYSTEM -> systemDark
        AppAppearance.LIGHT -> false
        AppAppearance.DARK -> true
    }
    androidx.compose.runtime.LaunchedEffect(dark) { onDark(dark) }
    // ALWAYS the same provider, whatever the mode: branching between a bare
    // `content()` and a provider changes the composition's shape, which
    // throws away every remembered state under it — flipping the switch
    // closed Settings and reset the tabs.
    val config = remember(base, dark, systemDark) {
        if (dark == systemDark) base else Configuration(base).apply {
            uiMode = (uiMode and Configuration.UI_MODE_NIGHT_MASK.inv()) or
                (if (dark) Configuration.UI_MODE_NIGHT_YES else Configuration.UI_MODE_NIGHT_NO)
        }
    }
    CompositionLocalProvider(LocalConfiguration provides config) { content() }
}
