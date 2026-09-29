package com.roro.futurevoice.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameMillis
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.rotateRad
import androidx.compose.ui.graphics.drawscope.withTransform
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.unit.dp
import com.roro.futurevoice.ui.brand.AppSurfaces
import kotlin.math.exp
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

/**
 * The fluent self as the test's host (iOS `WeeklyTestCharacter`): two pixel
 * eyes on a rounded-square tile and nothing else. Each eye is ONE cell of the
 * app's 12.8 pt lattice, stretched tall (0.82 × 1.12), moved and blinked
 * smoothly. No mouth, no brows.
 *
 * Waiting glances and blinks; a right answer lifts the eyes with a flutter
 * and a bounce; a wrong one drops them, long and low; a second wrong in a row
 * narrows them into inward slits — a pout at itself, never a scold; while a
 * test is written they sweep.
 */
object WeeklyTestHost {
    enum class Mood { THINKING, WAITING, HAPPY, SAD, ANGRY }

    const val CELL = 12.8f
    const val CELLS = 6
    const val SIZE = CELL * CELLS
    const val EASE = 0.28
    const val CLOSED_HEIGHT = 2.5f
    private const val EYE_SPACING = 2f
    private const val TILE_RADIUS = 20f

    /** One eye, in points inside the tile. */
    data class Eye(val x: Float, val y: Float, val lid: Double = 0.0, val scaleY: Double = 1.0,
                   val scaleX: Double = 1.0, val tilt: Double = 0.0) {
        fun mix(b: Eye, k: Double) = Eye(
            x + ((b.x - x) * k).toFloat(), y + ((b.y - y) * k).toFloat(),
            lid + (b.lid - lid) * k, scaleY + (b.scaleY - scaleY) * k,
            scaleX + (b.scaleX - scaleX) * k, tilt + (b.tilt - tilt) * k)
    }

    data class Pose(val left: Eye, val right: Eye) {
        fun mix(b: Pose, k: Double) = Pose(left.mix(b.left, k), right.mix(b.right, k))
    }

    private val restLeftX = SIZE / 2 - CELL * EYE_SPACING / 2
    private val restRightX = SIZE / 2 + CELL * EYE_SPACING / 2
    private val restY = CELL * 2.5f

    private fun pose(dx: Double = 0.0, dy: Double = 0.0, lid: Double = 0.0, scaleY: Double = 1.0,
                     scaleX: Double = 1.0, tilt: Double = 0.0, apart: Double = 0.0): Pose {
        val ox = (dx * CELL).toFloat(); val oy = (dy * CELL).toFloat()
        val a = (apart * CELL / 2).toFloat()
        return Pose(Eye(restLeftX + ox - a, restY + oy, lid, scaleY, scaleX, tilt),
            Eye(restRightX + ox + a, restY + oy, lid, scaleY, scaleX, -tilt))
    }

    private fun settled(mood: Mood): Pose = when (mood) {
        Mood.HAPPY -> pose(dy = -0.6)
        Mood.SAD -> pose(dy = 0.6, lid = 0.15, scaleY = 0.6, scaleX = 1.45, tilt = -0.2)
        Mood.ANGRY -> pose(dy = 0.1, scaleY = 0.34, scaleX = 1.55, tilt = 0.36, apart = -0.3)
        Mood.WAITING, Mood.THINKING -> pose()
    }

    /** The face at time [t] (seconds), [elapsed] seconds into [mood]. */
    fun pose(mood: Mood, t: Double, elapsed: Double): Pose {
        val (gx, gy) = gaze(t)
        val neutral = pose(dx = gx, dy = gy, lid = blink(t, 3.8, 0.0))
        val k = smooth(elapsed / EASE)
        return when (mood) {
            Mood.WAITING -> neutral
            Mood.THINKING -> neutral.mix(pose(dx = sin(t * 1.4), lid = blink(t, 5.0, 3.1)), k)
            Mood.HAPPY -> {
                val flutter = maxOf(pulse(elapsed - 0.10, 0.06, 0.04, 0.08),
                    pulse(elapsed - 0.36, 0.06, 0.04, 0.08), pulse(elapsed - 0.62, 0.06, 0.04, 0.08))
                val bounce = if (elapsed < 1.4) -0.18 * sin(elapsed * 8) * exp(-elapsed * 2.6) else 0.0
                val s = settled(Mood.HAPPY)
                val by = (bounce * CELL).toFloat()
                neutral.mix(Pose(s.left.copy(lid = flutter, y = s.left.y + by),
                    s.right.copy(lid = flutter, y = s.right.y + by)), k)
            }
            Mood.SAD -> {
                val slow = pulse(elapsed - 0.7, 0.15, 0.2, 0.2)
                val s = settled(Mood.SAD)
                neutral.mix(Pose(s.left.copy(lid = max(s.left.lid, slow)),
                    s.right.copy(lid = max(s.right.lid, slow))), k)
            }
            Mood.ANGRY -> {
                val shake = if (elapsed < 0.5) 0.12 * sin(elapsed * 40) * exp(-elapsed * 7) else 0.0
                val s = settled(Mood.ANGRY)
                val sx = (shake * CELL).toFloat()
                neutral.mix(Pose(s.left.copy(x = s.left.x + sx), s.right.copy(x = s.right.x + sx)), k)
            }
        }
    }

