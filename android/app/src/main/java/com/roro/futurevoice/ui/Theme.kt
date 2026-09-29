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
    // The NEUTRALS are iOS's system greys, fixed. Material You took them
    // from the wallpaper too, so on a grey-ish wallpaper a chip's fill
    // (`surfaceVariant`) came out the same tone as the page and every capsule
    // in a header vanished — the streak chip, the avatar's disc. iOS draws
    // those on `secondarySystemFill` over `systemGroupedBackground`, which is
    // the same grey on every phone. (`AppSurfaces`: ground = surfaceContainer
    // in light / surface in dark; card = surface / surfaceContainerHigh.)
    val base = if (darkTheme) darkColorScheme(
        background = Color(0xFF000000), onBackground = Color.White,
        surface = Color(0xFF000000), onSurface = Color.White,
        surfaceContainerLowest = Color(0xFF000000), surfaceContainerLow = Color(0xFF0E0E0F),
        surfaceContainer = Color(0xFF141415), surfaceContainerHigh = Color(0xFF1C1C1E),
        surfaceContainerHighest = Color(0xFF2C2C2E), surfaceVariant = Color(0xFF2C2C2E),
        onSurfaceVariant = Color(0xFF8D8D93), outline = Color(0xFF38383A),
        outlineVariant = Color(0xFF2C2C2E), surfaceBright = Color(0xFF2C2C2E), surfaceDim = Color.Black,
    ) else lightColorScheme(
        background = Color(0xFFF2F2F7), onBackground = Color.Black,
        surface = Color.White, onSurface = Color.Black,
        surfaceContainerLowest = Color.White, surfaceContainerLow = Color(0xFFF7F7FA),
        surfaceContainer = Color(0xFFF2F2F7), surfaceContainerHigh = Color(0xFFE9E9EE),
        surfaceContainerHighest = Color(0xFFE3E3E8), surfaceVariant = Color(0xFFE3E3E8),
        onSurfaceVariant = Color(0xFF8A8A8E), outline = Color(0xFFC6C6C8),
        outlineVariant = Color(0xFFD1D1D6), surfaceBright = Color.White, surfaceDim = Color(0xFFE5E5EA),
    )
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
        // Material's secondary/tertiary default to a purple the app never
        // chose — it showed as the selected tab's pill. One accent, as on iOS.
        secondary = accent, onSecondary = onAccent,
        secondaryContainer = accent.copy(alpha = 0.16f).compositeOver(base.surface),
        onSecondaryContainer = accent,
        tertiary = accent, onTertiary = onAccent,
        tertiaryContainer = accent.copy(alpha = 0.16f).compositeOver(base.surface),
        onTertiaryContainer = accent,
    )
    MaterialTheme(colorScheme = colors, typography = IosTypeScale, content = content)
}

/**
 * The iOS text styles, in Material's slots. Material's defaults were in use
 * untouched — 16sp MEDIUM for `titleMedium`, 0.15–0.5sp tracking everywhere —
 * so a call bubble read as a bold heading and every label was spaced out
 * next to the SF-set iPhone app. Each role now carries the size, weight and
 * leading of the iOS style it stands in for, with no added tracking:
 *
 *   headlineLarge  34 bold      Large Title     displays keep Material's
 *   headlineMedium 28           Title 1         (nothing in the app uses
 *   headlineSmall  22           Title 2          them at those sizes)
 *   titleLarge     20           Title 3   ← a call bubble (`.title3` on iOS)
 *   titleMedium    17 semibold  Headline
 *   titleSmall     15 semibold  Subheadline, emphasised
 *   bodyLarge      17           Body      ← a standard bubble, list rows
 *   bodyMedium     15           Subheadline
 *   bodySmall      13           Footnote
 *   labelLarge     17 semibold  button text
 *   labelMedium    13 medium    Footnote, emphasised
 *   labelSmall     12           Caption   ← a speaker's name over a bubble
 */
private fun ios(size: Int, leading: Int, weight: androidx.compose.ui.text.font.FontWeight =
    androidx.compose.ui.text.font.FontWeight.Normal) = androidx.compose.ui.text.TextStyle(
    fontSize = androidx.compose.ui.unit.TextUnit(size.toFloat(), androidx.compose.ui.unit.TextUnitType.Sp),
    lineHeight = androidx.compose.ui.unit.TextUnit(leading.toFloat(), androidx.compose.ui.unit.TextUnitType.Sp),
    fontWeight = weight,
    letterSpacing = androidx.compose.ui.unit.TextUnit(0f, androidx.compose.ui.unit.TextUnitType.Sp),
)

private val Semibold = androidx.compose.ui.text.font.FontWeight.SemiBold

val IosTypeScale = androidx.compose.material3.Typography().let { m ->
    m.copy(
        headlineLarge = ios(34, 41, androidx.compose.ui.text.font.FontWeight.Bold),
        headlineMedium = ios(28, 34),
        headlineSmall = ios(22, 28),
        titleLarge = ios(20, 25),
        titleMedium = ios(17, 22, Semibold),
        titleSmall = ios(15, 20, Semibold),
        bodyLarge = ios(17, 22),
        bodyMedium = ios(15, 20),
        bodySmall = ios(13, 18),
        labelLarge = ios(17, 22, Semibold),
        labelMedium = ios(13, 18, androidx.compose.ui.text.font.FontWeight.Medium),
        labelSmall = ios(12, 16),
    )
}
