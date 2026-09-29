package com.roro.futurevoice.widget

import android.content.Context
import android.os.SystemClock
import android.util.TypedValue
import android.widget.RemoteViews
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.LocalContext
import androidx.glance.LocalSize
import androidx.glance.appwidget.AndroidRemoteViews
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.SizeMode
import androidx.glance.appwidget.provideContent
import androidx.glance.background
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.size
import androidx.glance.layout.width
import androidx.glance.text.FontFamily
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import com.roro.futurevoice.R
import java.util.Calendar

/**
 * The streak widget (`StreakWidget`): a pixel-face mascot and the day count,
 * nudging the learner not to break their run. The face's mood is TIME
 * PRESSURE: smiling once today counts, calm while the day is young, anxious
 * in the last three hours before midnight on an unmet streak. Tap opens Talk.
 *
 * iOS adds a timeline entry three hours before midnight so the face turns on
 * its own; here the mood is computed at every draw and the widget redraws on
 * its update period, and the countdown is a Chronometer that ticks by itself.
 */
class StreakWidget : GlanceAppWidget() {

    // EXACT, not Responsive: the pill, the ring and the graph paper are drawn to
    // the tile's real size, and Responsive hands back the breakpoint instead.
    override val sizeMode = SizeMode.Exact

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val snapshot = StudyWidgetSnapshotStore.loadProgress(context)
        val theme = StudyWidgetSnapshotStore.themeIndex(context)
        provideContent { Body(snapshot, theme) }
    }

    @Composable
    private fun Body(s: StudyProgressSnapshot, theme: Int) {
        val context = LocalContext.current
        val size = LocalSize.current
        val compact = size.width < 200.dp
        val now = System.currentTimeMillis()
        val deadline = nextMidnight(now)
        // Only count "today" if the snapshot is FROM today; a stale one after
        // midnight would otherwise read as done. The rule itself is the
        // streak's, decided app-side beside the number it counted.
        val done = isSameDay(s.updatedAt, now) && s.metToday
        val hoursLeft = ((deadline - now).coerceAtLeast(0L)) / 3_600_000.0
        val vivid = WidgetTheme.vivid(theme)
        val face = when {
            done -> StreakFace.HAPPY
            s.streakDays == 0 -> StreakFace.NEUTRAL
            hoursLeft <= 3 -> StreakFace.ANXIOUS
            else -> StreakFace.NEUTRAL
        }
        val faceImage = ImageProvider(faceBitmap(context, face, vivid))
        WidgetSurface(context, theme, size.width, size.height, "futurevoice://talk",
            step = streakPixel) {
            if (compact) {
                Column(
                    GlanceModifier.fillMaxSize().padding(12.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Image(faceImage, contentDescription = null,
                        modifier = GlanceModifier.size(streakPixel * 8))
                    Text("${s.streakDays}", maxLines = 1,
                        style = TextStyle(fontSize = 26.sp, fontFamily = FontFamily.Monospace,
                            color = vivid.provider()))
                    StatusLine(context, s.streakDays, done, deadline, hoursLeft, vivid, 10f)
                }
            } else {
                Row(
                    GlanceModifier.fillMaxSize().padding(16.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Image(faceImage, contentDescription = null,
                        modifier = GlanceModifier.size(streakPixel * 11))
                    Spacer(GlanceModifier.width(16.dp))
                    Box(GlanceModifier.width(1.dp).height(74.dp)
                        .background(Color.White.copy(alpha = 0.12f).provider())) {}
                    Spacer(GlanceModifier.width(16.dp))
                    Column {
                        Text("${s.streakDays}", maxLines = 1,
                            style = TextStyle(fontSize = 40.sp, fontFamily = FontFamily.Monospace,
                                color = vivid.provider()))
                        Text(StudyWidgetSnapshotStore.chrome(context, R.string.day_streak),
                            maxLines = 1,
                            style = TextStyle(fontSize = 16.sp, fontFamily = FontFamily.Monospace,
                                color = Color.White.provider()))
                        Spacer(GlanceModifier.height(4.dp))
                        StatusLine(context, s.streakDays, done, deadline, hoursLeft, vivid, 12f)
                    }
                }
            }
        }
    }

    /** Countdown while the streak is on the line, else a short status. */
    @Composable
    private fun StatusLine(context: Context, streak: Int, done: Boolean, deadline: Long,
                           hoursLeft: Double, vivid: Color, sizeSp: Float) {
        val dim = TextStyle(fontSize = sizeSp.sp, fontFamily = FontFamily.Monospace,
            color = Color.White.copy(alpha = 0.7f).provider())
        when {
            done -> Text(StudyWidgetSnapshotStore.chrome(context, R.string.done_for_today),
                maxLines = 1, style = dim)
            streak == 0 -> Text(StudyWidgetSnapshotStore.chrome(context, R.string.start_your_streak),
                maxLines = 1, style = dim)
            else -> Row(verticalAlignment = Alignment.CenterVertically) {
                val tint = if (hoursLeft <= 3) vivid else Color.White.copy(alpha = 0.85f)
                val views = RemoteViews(context.packageName, R.layout.widget_countdown).apply {
                    val remaining = (deadline - System.currentTimeMillis()).coerceAtLeast(60_000L)
                    setChronometer(R.id.widget_countdown,
                        SystemClock.elapsedRealtime() + remaining, null, true)
                    setChronometerCountDown(R.id.widget_countdown, true)
                    setTextColor(R.id.widget_countdown, tint.toArgb())
                    setTextViewTextSize(R.id.widget_countdown, TypedValue.COMPLEX_UNIT_SP, sizeSp)
                }
                AndroidRemoteViews(views)
                Spacer(GlanceModifier.width(4.dp))
                Text(StudyWidgetSnapshotStore.chrome(context, R.string.left), maxLines = 1,
                    style = dim.copy(color = Color.White.copy(alpha = 0.5f).provider()))
            }
        }
    }

    companion object {
        /** Local midnight strictly after [at] — the streak's daily wire. */
        fun nextMidnight(at: Long): Long = Calendar.getInstance().apply {
            timeInMillis = at
            set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
            add(Calendar.DAY_OF_YEAR, 1)
        }.timeInMillis

        fun isSameDay(a: Long, b: Long): Boolean {
            val ca = Calendar.getInstance().apply { timeInMillis = a }
            val cb = Calendar.getInstance().apply { timeInMillis = b }
            return ca.get(Calendar.YEAR) == cb.get(Calendar.YEAR) &&
                ca.get(Calendar.DAY_OF_YEAR) == cb.get(Calendar.DAY_OF_YEAR)
        }
    }
}

class StreakWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = StreakWidget()
}
