package com.roro.futurevoice.widget

import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.net.Uri
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.glance.GlanceModifier
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.action.Action
import androidx.glance.action.clickable
import androidx.glance.appwidget.action.actionStartActivity
import androidx.glance.appwidget.cornerRadius
import androidx.glance.background
import androidx.glance.layout.Box
import androidx.glance.layout.ContentScale
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.padding
import androidx.glance.unit.ColorProvider
import kotlin.math.floor
import kotlin.math.min

/**
 * The widgets' tone, from the learner's Futureself palette (`WidgetTheme` in
 * StudyWidgetShared.swift): `ground` the dark display, `vivid` the accent,
 * `frame` the bezel. One committed dark look — it doesn't follow light/dark,
 * so the pixel accent reads the same on any home screen.
 */
object WidgetTheme {
    private val groundC = listOf(
        floatArrayOf(0.030f, 0.036f, 0.070f), floatArrayOf(0.030f, 0.030f, 0.032f),
        floatArrayOf(0.022f, 0.038f, 0.032f), floatArrayOf(0.048f, 0.036f, 0.020f),
        floatArrayOf(0.048f, 0.022f, 0.036f), floatArrayOf(0.018f, 0.038f, 0.044f),
    )
    private val vividC = listOf(
        floatArrayOf(0.480f, 0.720f, 1.000f), floatArrayOf(0.960f, 0.960f, 0.970f),
        floatArrayOf(0.560f, 0.940f, 0.760f), floatArrayOf(1.000f, 0.830f, 0.480f),
        floatArrayOf(1.000f, 0.640f, 0.660f), floatArrayOf(0.560f, 0.940f, 1.000f),
    )
    /** A deep, saturated shade of the accent, hand-picked per theme. */
    private val frameC = listOf(
        floatArrayOf(0.030f, 0.140f, 0.480f), floatArrayOf(0.090f, 0.090f, 0.100f),
        floatArrayOf(0.020f, 0.320f, 0.210f), floatArrayOf(0.500f, 0.280f, 0.030f),
        floatArrayOf(0.500f, 0.100f, 0.150f), floatArrayOf(0.020f, 0.320f, 0.420f),
    )
    private fun pick(t: List<FloatArray>, i: Int): Color {
        val v = t[((i % t.size) + t.size) % t.size]
        return Color(v[0], v[1], v[2])
    }
    fun ground(i: Int) = pick(groundC, i)
    fun vivid(i: Int) = pick(vividC, i)
    fun frame(i: Int) = pick(frameC, i)
}

/** The streak mascot's pixel unit — face pixels AND grid cells, one display. */
val streakPixel: Dp = 8.dp
/** The Futureself cell — the app's pill is five of these tall. */
const val FUTURESELF_CELL_DP = 12.8f
/** Default graph-paper spacing. */
val gridStep: Dp = 26.dp

internal fun Color.provider() = ColorProvider(this)

/** Opens `futurevoice://…` in the app — the same scheme iOS widgets use. */
internal fun openLink(link: String): Action = actionStartActivity(
    Intent(Intent.ACTION_VIEW, Uri.parse(link)).apply {
        setPackage("com.roro.futurevoice")
        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    })

/**
 * The shared widget surface: the theme's bezel, the dark ground, and the
 * faint graph paper lines (`WidgetGrid`). [phase] shifts the lattice so a
 * surface in front of it (the Free Talk pill) lines up with it.
 */
@Composable
internal fun WidgetSurface(
    context: Context,
    theme: Int,
    width: Dp,
    height: Dp,
    link: String,
    step: Dp = gridStep,
    phase: Pair<Float, Float> = 0f to 0f,
    content: @Composable () -> Unit,
) {
    Box(
        GlanceModifier.fillMaxSize()
            .background(WidgetTheme.frame(theme).provider())
            .cornerRadius(20.dp)
            .clickable(openLink(link)),
    ) {
        Box(
            GlanceModifier.fillMaxSize().padding(4.dp)
                .cornerRadius(16.dp),
        ) {
            Box(GlanceModifier.fillMaxSize().background(WidgetTheme.ground(theme).provider())
                .cornerRadius(16.dp)) {
                // The bezel eats 4dp a side, so the paper is the inner size exactly —
                // stretched, its lattice would drift off the pill in front of it.
                gridBitmap(context, theme, width - 8.dp, height - 8.dp, step, phase)?.let {
                    Image(ImageProvider(it), contentDescription = null,
                        modifier = GlanceModifier.fillMaxSize(), contentScale = ContentScale.FillBounds)
                }
                content()
            }
        }
    }
}

private fun density(context: Context) = context.resources.displayMetrics.density

/** Bitmaps stay under RemoteViews' memory ceiling whatever the launcher asks. */
private fun px(context: Context, dp: Float) = (dp * density(context)).toInt().coerceIn(1, 1200)

/** Faint grid lines tinted with the theme's accent, on a transparent sheet. */
private fun gridBitmap(context: Context, theme: Int, width: Dp, height: Dp, step: Dp,
                       phase: Pair<Float, Float>): Bitmap? {
    val d = density(context)
    val w = px(context, width.value); val h = px(context, height.value)
    if (w <= 1 || h <= 1) return null
    val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
    val c = Canvas(bmp)
    val paint = Paint().apply {
        color = WidgetTheme.vivid(theme).copy(alpha = 0.06f).toArgb()
        strokeWidth = d
    }
    val s = step.value * d
    var x = phase.first * d - s
    while (x <= w) { c.drawLine(x, 0f, x, h.toFloat(), paint); x += s }
    var y = phase.second * d - s
    while (y <= h) { c.drawLine(0f, y, w.toFloat(), y, paint); y += s }
    return bmp
}