    private fun blink(t: Double, every: Double, seed: Double): Double {
        val seg = floor(t / every)
        val period = every * (0.75 + 0.5 * hash(seg + seed))
        val phase = t % period
        val first = pulse(phase, 0.08, 0.07, 0.11)
        val double = if (hash(seg + seed + 9) < 0.25) pulse(phase - 0.34, 0.08, 0.07, 0.11) else 0.0
        return max(first, double)
    }

    private fun pulse(x: Double, up: Double, hold: Double, down: Double): Double = when {
        x < 0 -> 0.0
        x < up -> smooth(x / up)
        x < up + hold -> 1.0
        x < up + hold + down -> 1 - smooth((x - up - hold) / down)
        else -> 0.0
    }

    private val gazeX = doubleArrayOf(-1.0, -0.5, 0.0, 0.0, 0.0, 0.5, 1.0)

    private fun gaze(t: Double): Pair<Double, Double> {
        val hold = 1.6
        val segment = floor(t / hold)
        fun target(seg: Double): Pair<Double, Double> {
            val h1 = hash(seg + 0.5); val h2 = hash(seg + 17.3)
            val dx = gazeX[(h1 * 7).toInt() % 7]
            val dy = if (h2 < 0.15) -0.5 else if (h2 > 0.9) 0.25 else 0.0
            return dx to dy
        }
        val from = target(segment - 1); val to = target(segment)
        val k = smooth((t - segment * hold) / 0.25)
        return (from.first + (to.first - from.first) * k) to (from.second + (to.second - from.second) * k)
    }

    private fun smooth(x: Double): Double {
        val v = min(max(x, 0.0), 1.0)
        return v * v * (3 - 2 * v)
    }

    private fun hash(x: Double): Double {
        val v = sin(x * 12.9898 + 78.233) * 43758.5453
        return v - floor(v)
    }

    internal val tileRadius = TILE_RADIUS
}

/** The host's face. [since] is when [mood] began (epoch millis). */
@Composable
fun WeeklyTestCharacter(mood: WeeklyTestHost.Mood, since: Long, modifier: Modifier = Modifier,
                        tile: Color = AppSurfaces.card) {
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(Unit) {
        while (true) withFrameMillis { now = System.currentTimeMillis() }
    }
    val ink = if (isSystemInDarkTheme()) Color(0xFFF5F5F5) else Color(0xFF1A1A1A)
    Box(modifier
        .size(WeeklyTestHost.SIZE.dp)
        .background(tile, RoundedCornerShape(WeeklyTestHost.tileRadius.dp))
        .clearAndSetSemantics { }) {
        Canvas(Modifier.size(WeeklyTestHost.SIZE.dp)) {
            val scale = size.width / WeeklyTestHost.SIZE
            val t = now / 1000.0
            val pose = WeeklyTestHost.pose(mood, t, (now - since) / 1000.0)
            val w = WeeklyTestHost.CELL * 0.82f
            val openH = WeeklyTestHost.CELL * 1.12f
            val radius = 3.4f
            for (eye in listOf(pose.left, pose.right)) {
                val fullH = openH * eye.scaleY.toFloat()
                val h = max(WeeklyTestHost.CLOSED_HEIGHT,
                    fullH - (fullH - WeeklyTestHost.CLOSED_HEIGHT) * eye.lid.toFloat())
                val ew = w * eye.scaleX.toFloat()
                val r = min(radius, h / 2)
                withTransform({
                    translate(eye.x * scale, eye.y * scale)
                    rotateRad(eye.tilt.toFloat(), pivot = Offset.Zero)
                }) {
                    drawRoundRect(ink, topLeft = Offset(-ew / 2 * scale, -h / 2 * scale),
                        size = Size(ew * scale, h * scale), cornerRadius = CornerRadius(r * scale))
                }
            }
        }
    }
}
