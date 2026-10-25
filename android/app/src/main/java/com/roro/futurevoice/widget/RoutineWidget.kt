package com.roro.futurevoice.widget

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Bedtime
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.VectorGroup
import androidx.compose.ui.graphics.vector.VectorNode
import androidx.compose.ui.graphics.vector.VectorPath
import androidx.compose.ui.graphics.vector.toPath
import androidx.compose.ui.graphics.asAndroidPath
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.LocalContext
import androidx.glance.LocalSize
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.SizeMode
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.provideContent
import androidx.glance.background
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.size
import androidx.glance.layout.width
import androidx.glance.text.FontFamily
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import com.roro.futurevoice.data.StudyPlan
import com.roro.futurevoice.ui.icon

/**
 * The routine widget (iOS `RoutineWidget`, a0836bbe): today's planned blocks,
 * and while one's time is on, that one said out loud ("Ready to review"). The
 * big line is always a block's name and the state is the line under it, so
 * the places never move when the state does. Small: the one thing that
 * matters now. Medium: the day as a list, now marked. A tap opens that
 * block's door (`futurevoice://routine?kind=…`), the one its reminder opens.
 *
 * The face changes at every block's start and end with the app closed
 * ([RoutineWidgetTicker]); done ticks arrive when the app writes the
 * snapshot, which every rep does. iOS also has a lock-screen size; Android
 * phones have no lock-screen widgets.
 */
class RoutineWidget : GlanceAppWidget() {

    override val sizeMode = SizeMode.Exact

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val snapshot = RoutineWidgetStore.load(context)
        val theme = StudyWidgetSnapshotStore.themeIndex(context)
        provideContent { Body(snapshot, theme) }
    }

    @Composable
    private fun Body(snap: RoutineWidgetSnapshot, theme: Int) {
        val context = LocalContext.current
        val size = LocalSize.current
        val compact = size.width < 200.dp
        val now = System.currentTimeMillis()
        val vivid = WidgetTheme.vivid(theme)
        val blocks = snap.blocks(now)
        WidgetSurface(context, theme, size.width, size.height, snap.deepLink(now)) {
            Column(GlanceModifier.fillMaxSize().padding(14.dp)) {
                Text(snap.label("title"), maxLines = 1,
                    style = TextStyle(fontSize = 12.sp, fontFamily = FontFamily.Monospace,
                        color = Color.White.copy(alpha = 0.85f).provider()))
                Spacer(GlanceModifier.height(6.dp))
                if (compact) {
                    Spacer(GlanceModifier.defaultWeight())
                    Hero(context, snap, now, vivid)
                } else if (blocks.isEmpty()) {
                    Spacer(GlanceModifier.defaultWeight())
                    DayOver(context, snap, now, vivid)
                    Spacer(GlanceModifier.defaultWeight())
                } else {
                    visibleRows(snap, now).forEachIndexed { i, b ->
                        if (i > 0) Spacer(GlanceModifier.height(2.dp))
                        BlockRow(context, snap, b, now, vivid)
                    }
                    Spacer(GlanceModifier.defaultWeight())
                }
            }
        }
    }

    /** Every state of the small widget is the same three lines — icon, one
     *  large line, one caption — so only the words change. */
    @Composable
    private fun Hero(context: Context, snap: RoutineWidgetSnapshot, now: Long, vivid: Color) {
        val nowBlock = snap.now(now)
        val next = snap.next(now)
        when {
            // The block's name stays; the state is the caption.
            nowBlock != null -> HeroLayout(context, kindIcon(nowBlock.kind), routineTint(nowBlock.kind),
                nowBlock.title, nowBlock.nowLine, vivid)
            next != null -> {
                val whenText = if (next.anytime) snap.label("anytime")
                    else "${snap.label(if (next.start <= now) "today" else "next")} · ${routineClock(next.start)}"
                HeroLayout(context, kindIcon(next.kind), routineTint(next.kind), next.title, whenText, vivid)
            }
            else -> DayOver(context, snap, now, vivid)
        }
    }

    /** Nothing left today. Still a block's name on top, the state below: a
     *  finished day shows its last block, a rest day tomorrow's first. Only a
     *  day with nothing planned anywhere has no block to name. */
    @Composable
    private fun DayOver(context: Context, snap: RoutineWidgetSnapshot, now: Long, vivid: Color) {
        val last = snap.blocks(now).lastOrNull()
        val first = snap.tomorrowFirst(now)
        when {
            last != null -> HeroLayout(context, kindIcon(last.kind), routineTint(last.kind),
                last.title, snap.label("allDone"), vivid)
            first != null -> HeroLayout(context, kindIcon(first.kind), routineTint(first.kind), first.title,
                "${snap.label("tomorrow")} · ${if (first.anytime) snap.label("anytime") else routineClock(first.start)}",
                vivid)
            else -> HeroLayout(context, Icons.Filled.Bedtime, vivid.copy(alpha = 0.85f),
                snap.label("empty"), null, vivid)
        }
    }

    /** Fixed slots: the words change, the places never do. One line for the
     *  large text and a caption line kept even when it is empty. */
    @Composable
    private fun HeroLayout(context: Context, icon: ImageVector, tint: Color, main: String,
                           caption: String?, vivid: Color) {
        Column {
            Box(GlanceModifier.height(26.dp), contentAlignment = Alignment.CenterStart) {
                Image(ImageProvider(vectorBitmap(context, icon, 22f, tint)), contentDescription = null,
                    modifier = GlanceModifier.size(22.dp))
            }
            Box(GlanceModifier.height(22.dp), contentAlignment = Alignment.CenterStart) {
                Text(main, maxLines = 1,
                    style = TextStyle(fontSize = 17.sp, fontFamily = FontFamily.Monospace,
                        color = vivid.provider()))
            }
            Box(GlanceModifier.height(14.dp), contentAlignment = Alignment.CenterStart) {
                Text(caption ?: " ", maxLines = 1,
                    style = TextStyle(fontSize = 11.sp, fontFamily = FontFamily.Monospace,
                        color = Color.White.copy(alpha = 0.6f).provider()))
            }
        }
    }

    /** Four rows at most, kept around now: the block due or next, with the
     *  one before it when there is room. */
    private fun visibleRows(snap: RoutineWidgetSnapshot, now: Long): List<RoutineWidgetBlock> {
        val blocks = snap.blocks(now)
        val limit = 4
        if (blocks.size <= limit) return blocks
        // A finished day keeps its last rows on screen.
        val focus = (snap.now(now) ?: snap.next(now))?.let { f -> blocks.indexOfFirst { it.id == f.id } }
            ?.takeIf { it >= 0 } ?: (blocks.size - 1)
        val start = maxOf(0, minOf(focus - 1, blocks.size - limit))
        return blocks.subList(start, start + limit)
    }

    @Composable
    private fun BlockRow(context: Context, snap: RoutineWidgetSnapshot, b: RoutineWidgetBlock,
                         now: Long, vivid: Color) {
        val isNow = b.isNow(now)
        val lapsed = !b.done && !b.anytime && b.end <= now
        Row(
            GlanceModifier.fillMaxWidth().height(24.dp)
                .cornerRadius(8.dp)
                .background((if (isNow) vivid.copy(alpha = 0.14f) else Color.Transparent).provider())
                .padding(horizontal = 6.dp)
                .clickable(openLink(b.deepLink)),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            // The time even for the block due now: the row's highlight and its
            // line already say "now".
            Text(if (b.anytime) snap.label("anytime") else routineClock(b.start), maxLines = 1,
                modifier = GlanceModifier.width(44.dp),
                style = TextStyle(fontSize = 11.sp, fontFamily = FontFamily.Monospace,
                    color = (if (isNow) vivid else Color.White.copy(alpha = 0.55f)).provider()))
            Box(GlanceModifier.width(16.dp), contentAlignment = Alignment.Center) {
                Image(ImageProvider(vectorBitmap(context, kindIcon(b.kind), 12f,
                    if (lapsed) Color.White.copy(alpha = 0.35f) else routineTint(b.kind))),
                    contentDescription = null, modifier = GlanceModifier.size(12.dp))
            }
            Spacer(GlanceModifier.width(8.dp))
            Text(b.title, maxLines = 1, modifier = GlanceModifier.defaultWeight(),
                style = TextStyle(fontSize = 12.sp, fontFamily = FontFamily.Monospace,
                    color = (if (isNow) vivid else Color.White.copy(alpha = if (lapsed) 0.4f else 0.85f)).provider()))
            Spacer(GlanceModifier.width(4.dp))
            Image(ImageProvider(routineRingBitmap(context, if (b.done) 1.0 else (b.progress ?: 0.0), lapsed)),
                contentDescription = null, modifier = GlanceModifier.size(15.dp))
        }
    }

    private fun kindIcon(raw: String): ImageVector =
        (StudyPlan.Kind.entries.firstOrNull { it.raw == raw } ?: StudyPlan.Kind.REVIEW).icon()
}

class RoutineWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = RoutineWidget()
}

private fun density(context: Context) = context.resources.displayMetrics.density

/** A Material icon drawn into a bitmap in one colour — RemoteViews can't
 *  take an ImageVector. */
internal fun vectorBitmap(context: Context, vector: ImageVector, sizeDp: Float, tint: Color): Bitmap {
    val px = (sizeDp * density(context)).toInt().coerceIn(1, 400)
    val bmp = Bitmap.createBitmap(px, px, Bitmap.Config.ARGB_8888)
    val c = Canvas(bmp)
    c.scale(px / vector.viewportWidth, px / vector.viewportHeight)
    val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = tint.toArgb(); style = Paint.Style.FILL }
    fun draw(node: VectorNode) {
        when (node) {
            is VectorGroup -> node.forEach { draw(it) }
            is VectorPath -> c.drawPath(node.pathData.toPath().asAndroidPath(), paint)
        }
    }
    draw(vector.root)
    return bmp
}

/** Activity's ring on the widget's dark ground: empty circle → filling green
 *  ring → green tick (iOS `RoutineRing`). */
internal fun routineRingBitmap(context: Context, progress: Double, faded: Boolean): Bitmap {
    val green = Color(0xFF34C759)
    if (progress >= 1) return vectorBitmap(context, Icons.Filled.CheckCircle, 15f, green)
    val d = density(context)
    val s = (15 * d).toInt().coerceAtLeast(1)
    val bmp = Bitmap.createBitmap(s, s, Bitmap.Config.ARGB_8888)
    val c = Canvas(bmp)
    val track = 1.5f * d
    val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE; strokeWidth = track
        color = Color.White.copy(alpha = if (faded) 0.2f else 0.35f).toArgb()
    }
    c.drawArc(RectF(track / 2, track / 2, s - track / 2, s - track / 2), 0f, 360f, false, paint)
    if (progress > 0) {
        val line = 2f * d
        val inset = d + line / 2
        paint.strokeWidth = line; paint.strokeCap = Paint.Cap.ROUND; paint.color = green.toArgb()
        c.drawArc(RectF(inset, inset, s - inset, s - inset), -90f, (360f * progress).toFloat(), false, paint)
    }
    return bmp
}

