package com.roro.futurevoice.ui.brand

import android.graphics.RuntimeShader
import android.os.Build
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ShaderBrush
import androidx.compose.ui.graphics.drawscope.DrawScope
import kotlin.math.abs
import kotlin.math.exp
import kotlin.math.floor
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

/**
 * Futureself — the call button's living surface, ported from
 * `Shaders/Futureself.metal`: a quantized PIXEL GRID in the app icon's
 * mosaic identity. Cells breathe individually in silence and ignite with the
 * voice; color snaps to a 5-step palette (no gradients inside a cell) so the
 * surface always reads as pixels, never as a blur.
 *
 *   listening: cells bloom upward from the bottom edge with mic energy
 *   speaking:  cells bloom outward from the center with playback energy
 *   thinking:  a scanner column sweeps the grid
 *   idle:      dim ambient twinkle, still alive
 *
 * AGSL (`RuntimeShader`, API 33+) runs the real thing; below that the same
 * cell math draws as rectangles on Canvas — coarser (no grain, no per-pixel
 * inner shadow) but the same mosaic, the same palette, the same bloom.
 *
 * The 5 ramp steps arrive as UNIFORMS rather than a constant array: theme
 * and dark mode are known when the frame is drawn, and SkSL indexing into a
 * 6×2×5 constant table with a runtime index is exactly the kind of thing
 * that differs between drivers.
 */
enum class FutureselfMode(val raw: Float) {
    IDLE(0f), LISTENING(1f), THINKING(2f), SPEAKING(3f)
}

private const val AGSL = """
uniform float2 uSize;
// Device pixels per POINT. AGSL hands `main` a fragCoord in device PIXELS,
// while Metal via SwiftUI's colorEffect works in POINTS — so every LENGTH
// constant below (the hairline gap, the rim falloff, the grain frequency)
// would be off by this factor. Converting once at the top keeps every
// number identical to `Futureself.metal` instead of scaling each by hand.
uniform float uPx;
uniform float uTime;
uniform float uLevel;
uniform float uMode;
uniform float uDark;
uniform float3 p0;
uniform float3 p1;
uniform float3 p2;
uniform float3 p3;
uniform float3 p4;

float hash21(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float3 rampAt(float i) {
    if (i < 0.5) { return p0; }
    if (i < 1.5) { return p1; }
    if (i < 2.5) { return p2; }
    if (i < 3.5) { return p3; }
    return p4;
}

half4 main(float2 fragCoord) {
    float2 position = fragCoord / uPx;
    // 5 rows of square cells; column count follows the surface width, so the
    // same shader stays icon-scaled on the pill and the home circle.
    float cellPt = uSize.y / 5.0;
    float2 cell = floor(position / cellPt);
    float2 cuv = (cell + 0.5) * cellPt / uSize;

    float r1 = hash21(cell + 0.13);
    float r2 = hash21(cell + 7.77);
    float r3 = hash21(cell + 23.19);

    // Ambient life: each cell breathes on its own slow phase.
    float v = 0.16 + 0.14 * sin(uTime * (0.35 + 0.55 * r2) + r3 * 6.2831);

    // Ignition order — randomness blended with a directional bias so the
    // bloom grows coherently but never reads as clean rows.
    float bias = (uMode > 2.5) ? abs(cuv.x - 0.5) * 2.0 : (1.0 - cuv.y);
    float order = clamp(mix(r1, bias, 0.45), 0.0, 1.0);
    float drive = clamp(uLevel, 0.0, 1.0) * 1.15;
    float ignite = smoothstep(order, order + 0.22, drive);
    v += ignite * (0.55 + 0.30 * r2);
    v += ignite * 0.08 * sin(uTime * (2.0 + 3.0 * r1) + r2 * 6.2831);

    if (uMode > 1.5 && uMode < 2.5) {
        float sx = 0.5 + 0.46 * sin(uTime * 1.4);
        float sweep = exp(-pow((cuv.x - sx) * 3.5, 2.0));
        v += sweep * (0.45 + 0.35 * r1);
    }
    if (uMode < 0.5) { v = v * 0.7; }

    // Snap to the 5-step palette, dithered per cell so neighbours never snap
    // in unison — the grid mutates cell by cell.
    float step5 = clamp(floor(v * 4.0 + (r3 - 0.5) * 0.9 + 0.5), 0.0, 4.0);
    float3 col = rampAt(step5);

    // Hairline gap in the base colour — this is what keeps the surface
    // reading as a mosaic instead of coloured noise.
    float2 f = position - cell * cellPt;
    float gapDist = min(min(f.x, f.y), min(cellPt - f.x, cellPt - f.y));
    col = mix(p0, col, smoothstep(0.35, 1.1, gapDist));

    // Inner shadow — recessed, not flat. Capsule SDF (a circle when w == h)
    // matches both clip shapes this surface lives in.
    float rad = uSize.y * 0.5;
    float2 pc = position - uSize * 0.5;
    float2 ax = float2(max(uSize.x * 0.5 - rad, 0.0), 0.0);
    float inset = rad - length(pc - clamp(pc, -ax, ax));
    float rim = exp(-max(inset, 0.0) / 7.0);
    float topW = clamp(0.5 - pc.y / uSize.y, 0.0, 1.0);
    float shade = rim * (0.14 + 0.34 * topW);
    col = col * (1.0 - shade * (uDark > 0.5 ? 0.85 : 0.45));
    col = col + float3(rim * (1.0 - topW) * (uDark > 0.5 ? 0.06 : 0.05));

    // Film grain — a whisper of texture, not a filter, reshuffled at a
    // filmic ~18fps so it flickers organically instead of buzzing.
    float tq = mod(floor(uTime * 18.0), 64.0);
    float g = hash21(position * 1.7 + tq * float2(13.7, 91.3)) - 0.5;
    col = col + float3(g * (uDark > 0.5 ? 0.06 : 0.04));

    return half4(half3(col), 1.0);
}
"""

