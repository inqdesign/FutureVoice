package com.roro.futurevoice.ui

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas as AndroidCanvas
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.PorterDuff
import android.graphics.PorterDuffColorFilter
import android.graphics.RectF
import android.graphics.Typeface
import android.text.Layout
import android.text.StaticLayout
import android.text.TextPaint
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.core.content.res.ResourcesCompat
import com.roro.futurevoice.R
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * iOS `CoreCubeView`: a member's seat as a cube — the name on the front, the
 * hope on the back (left blank for a reader not allowed it), SINCE / DAY on
 * one side, the nawana mark on the other. iOS draws it in SceneKit; here it
 * is six textured faces projected by hand (orthographic, so the face that
 * turns to the learner is exactly [unit] wide — the size of the square that
 * takes over for the flight into the grid).
 *
 * It arrives small and tumbling, settles tipped toward the learner, then
 * turns once every [TURN_SECONDS]. Drag sideways to turn it, up and down to
 * tip it. [flatten] turns it square to the learner.
 */
@Composable
fun CoreCube(
    color: Color,
    name: String,
    hope: String,
    modifier: Modifier = Modifier,
    since: String? = null,
    days: Int? = null,
    flatten: Boolean = false,
    unit: Dp = CoreCubeUnit,
) {
    val context = LocalContext.current
    val unitPx = with(LocalDensity.current) { unit.toPx() }
    var yaw by remember { mutableFloatStateOf(-4.6f) }
    var pitch by remember { mutableFloatStateOf(2.4f) }
    var scale by remember { mutableFloatStateOf(0.15f) }
    var dragging by remember { mutableStateOf(false) }

    // Arrival, then the slow turn; or, flattened, square to the learner.
    LaunchedEffect(flatten, dragging) {
        if (dragging) return@LaunchedEffect
        if (flatten) {
            val y0 = yaw; val p0 = pitch; val s0 = scale
            val target = ((y0 / (2 * PI)).roundToInt() * 2 * PI).toFloat()
            val start = withFrameNanos { it }
            var t = 0f
            while (t < 1f) {
                t = withFrameNanos { ((it - start) / 450_000_000f).coerceAtMost(1f) }
                val e = ease(t)
                yaw = y0 + (target - y0) * e; pitch = p0 * (1 - e); scale = s0 + (1 - s0) * e
            }
            return@LaunchedEffect
        }
        if (scale < 1f || abs(pitch - TILT) > 0.01f) {
            val y0 = yaw; val p0 = pitch; val s0 = scale
            val y1 = if (scale < 1f) (PI / 4).toFloat() else yaw + (PI / 4).toFloat()
            val ms = if (scale < 1f) 1_200_000_000f else 500_000_000f
            val start = withFrameNanos { it }
            var t = 0f
            while (t < 1f) {
                t = withFrameNanos { ((it - start) / ms).coerceAtMost(1f) }
                val e = 1 - (1 - t) * (1 - t)
                yaw = y0 + (y1 - y0) * e; pitch = p0 + (TILT - p0) * e; scale = s0 + (1 - s0) * e
            }
        }
        var last = withFrameNanos { it }
        while (true) {
            val now = withFrameNanos { it }
            yaw += ((now - last) / 1e9f) * (2 * PI / TURN_SECONDS).toFloat()
            last = now
        }
    }

    val faces = remember(color, name, hope, since, days) {
        CubeFaces.build(context, color, name, hope, since, days)
    }

    Canvas(modifier.pointerInput(flatten) {
        if (flatten) return@pointerInput
        detectDragGestures(
            onDragStart = { dragging = true; scale = 1f; HapticEngine.selection(context) },
            onDragEnd = { dragging = false },
            onDragCancel = { dragging = false },
        ) { change, amount ->
            change.consume()
            yaw += amount.x * 0.012f
            pitch = (pitch + amount.y * 0.012f).coerceIn(-1.2f, 1.2f)
        }
    }) {
        drawCube(faces, yaw, pitch, unitPx * scale)
    }
}

val CoreCubeUnit = 116.dp
private const val TILT = 0.48f
const val TURN_SECONDS = 20.0

private fun ease(t: Float) = if (t < 0.5f) 2 * t * t else 1 - (-2 * t + 2).let { it * it } / 2

