package com.roro.futurevoice.ui.brand

import androidx.compose.foundation.Canvas
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.exp
import kotlin.math.floor
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sin

/**
 * A STATIC Futureself surface, drawn on the CPU — port of
 * `FutureselfPixels.swift`. A faithful copy of the shader's per-cell math at
 * one frozen instant: the same hash-driven cell life, ignition ordering,
 * 5-step palette snap with per-cell dither, hairline gap, and capsule-SDF
 * recess. Only the film grain is dropped — per-pixel noise nobody sees in a
 * still.
 *
 * **Cell size is FIXED, not derived from the frame**: a bigger surface gets
 * MORE cells, not bigger ones, so the circle and the pill wear the same
 * pixel scale. Clip it — capsule or circle, never a bare rectangle.
 */
@Composable
fun FutureselfPixels(
    modifier: Modifier = Modifier,
    theme: Int = 0,
    mode: FutureselfMode = FutureselfMode.SPEAKING,
    /** Frozen voice energy; a still needs some drive or it reads as a flat disc. */
    level: Float = 0.36f,
    /** The instant of the shader's clock this still is taken at. */
    time: Float = 3.2f,
    /** Cell edge in px. 12.8 = the app's pill (64 / 5 rows). */
    cell: Float = 12.8f,
    /**
     * How reluctantly a cell takes COLOUR. The ramp's first two steps are
     * neutral darks and the last three carry the hue, so raising this pushes
     * the middle of the distribution down. 1 = the shader's own curve.
     */
    colourFalloff: Float = 1f,
    /** Ceiling on the ramp step. 3 withholds the hottest tone (a sparkle in a still). */
    maxStep: Int = 4,
    dark: Boolean = true,
) {
    Canvas(modifier) {
        if (size.width <= 0f || size.height <= 0f || cell <= 0f) return@Canvas
        val base = FutureselfRamp.rgb(theme, dark, 0)
        drawRect(Color(base[0], base[1], base[2]))
        val cols = ceil(size.width / cell).toInt()
        val rows = ceil(size.height / cell).toInt()
        val gap = 1f
        for (cy in 0 until rows) for (cx in 0 until cols) {
            val origin = Offset(cx * cell, cy * cell)
            val center = Offset(origin.x + cell / 2, origin.y + cell / 2)
            drawRect(
                color = shade(cx, cy, center, size, theme, mode, level, time,
                    colourFalloff, maxStep, dark),
                topLeft = Offset(origin.x + gap / 2, origin.y + gap / 2),
                size = Size(cell - gap, cell - gap),
            )
        }
    }
}

/** The shader, on the CPU. */
private fun shade(
    cx: Int, cy: Int, center: Offset, size: Size, theme: Int, mode: FutureselfMode,
    level: Float, time: Float, colourFalloff: Float, maxStep: Int, dark: Boolean,
): Color {
    val r1 = hash21(cx + 0.13f, cy + 0.13f)
    val r2 = hash21(cx + 7.77f, cy + 7.77f)
    val r3 = hash21(cx + 23.19f, cy + 23.19f)
    val ux = center.x / size.width
    val uy = center.y / size.height

    var v = 0.16f + 0.14f * sin(time * (0.35f + 0.55f * r2) + r3 * 2f * Math.PI.toFloat())
    val bias = if (mode == FutureselfMode.SPEAKING) abs(ux - 0.5f) * 2f else 1f - uy
    val order = (r1 + (bias - r1) * 0.45f).coerceIn(0f, 1f)
    val drive = level.coerceIn(0f, 1f) * 1.15f
    val ignite = smoothstep(order, order + 0.22f, drive)
    v += ignite * (0.55f + 0.30f * r2)
    v += ignite * 0.08f * sin(time * (2f + 3f * r1) + r2 * 2f * Math.PI.toFloat())
    if (mode == FutureselfMode.THINKING) {
        val sx = 0.5f + 0.46f * sin(time * 1.4f)
        v += exp(-((ux - sx) * 3.5f).pow(2)) * (0.45f + 0.35f * r1)
    }
    if (mode == FutureselfMode.IDLE) v *= 0.7f
    if (colourFalloff != 1f) v = v.coerceIn(0f, 1f).pow(colourFalloff)

    val top = maxStep.coerceIn(0, 4)
    val step = floor(v * 4f + (r3 - 0.5f) * 0.9f + 0.5f).toInt().coerceIn(0, top)
    val ramp = FutureselfRamp.rgb(theme, dark, step)

    // Capsule-SDF recess, evaluated at the cell centre so it quantizes too.
    val rad = size.height / 2f
    val pcx = center.x - size.width / 2f
    val pcy = center.y - size.height / 2f
    val axx = max(size.width / 2f - rad, 0f)
    val qx = pcx.coerceIn(-axx, axx)
    val inset = rad - hypot(pcx - qx, pcy)
    val rim = exp(-max(inset, 0f) / 7f)
    val topW = (0.5f - pcy / size.height).coerceIn(0f, 1f)
    val k = 1f - rim * (0.14f + 0.34f * topW) * (if (dark) 0.85f else 0.45f)
    val lift = rim * (1f - topW) * (if (dark) 0.06f else 0.05f)
    return Color(
        min(ramp[0] * k + lift, 1f), min(ramp[1] * k + lift, 1f), min(ramp[2] * k + lift, 1f))
}

private fun hash21(x: Float, y: Float): Float {
    var px = frac(x * 123.34f); var py = frac(y * 456.21f)
    val d = px * (px + 45.32f) + py * (py + 45.32f)
    px += d; py += d
    return frac(px * py)
}
private fun frac(v: Float) = v - floor(v)
private fun smoothstep(e0: Float, e1: Float, x: Float): Float {
    if (e1 <= e0) return if (x < e0) 0f else 1f
    val t = ((x - e0) / (e1 - e0)).coerceIn(0f, 1f)
    return t * t * (3f - 2f * t)
}
