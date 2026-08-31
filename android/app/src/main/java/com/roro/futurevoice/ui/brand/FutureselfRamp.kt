package com.roro.futurevoice.ui.brand

import androidx.compose.ui.graphics.Color

/**
 * Futureself's 5-step ramps — EXTRACTED from `FutureselfPixels.swift`
 * by scripts/android/gen-futureself-ramp.py, which lifts them from
 * `Shaders/Futureself.metal`. Indexed [theme][dark ? 0 : 1][step],
 * base → hottest. Never retyped: one brand, one palette.
 */
object FutureselfRamp {

    /** [theme][darkIndex][step] → rgb triple, 0…1. */
    val table: Array<Array<Array<FloatArray>>> = arrayOf(
        arrayOf( // 0 blue
            arrayOf(
                floatArrayOf(0.020f, 0.028f, 0.060f),
                floatArrayOf(0.080f, 0.095f, 0.130f),
                floatArrayOf(0.020f, 0.130f, 0.400f),
                floatArrayOf(0.040f, 0.360f, 0.960f),
                floatArrayOf(0.480f, 0.720f, 1.000f),
            ),
            arrayOf(
                floatArrayOf(0.965f, 0.972f, 1.000f),
                floatArrayOf(0.900f, 0.922f, 0.970f),
                floatArrayOf(0.720f, 0.830f, 1.000f),
                floatArrayOf(0.450f, 0.680f, 1.000f),
                floatArrayOf(0.030f, 0.340f, 0.950f),
            ),
        ),
        arrayOf( // 1 mono
            arrayOf(
                floatArrayOf(0.020f, 0.020f, 0.022f),
                floatArrayOf(0.090f, 0.090f, 0.095f),
                floatArrayOf(0.220f, 0.220f, 0.230f),
                floatArrayOf(0.550f, 0.550f, 0.560f),
                floatArrayOf(0.960f, 0.960f, 0.970f),
            ),
            arrayOf(
                floatArrayOf(0.970f, 0.970f, 0.972f),
                floatArrayOf(0.905f, 0.905f, 0.910f),
                floatArrayOf(0.760f, 0.760f, 0.770f),
                floatArrayOf(0.420f, 0.420f, 0.430f),
                floatArrayOf(0.070f, 0.070f, 0.080f),
            ),
        ),
        arrayOf( // 2 emerald
            arrayOf(
                floatArrayOf(0.015f, 0.030f, 0.025f),
                floatArrayOf(0.075f, 0.100f, 0.090f),
                floatArrayOf(0.020f, 0.230f, 0.160f),
                floatArrayOf(0.050f, 0.640f, 0.420f),
                floatArrayOf(0.560f, 0.940f, 0.760f),
            ),
            arrayOf(
                floatArrayOf(0.960f, 0.980f, 0.970f),
                floatArrayOf(0.885f, 0.925f, 0.905f),
                floatArrayOf(0.700f, 0.900f, 0.800f),
                floatArrayOf(0.350f, 0.780f, 0.560f),
                floatArrayOf(0.020f, 0.480f, 0.300f),
            ),
        ),
        arrayOf( // 3 amber
            arrayOf(
                floatArrayOf(0.040f, 0.028f, 0.015f),
                floatArrayOf(0.110f, 0.095f, 0.070f),
                floatArrayOf(0.400f, 0.220f, 0.020f),
                floatArrayOf(0.960f, 0.560f, 0.050f),
                floatArrayOf(1.000f, 0.830f, 0.480f),
            ),
            arrayOf(
                floatArrayOf(1.000f, 0.975f, 0.950f),
                floatArrayOf(0.945f, 0.910f, 0.860f),
                floatArrayOf(1.000f, 0.850f, 0.620f),
                floatArrayOf(1.000f, 0.690f, 0.330f),
                floatArrayOf(0.900f, 0.450f, 0.020f),
            ),
        ),
        arrayOf( // 4 coral
            arrayOf(
                floatArrayOf(0.040f, 0.015f, 0.030f),
                floatArrayOf(0.110f, 0.070f, 0.085f),
                floatArrayOf(0.380f, 0.050f, 0.140f),
                floatArrayOf(0.950f, 0.230f, 0.320f),
                floatArrayOf(1.000f, 0.640f, 0.660f),
            ),
            arrayOf(
                floatArrayOf(1.000f, 0.960f, 0.960f),
                floatArrayOf(0.950f, 0.890f, 0.890f),
                floatArrayOf(1.000f, 0.760f, 0.760f),
                floatArrayOf(0.990f, 0.500f, 0.520f),
                floatArrayOf(0.870f, 0.120f, 0.230f),
            ),
        ),
        arrayOf( // 5 aqua
            arrayOf(
                floatArrayOf(0.012f, 0.030f, 0.036f),
                floatArrayOf(0.070f, 0.100f, 0.108f),
                floatArrayOf(0.015f, 0.230f, 0.280f),
                floatArrayOf(0.040f, 0.640f, 0.760f),
                floatArrayOf(0.560f, 0.940f, 1.000f),
            ),
            arrayOf(
                floatArrayOf(0.955f, 0.980f, 0.985f),
                floatArrayOf(0.880f, 0.925f, 0.930f),
                floatArrayOf(0.680f, 0.890f, 0.930f),
                floatArrayOf(0.300f, 0.760f, 0.850f),
                floatArrayOf(0.020f, 0.480f, 0.590f),
            ),
        ),
    )

    fun rgb(theme: Int, dark: Boolean, step: Int): FloatArray =
        table[theme.coerceIn(0, table.size - 1)][if (dark) 0 else 1][step.coerceIn(0, 4)]

    fun color(theme: Int, dark: Boolean, step: Int): Color =
        rgb(theme, dark, step).let { Color(it[0], it[1], it[2]) }
}