/**
 * @param virtualHeight when set, the shader sees THIS height instead of the
 * real one, pinning the cell size (height/5) however big the frame is — the
 * Talk home's ring passes the call pill's height so the big circle keeps the
 * pill's fine grid and morphing between them never changes the pixel scale.
 */
@Composable
fun Futureself(
    mode: FutureselfMode,
    level: Float,
    modifier: Modifier = Modifier,
    theme: FutureselfTheme = FutureselfTheme.BLUE,
    virtualHeight: Float? = null,
) {
    val dark = isSystemInDarkTheme()
    val smoother = remember { LevelSmoother() }
    var time by remember { mutableFloatStateOf(0f) }
    var display by remember { mutableFloatStateOf(0f) }
    // One frame loop drives both the clock and the smoother: the level
    // arrives in coarse audio-buffer steps and is interpolated per FRAME so
    // the surface glides instead of stepping.
    LaunchedEffect(Unit) {
        var last = 0L
        while (true) {
            withFrameNanos { now ->
                val dt = if (last == 0L) 1f / 60f else ((now - last) / 1e9f).coerceIn(0f, 0.1f)
                last = now
                // Modulo keeps the float precise enough for the sin() phases.
                time = (time + dt) % 1000f
                display = smoother.step(level, dt)
            }
        }
    }
    val ramp = remember(theme, dark) {
        Array(5) { FutureselfRamp.rgb(theme.ordinal, dark, it) }
    }
    val shader = remember { if (Build.VERSION.SDK_INT >= 33) runCatching { RuntimeShader(AGSL) }.getOrNull() else null }

    Canvas(modifier) {
        // `virtualHeight` is a DP figure (the call pill is 64dp tall), but the
        // shader reads `fragCoord` in device PIXELS — so it has to be
        // converted, or the cell grid comes out `density` times too fine.
        // On a 2.75x screen that turned the pill's 12.8dp cell into a 4.6dp
        // one: the surface still looked like a mosaic, just a far grainier
        // one than the design, and the ring read as flat noise.
        // Everything the shader sees is in POINTS — see `uPx` in the source.
        val h = virtualHeight ?: (size.height / density)
        val w = size.width * (h / max(size.height, 1f))
        if (shader != null && Build.VERSION.SDK_INT >= 33) {
            shader.setFloatUniform("uSize", w, h)
            shader.setFloatUniform("uPx", density)
            shader.setFloatUniform("uTime", time)
            shader.setFloatUniform("uLevel", display)
            shader.setFloatUniform("uMode", mode.raw)
            shader.setFloatUniform("uDark", if (dark) 1f else 0f)
            ramp.forEachIndexed { i, c -> shader.setFloatUniform("p$i", c[0], c[1], c[2]) }
            drawRect(brush = ShaderBrush(shader))
        } else {
            drawMosaic(time, display, mode, dark, ramp, h)
        }
    }
}