/** The goal ring (`ProgressCard.ring`): a faint track and the accent arc. */
internal fun ringBitmap(context: Context, sizeDp: Float, lineDp: Float, progress: Double,
                        vivid: Color): Bitmap {
    val d = density(context)
    val s = px(context, sizeDp)
    val bmp = Bitmap.createBitmap(s, s, Bitmap.Config.ARGB_8888)
    val c = Canvas(bmp)
    val stroke = lineDp * d
    val rect = RectF(stroke / 2, stroke / 2, s - stroke / 2, s - stroke / 2)
    val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE; strokeWidth = stroke
        color = Color.White.copy(alpha = 0.12f).toArgb()
    }
    c.drawArc(rect, 0f, 360f, false, paint)
    paint.color = vivid.toArgb(); paint.strokeCap = Paint.Cap.ROUND
    c.drawArc(rect, -90f, (360f * progress.coerceIn(0.001, 1.0)).toFloat(), false, paint)
    return bmp
}

/** The streak mascot's mood (`StreakFace`). */
enum class StreakFace { HAPPY, ANXIOUS, NEUTRAL }

private val faceRows = mapOf(
    StreakFace.HAPPY to listOf(
        "           ", "           ", "           ", "   #   #   ", "           ",
        "           ", "  #     #  ", "   #####   ", "           ", "           ", "           "),
    StreakFace.ANXIOUS to listOf(
        "           ", "           ", " o         ", "   #   #   ", "           ",
        "           ", "   #####   ", "  #     #  ", "           ", "           ", "           "),
    StreakFace.NEUTRAL to listOf(
        "           ", "           ", "           ", "   #   #   ", "           ",
        "           ", "           ", "   #####   ", "           ", "           ", "           "),
)

/** The 11×11 pixel face (`PixelFace`), cells [streakPixel] wide. */
internal fun faceBitmap(context: Context, face: StreakFace, color: Color): Bitmap {
    val rows = faceRows.getValue(face)
    val cell = streakPixel.value * density(context)
    val n = rows.size
    val bmp = Bitmap.createBitmap((cell * n).toInt(), (cell * n).toInt(), Bitmap.Config.ARGB_8888)
    val c = Canvas(bmp)
    val accent = Paint().apply { this.color = color.toArgb() }
    val marker = Paint().apply { this.color = Color(0.55f, 0.8f, 1.0f).toArgb() }
    rows.forEachIndexed { r, line ->
        line.forEachIndexed { col, ch ->
            if (ch != ' ') c.drawRect(col * cell, r * cell, col * cell + cell * 0.9f,
                r * cell + cell * 0.9f, if (ch == 'o') marker else accent)
        }
    }
    return bmp
}

/**
 * The Free Talk pill's geometry (`FutureselfLattice`): a whole number of
 * cells each way so its edges land ON lattice lines, and the lattice then
 * anchored to the surface, so the leftover fraction moves to the tile's edge.
 */
internal object FutureselfLattice {
    fun inset(compact: Boolean) = if (compact) 12f else 16f

    /** Surface size in dp. */
    fun surfaceSize(w: Float, h: Float, compact: Boolean): Pair<Float, Float> {
        val cell = FUTURESELF_CELL_DP
        val pad = inset(compact) * 2
        fun cells(available: Float) = maxOf(cell, floor(available / cell) * cell)
        val rows = if (compact) 5f else 8f
        return cells(w - pad) to min(cells(h - pad), cell * rows)
    }

    /** The lattice offset both the surface and the graph paper start from. */
    fun phase(w: Float, h: Float, compact: Boolean): Pair<Float, Float> {
        val (sw, sh) = surfaceSize(w, h, compact)
        return ((w - sw) / 2) % FUTURESELF_CELL_DP to ((h - sh) / 2) % FUTURESELF_CELL_DP
    }
}

/**
 * The static Futureself pill (`FreeTalkCard.surface`): the mosaic, the ground
 * wash so the type reads, clipped to a capsule with a hairline rim.
 */
internal fun freeTalkPillBitmap(context: Context, theme: Int, wDp: Float, hDp: Float,
                                compact: Boolean): Bitmap {
    val d = density(context)
    val w = px(context, wDp); val h = px(context, hDp)
    val mosaic = com.roro.futurevoice.ui.brand.futureselfPixelsBitmap(
        w, h, theme = theme, level = 0.5f, time = 3.2f, cell = FUTURESELF_CELL_DP * d,
        colourFalloff = if (compact) 2.2f else 5f, maxStep = 3, dark = true)
    val out = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
    val c = Canvas(out)
    val r = h / 2f
    val capsule = Path().apply { addRoundRect(RectF(0f, 0f, w.toFloat(), h.toFloat()), r, r, Path.Direction.CW) }
    c.save(); c.clipPath(capsule)
    c.drawBitmap(mosaic, 0f, 0f, null)
    c.drawColor(WidgetTheme.ground(theme).copy(alpha = 0.14f).toArgb())
    // The app's inner shadow, approximated: a dark ring hugging the edge.
    val shade = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE; strokeWidth = 6 * d
        color = Color.Black.copy(alpha = 0.30f).toArgb()
    }
    c.drawRoundRect(RectF(3 * d, 3 * d, w - 3 * d, h - 3 * d), r - 3 * d, r - 3 * d, shade)
    c.restore()
    val rim = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE; strokeWidth = 0.5f * d
        color = Color.White.copy(alpha = 0.14f).toArgb()
    }
    c.drawRoundRect(RectF(0.25f * d, 0.25f * d, w - 0.25f * d, h - 0.25f * d), r, r, rim)
    return out
}