private val CORNERS = arrayOf(
    // front (+z): name
    floatArrayOf(-.5f, .5f, .5f, .5f, .5f, .5f, .5f, -.5f, .5f, -.5f, -.5f, .5f),
    // right (+x): plaque
    floatArrayOf(.5f, .5f, .5f, .5f, .5f, -.5f, .5f, -.5f, -.5f, .5f, -.5f, .5f),
    // back (-z): hope
    floatArrayOf(.5f, .5f, -.5f, -.5f, .5f, -.5f, -.5f, -.5f, -.5f, .5f, -.5f, -.5f),
    // left (-x): mark
    floatArrayOf(-.5f, .5f, -.5f, -.5f, .5f, .5f, -.5f, -.5f, .5f, -.5f, -.5f, -.5f),
    // top (+y)
    floatArrayOf(-.5f, .5f, -.5f, .5f, .5f, -.5f, .5f, .5f, .5f, -.5f, .5f, .5f),
    // bottom (-y)
    floatArrayOf(-.5f, -.5f, .5f, .5f, -.5f, .5f, .5f, -.5f, -.5f, -.5f, -.5f, -.5f),
)
private val NORMALS = arrayOf(
    floatArrayOf(0f, 0f, 1f), floatArrayOf(1f, 0f, 0f), floatArrayOf(0f, 0f, -1f),
    floatArrayOf(-1f, 0f, 0f), floatArrayOf(0f, 1f, 0f), floatArrayOf(0f, -1f, 0f),
)
/** Light from the upper left, in front. */
private val LIGHT = floatArrayOf(-0.35f, 0.75f, 0.56f).let { v ->
    val l = sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]); floatArrayOf(v[0] / l, v[1] / l, v[2] / l)
}

private fun rotate(x: Float, y: Float, z: Float, yaw: Float, pitch: Float): FloatArray {
    val cy = cos(yaw); val sy = sin(yaw); val cp = cos(pitch); val sp = sin(pitch)
    val x1 = x * cy + z * sy
    val z1 = -x * sy + z * cy
    return floatArrayOf(x1, y * cp - z1 * sp, y * sp + z1 * cp)
}

private fun DrawScope.drawCube(faces: CubeFaces, yaw: Float, pitch: Float, side: Float) {
    val cx = size.width / 2; val cy = size.height / 2
    data class Drawn(val i: Int, val pts: FloatArray, val depth: Float, val light: Float)
    val drawn = (0 until 6).mapNotNull { i ->
        val n = NORMALS[i].let { rotate(it[0], it[1], it[2], yaw, pitch) }
        if (n[2] <= 0.01f) return@mapNotNull null
        val c = CORNERS[i]
        val pts = FloatArray(8); var depth = 0f
        for (k in 0 until 4) {
            val r = rotate(c[k * 3], c[k * 3 + 1], c[k * 3 + 2], yaw, pitch)
            pts[k * 2] = cx + r[0] * side
            pts[k * 2 + 1] = cy - r[1] * side
            depth += r[2]
        }
        val lit = max(0f, n[0] * LIGHT[0] + n[1] * LIGHT[1] + n[2] * LIGHT[2])
        Drawn(i, pts, depth, lit)
    }.sortedBy { it.depth }

    val paint = Paint(Paint.FILTER_BITMAP_FLAG)
    val shade = Paint()
    drawContext.canvas.nativeCanvas.apply {
        for (d in drawn) {
            val bmp = faces.bitmaps[d.i]
            val w = bmp.width.toFloat(); val h = bmp.height.toFloat()
            val m = Matrix()
            m.setPolyToPoly(floatArrayOf(0f, 0f, w, 0f, w, h, 0f, h), 0, d.pts, 0, 4)
            save()
            concat(m)
            drawBitmap(bmp, 0f, 0f, paint)
            // Lambert shading as a dark wash, a touch of white on the lit side.
            val dark = ((1f - (0.62f + 0.38f * d.light)) * 255 * 0.9f).toInt().coerceIn(0, 255)
            shade.color = android.graphics.Color.argb(dark, 0, 0, 0)
            drawRect(0f, 0f, w, h, shade)
            if (d.light > 0.8f) {
                shade.color = android.graphics.Color.argb(((d.light - 0.8f) * 120).toInt(), 255, 255, 255)
                drawRect(0f, 0f, w, h, shade)
            }
            restore()
        }
    }
}