/** Canvas fallback: the same cell math, drawn as rectangles (API < 33). */
private fun DrawScope.drawMosaic(
    time: Float, level: Float, mode: FutureselfMode, dark: Boolean,
    ramp: Array<FloatArray>, virtualH: Float,
) {
    val cell = virtualH / 5f
    if (cell <= 0f) return
    val cols = (size.width / cell).toInt() + 1
    val rows = (size.height / cell).toInt() + 1
    val drive = level.coerceIn(0f, 1f) * 1.15f
    for (cy in 0 until rows) for (cx in 0 until cols) {
        val r1 = hash21(cx + 0.13f, cy + 0.13f)
        val r2 = hash21(cx + 7.77f, cy + 7.77f)
        val r3 = hash21(cx + 23.19f, cy + 23.19f)
        val ux = (cx + 0.5f) * cell / size.width
        val uy = (cy + 0.5f) * cell / size.height
        var v = 0.16f + 0.14f * sin(time * (0.35f + 0.55f * r2) + r3 * 6.2831f)
        val bias = if (mode == FutureselfMode.SPEAKING) abs(ux - 0.5f) * 2f else 1f - uy
        val order = (r1 + (bias - r1) * 0.45f).coerceIn(0f, 1f)
        val ignite = smoothstep(order, order + 0.22f, drive)
        v += ignite * (0.55f + 0.30f * r2)
        if (mode == FutureselfMode.THINKING) {
            val sx = 0.5f + 0.46f * sin(time * 1.4f)
            v += exp(-((ux - sx) * 3.5f) * ((ux - sx) * 3.5f)) * (0.45f + 0.35f * r1)
        }
        if (mode == FutureselfMode.IDLE) v *= 0.7f
        val step = floor(v * 4f + (r3 - 0.5f) * 0.9f + 0.5f).toInt().coerceIn(0, 4)
        val c = ramp[step]
        // A one-pixel inset reproduces the shader's hairline gap.
        drawRect(color = Color(c[0], c[1], c[2]),
            topLeft = Offset(cx * cell + 0.5f, cy * cell + 0.5f),
            size = Size(cell - 1f, cell - 1f))
    }
}

private fun hash21(x: Float, y: Float): Float {
    var px = frac(x * 123.34f); var py = frac(y * 456.21f)
    val d = px * (px + 45.32f) + py * (py + 45.32f)
    px += d; py += d
    return frac(px * py)
}
private fun frac(v: Float) = v - floor(v)
private fun smoothstep(e0: Float, e1: Float, x: Float): Float {
    val t = ((x - e0) / (e1 - e0)).coerceIn(0f, 1f)
    return t * t * (3f - 2f * t)
}

/**
 * Rises fast, falls slow — a voice that stops should leave the surface
 * glowing for a beat, not snap dark (iOS `LevelSmoother`).
 */
private class LevelSmoother {
    private var value = 0f
    fun step(target: Float, dt: Float): Float {
        val tau = if (target > value) 0.06f else 0.35f
        value += (target - value) * (1f - exp(-dt / tau))
        return value
    }
}
