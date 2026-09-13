package com.roro.futurevoice.ui.brand

import androidx.compose.runtime.Composable
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.ui.graphics.Color

/**
 * The six palettes the Futureself surface can wear (`FutureselfTheme` in
 * Futureself.swift). Ordinal is what the shader and the stored preference
 * use, so the order is FROZEN — append, never reorder.
 */
enum class FutureselfTheme(val label: String) {
    BLUE("Blue"), MONO("Mono"), EMERALD("Emerald"),
    AMBER("Amber"), CORAL("Coral"), AQUA("Aqua");

    /**
     * Chrome that must match the shader surface (the call button's outline).
     * Each is the palette's vivid step, and every accent is ADAPTIVE: the
     * deep light-mode hues sit below dark mode's legibility floor, so dark
     * gets a brighter variant of the same hue.
     */
    @Composable
    fun tint(): Color = if (isSystemInDarkTheme()) darkTint else lightTint

    private val lightTint: Color get() = when (this) {
        BLUE -> Color(0.040f, 0.360f, 0.960f)
        MONO -> Color(0.16f, 0.16f, 0.16f)
        EMERALD -> Color(0.050f, 0.640f, 0.420f)
        AMBER -> Color(0.960f, 0.560f, 0.050f)
        CORAL -> Color(0.950f, 0.230f, 0.320f)
        AQUA -> Color(0.040f, 0.640f, 0.760f)
    }

    private val darkTint: Color get() = when (this) {
        BLUE -> Color(0.300f, 0.560f, 1.000f)
        MONO -> Color(0.86f, 0.86f, 0.86f)
        EMERALD -> Color(0.200f, 0.800f, 0.560f)
        AMBER -> Color(1.000f, 0.680f, 0.220f)
        CORAL -> Color(1.000f, 0.440f, 0.500f)
        AQUA -> Color(0.260f, 0.800f, 0.920f)
    }

    companion object {
        const val PREF_KEY = "futureselfTheme"
        fun from(ordinal: Int): FutureselfTheme = entries.getOrElse(ordinal) { BLUE }

        /** The learner's chosen palette (same key iOS's @AppStorage uses). */
        fun stored(context: android.content.Context): FutureselfTheme =
            live.value ?: from(context.getSharedPreferences("futurevoice", 0).getInt(PREF_KEY, 0))
                .also { live.value = it }

        /**
         * The palette the app is wearing RIGHT NOW. The accent reaches every
         * tinted control through the colour scheme, so a pick has to repaint
         * the app rather than wait for the next launch.
         */
        val live: androidx.compose.runtime.MutableState<FutureselfTheme?> =
            androidx.compose.runtime.mutableStateOf(null)

        fun pick(context: android.content.Context, theme: FutureselfTheme) {
            context.getSharedPreferences("futurevoice", 0).edit()
                .putInt(PREF_KEY, theme.ordinal).apply()
            live.value = theme
        }
    }
}