/** The six face images, drawn once per colour and engraving. */
class CubeFaces private constructor(val bitmaps: List<Bitmap>) {
    companion object {
        const val SIDE = 320
        const val CORNER = 0.09f

        fun build(context: Context, color: Color, name: String, hope: String,
                  since: String?, days: Int?): CubeFaces {
            val base = color.toArgb()
            return CubeFaces(listOf(
                text(context, base, name, isName = true),
                if (days != null) plaque(base, since, days) else plain(base),
                text(context, base, hope, isName = false),
                mark(context, base),
                plain(base),
                plain(base),
            ))
        }

        /** The inside of a cut: the face's own colour, much deeper (iOS `carved`). */
        fun carved(argb: Int): Int {
            val hsv = FloatArray(3)
            android.graphics.Color.colorToHSV(argb, hsv)
            if (hsv[1] >= 0.08f) hsv[1] = min(1f, hsv[1] * 1.15f + 0.1f)
            hsv[2] *= 0.42f
            return android.graphics.Color.HSVToColor(hsv)
        }

        private fun blank(base: Int): Pair<Bitmap, AndroidCanvas> {
            val bmp = Bitmap.createBitmap(SIDE, SIDE, Bitmap.Config.ARGB_8888)
            val c = AndroidCanvas(bmp)
            // Square to the edge: neighbouring faces meet with no seam.
            c.drawColor(base)
            return bmp to c
        }

        private fun plain(base: Int) = blank(base).first

        /** Pressed in: a pale lip under the letters, then the carved colour. */
        private inline fun deboss(base: Int, draw: (TextPaint) -> Unit) {
            val lip = TextPaint(Paint.ANTI_ALIAS_FLAG).apply { color = android.graphics.Color.argb(77, 255, 255, 255) }
            draw(lip.also { it.setShadowLayer(0f, 0f, 0f, 0) })
            val cut = TextPaint(Paint.ANTI_ALIAS_FLAG).apply { color = carved(base) }
            draw(cut)
        }

        /** The name large, the hope smaller over up to three lines, in
         *  handwriting (Nanum Pen Script, bundled, OFL; iOS uses Snell
         *  Roundhand for Latin, which Android doesn't have). */
        private fun text(context: Context, base: Int, raw: String, isName: Boolean): Bitmap {
            val (bmp, c) = blank(base)
            val t = raw.trim()
            if (t.isEmpty()) return bmp
            val face = ResourcesCompat.getFont(context, R.font.nanum_pen_script) ?: Typeface.DEFAULT_BOLD
            val size = SIDE / 512f * if (isName) (if (t.length > 12) 100f else if (t.length > 7) 124f else 150f)
                       else (if (t.length > 36) 66f else if (t.length > 20) 78f else 92f)
            val box = SIDE - SIDE * 0.14f
            fun layout(p: TextPaint) = StaticLayout.Builder.obtain(t, 0, t.length, p, box.toInt())
                .setAlignment(Layout.Alignment.ALIGN_CENTER).setMaxLines(3)
                .setEllipsize(android.text.TextUtils.TruncateAt.END).build()
            deboss(base) { p ->
                p.typeface = face; p.textSize = size
                val l = layout(p)
                val dy = if (p.alpha < 200) 2.5f else 0f
                c.save()
                c.translate((SIDE - box) / 2, (SIDE - l.height) / 2f + dy)
                l.draw(c)
                c.restore()
            }
            return bmp
        }

        /** SINCE and the date top-left, DAY and the count bottom-right,
         *  upright serif, in English on every phone like a dedication plate. */
        private fun plaque(base: Int, since: String?, days: Int): Bitmap {
            val (bmp, c) = blank(base)
            val k = SIDE / 512f
            val inset = 48f * k
            val date = since?.replace("-", ".").orEmpty()
            deboss(base) { p ->
                val dy = if (p.alpha < 200) 2.5f else 0f
                fun serif(size: Float, bold: Boolean) {
                    p.typeface = Typeface.create(Typeface.SERIF, if (bold) Typeface.BOLD else Typeface.NORMAL)
                    p.textSize = size * k
                }
                if (date.isNotEmpty()) {
                    serif(30f, true); p.letterSpacing = 0.2f
                    c.drawText("SINCE", inset, inset + 30f * k + dy, p)
                    serif(44f, false); p.letterSpacing = 0.04f
                    c.drawText(date, inset, inset + 82f * k + dy, p)
                }
                serif(96f, false); p.letterSpacing = 0f
                val n = "$days"
                val nw = p.measureText(n)
                c.drawText(n, SIDE - inset - nw, SIDE - inset + dy, p)
                serif(30f, true); p.letterSpacing = 0.2f
                val lw = p.measureText("DAY")
                c.drawText("DAY", SIDE - inset - lw, SIDE - inset - 96f * k + dy, p)
                p.letterSpacing = 0f
            }
            return bmp
        }

        /** The nawana mark, small in the middle of a face. */
        private fun mark(context: Context, base: Int): Bitmap {
            val (bmp, c) = blank(base)
            val src = BitmapFactory.decodeResource(context.resources, R.drawable.core_mark) ?: return bmp
            val w = SIDE * 120f / 512f
            val h = w * src.height / src.width
            val dst = RectF((SIDE - w) / 2, (SIDE - h) / 2, (SIDE + w) / 2, (SIDE + h) / 2)
            val lip = Paint(Paint.FILTER_BITMAP_FLAG).apply {
                colorFilter = PorterDuffColorFilter(android.graphics.Color.argb(77, 255, 255, 255), PorterDuff.Mode.SRC_IN) }
            c.drawBitmap(src, null, RectF(dst.left, dst.top + 2.5f, dst.right, dst.bottom + 2.5f), lip)
            val cut = Paint(Paint.FILTER_BITMAP_FLAG).apply {
                colorFilter = PorterDuffColorFilter(carved(base), PorterDuff.Mode.SRC_IN) }
            c.drawBitmap(src, null, dst, cut)
            return bmp
        }
    }
}

