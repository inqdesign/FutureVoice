package com.roro.futurevoice.ui

import android.os.Build
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.platform.LocalContext
import com.roro.futurevoice.ui.brand.FutureselfTheme
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.graphics.compositeOver
import androidx.compose.ui.graphics.Color

/**
 * System colors, ONE accent — the Android reading of the iOS rule.
 *
 * Material You dynamic colour was taking the accent from the phone's
 * WALLPAPER, so the palette the learner picks in Appearance never reached the
 * screen: the drill card, the ring and every tinted control wore whatever hue
 * the home screen happened to have. iOS sets the picked palette as the app's
 * accent and lets everything inherit it; this does the same, and leaves the
 * greys to the platform.
 */
@Composable
fun FutureVoiceTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit,
) {
    val context = LocalContext.current
    val base = when {
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.S ->
            if (darkTheme) dynamicDarkColorScheme(context) else dynamicLightColorScheme(context)

        darkTheme -> darkColorScheme()
        else -> lightColorScheme()
    }
    val accent = FutureselfTheme.stored(context).tint()
    // White on the deep hues, black on the pale ones — MONO is near-black in
    // light and near-white in dark, so this cannot be a constant.
    val onAccent = if (accent.luminance() > 0.5f) Color.Black else Color.White
    val colors = base.copy(
        primary = accent,
        onPrimary = onAccent,
        // The quiet half of the accent: a chip's selected fill, a tinted row.
        primaryContainer = accent.copy(alpha = 0.16f).compositeOver(base.surface),
        onPrimaryContainer = accent,
    )
    MaterialTheme(colorScheme = colors, content = content)
}
