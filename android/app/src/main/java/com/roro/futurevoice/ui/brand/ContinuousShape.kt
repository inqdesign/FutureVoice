package com.roro.futurevoice.ui.brand

import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Outline
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.vector.PathParser
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import kotlin.math.cos
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt
import kotlin.math.tan

/**
 * iOS's CONTINUOUS rounded corner (SwiftUI `.continuous`, every system card,
 * cell and sheet) — the curve eases into the straight edge instead of meeting
 * it at a circular arc's hard tangent point. Measured on the iOS app: a 16 pt
 * card's corner runs ~56 px (@3x) before it is straight, where a 16 pt circle
 * is straight after 48 — that longer, gentler run is what reads as "softer".
 *
 * The curve is Figma's corner smoothing (the published squircle construction,
 * `figma-squircle`): a circular arc in the middle, blended into both edges by
 * two cubic Béziers. Smoothing 0.6 is the value Figma itself labels "iOS".
 * The radius is the same number the design uses; only the curve changes.
 */
class ContinuousShape(
    private val radius: Dp,
    private val smoothing: Float = 0.6f,
) : Shape {
    override fun createOutline(size: Size, layoutDirection: LayoutDirection, density: Density): Outline {
        val w = size.width; val h = size.height
        val budget = min(w, h) / 2f
        val r = min(with(density) { radius.toPx() }, budget)
        if (r <= 0f) return Outline.Rectangle(androidx.compose.ui.geometry.Rect(0f, 0f, w, h))
        val c = corner(r, smoothing, budget)
        val path = PathParser().parsePathString(svg(w, h, c)).toPath()
        return Outline.Generic(path)
    }

    private class Corner(val a: Float, val b: Float, val c: Float, val d: Float, val p: Float,
                         val arc: Float, val r: Float)

    private fun rad(deg: Float) = Math.toRadians(deg.toDouble()).toFloat()

    private fun corner(r: Float, smoothingIn: Float, budget: Float): Corner {
        var p = (1 + smoothingIn) * r
        val s = smoothingIn
        val arcMeasure = 90f * (1 - s)
        val arc = sin(rad(arcMeasure / 2)) * r * sqrt(2f)
        val alpha = (90f - arcMeasure) / 2
        val p3p4 = r * tan(rad(alpha / 2))
        val beta = 45f * s
        val c = p3p4 * cos(rad(beta))
        val d = c * tan(rad(beta))
        var b = (p - arc - c - d) / 3
        var a = 2 * b
        // Preserve the smoothing on a shape too small for it (a capsule, a
        // short chip): squeeze the straight-edge blend, never the arc.
        if (p > budget) {
            val maxRun = budget - d - arc - c
            val minA = maxRun / 6
            val maxB = maxRun - minA
            b = min(b, maxB)
            a = maxRun - b
            p = min(p, budget)
        }
        return Corner(a, b, c, d, p, arc, r)
    }

    private fun f(v: Float) = String.format(java.util.Locale.US, "%.3f", v)

    private fun svg(w: Float, h: Float, k: Corner): String {
        val (a, b, c, d, r, arc) = listOf(k.a, k.b, k.c, k.d, k.r, k.arc)
        val abc = a + b + c; val bc = b + c; val ab = a + b
        return buildString {
            append("M ${f(w - k.p)} 0 ")
            append("c ${f(a)} 0 ${f(ab)} 0 ${f(abc)} ${f(d)} ")
            append("a ${f(r)} ${f(r)} 0 0 1 ${f(arc)} ${f(arc)} ")
            append("c ${f(d)} ${f(c)} ${f(d)} ${f(bc)} ${f(d)} ${f(abc)} ")
            append("L ${f(w)} ${f(h - k.p)} ")
            append("c 0 ${f(a)} 0 ${f(ab)} ${f(-d)} ${f(abc)} ")
            append("a ${f(r)} ${f(r)} 0 0 1 ${f(-arc)} ${f(arc)} ")
            append("c ${f(-c)} ${f(d)} ${f(-bc)} ${f(d)} ${f(-abc)} ${f(d)} ")
            append("L ${f(k.p)} ${f(h)} ")
            append("c ${f(-a)} 0 ${f(-ab)} 0 ${f(-abc)} ${f(-d)} ")
            append("a ${f(r)} ${f(r)} 0 0 1 ${f(-arc)} ${f(-arc)} ")
            append("c ${f(-d)} ${f(-c)} ${f(-d)} ${f(-bc)} ${f(-d)} ${f(-abc)} ")
            append("L 0 ${f(k.p)} ")
            append("c 0 ${f(-a)} 0 ${f(-ab)} ${f(d)} ${f(-abc)} ")
            append("a ${f(r)} ${f(r)} 0 0 1 ${f(arc)} ${f(-arc)} ")
            append("c ${f(c)} ${f(-d)} ${f(bc)} ${f(-d)} ${f(abc)} ${f(-d)} ")
            append("Z")
        }
    }

    override fun equals(other: Any?) = other is ContinuousShape && other.radius == radius && other.smoothing == smoothing
    override fun hashCode() = radius.hashCode() * 31 + smoothing.hashCode()
}

private operator fun <T> List<T>.component6() = this[5]

/** The iOS radii the app is drawn with — measured off the iOS build, so a
 *  change here is a change to what iOS does first. */
object IosRadius {
    /** System inset-grouped list cells (Settings, sheets): iOS 26. */
    val groupedCard = 26.dp
    val alert = 34.dp
    val sheet = 32.dp
    val menu = 22.dp
}