// ── The seat grid, as blocks ──────────────────────────────────────────────

/** Where cell [index] sits in a [columns]-wide grid of [size], with [gap]. */
fun coreCellRect(index: Int, size: Size, columns: Int, gap: Float): Rect {
    val side = (size.width - gap * (columns - 1)) / columns
    val x = (index % columns) * (side + gap); val y = (index / columns) * (side + gap)
    return Rect(Offset(x, y), Size(side, side))
}

/**
 * iOS `CoreSeatGrid.drawBlock`: each seat a small block of the cube it stands
 * for — lit from above, its own colour carved deeper along the foot, on a
 * soft shadow. An empty seat is a shallow hollow. Yours lifts a little and
 * glows in its colour.
 */
fun DrawScope.drawCoreBlock(rect: Rect, color: Color?, mine: Boolean, dark: Boolean) {
    val radius = rect.width * 0.18f
    val corner = androidx.compose.ui.geometry.CornerRadius(radius)
    if (color == null) {
        drawRoundRect(Color.Black.copy(alpha = if (dark) 0.0f else 0f), rect.topLeft, rect.size, corner)
        drawRoundRect((if (dark) Color.White else Color.Black).copy(alpha = if (dark) 0.07f else 0.05f),
            rect.topLeft, rect.size, corner)
        drawRoundRect(Color.Black.copy(alpha = if (dark) 0.35f else 0.08f), rect.topLeft,
            Size(rect.width, 1.4f), corner)
        return
    }
    val lift = if (mine) -1.5f * density else 0f
    val body = rect.translate(0f, lift)
    // Shadow, wider and in its own colour for yours.
    drawRoundRect((if (mine) color else Color.Black).copy(alpha = if (mine) 0.45f else 0.16f),
        body.topLeft + Offset(0f, (if (mine) 2.5f else 1.2f) * density), body.size, corner)
    val carved = Color(CubeFaces.carved(color.toArgb()))
    drawRoundRect(Brush.verticalGradient(
        0f to lerp(color, Color.White, 0.14f), 0.45f to color, 0.78f to color,
        1f to lerp(color, carved, 0.55f), startY = body.top, endY = body.bottom),
        body.topLeft, body.size, corner)
    drawRoundRect(Color.White.copy(alpha = 0.3f), body.topLeft, Size(body.width, 1.2f * density), corner)
    if (mine) {
        drawRoundRect(Color.White.copy(alpha = 0.9f), body.topLeft + Offset(0.75f, 0.75f),
            Size(body.width - 1.5f, body.height - 1.5f), corner, style = Stroke(1.5f * density))
    }
}

private fun lerp(a: Color, b: Color, t: Float) = Color(
    a.red + (b.red - a.red) * t, a.green + (b.green - a.green) * t, a.blue + (b.blue - a.blue) * t, 1f)
