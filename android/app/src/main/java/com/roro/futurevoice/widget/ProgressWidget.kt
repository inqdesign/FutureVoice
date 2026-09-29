package com.roro.futurevoice.widget

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.ColorFilter
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.LocalContext
import androidx.glance.LocalSize
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.SizeMode
import androidx.glance.appwidget.provideContent
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
import com.roro.futurevoice.R

/**
 * The Progress widget (`ProgressWidget`): today's goal ring, the streak, the
 * review backlog and what is being studied — the same deterministic numbers
 * the app shows, written app-side. Tap opens Practice.
 */
class ProgressWidget : GlanceAppWidget() {

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
        val vivid = WidgetTheme.vivid(theme)
        val off = Color.White.copy(alpha = 0.4f)
        WidgetSurface(context, theme, size.width, size.height, "futurevoice://practice") {
            Column(
                GlanceModifier.fillMaxSize().padding(if (compact) 12.dp else 15.dp),
                horizontalAlignment = if (compact) Alignment.CenterHorizontally else Alignment.Start,
            ) {
                Text(StudyWidgetSnapshotStore.chrome(context, R.string.studying), maxLines = 1,
                    modifier = GlanceModifier.fillMaxWidth(),
                    style = TextStyle(fontSize = (if (compact) 11 else 13).sp,
                        fontFamily = FontFamily.Monospace,
                        textAlign = androidx.glance.text.TextAlign.Center,
                        color = Color.White.copy(alpha = 0.85f).provider()))
                Spacer(GlanceModifier.height(if (compact) 6.dp else 8.dp))
                if (compact) {
                    Column(GlanceModifier.fillMaxWidth().defaultWeight(),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalAlignment = Alignment.CenterVertically) {
                        // As big as the tile allows under the header and the stat row (iOS 72).
                        val ring = minOf(90f, size.width.value - 24f, size.height.value - 90f)
                            .coerceAtLeast(48f).dp
                        Ring(context, s, vivid, ring, 7f)
                        Spacer(GlanceModifier.height(6.dp))
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            MiniStat(R.drawable.widget_ic_flame, s.streakDays,
                                if (s.streakDays > 0) vivid else off)
                            Spacer(GlanceModifier.width(14.dp))
                            MiniStat(R.drawable.widget_ic_checklist, s.dueCount,
                                if (s.dueCount > 0) vivid else off)
                        }
                    }
                } else {
                    Row(GlanceModifier.fillMaxWidth().defaultWeight(),
                        verticalAlignment = Alignment.CenterVertically) {
                        Ring(context, s, vivid, minOf(92f, size.height.value - 60f).coerceAtLeast(56f).dp, 9f)
                        Spacer(GlanceModifier.width(16.dp))
                        Column {
                            StatRow(R.drawable.widget_ic_flame, "${s.streakDays}",
                                StudyWidgetSnapshotStore.chrome(context, R.string.day_streak),
                                if (s.streakDays > 0) vivid else off)
                            Spacer(GlanceModifier.height(8.dp))
                            StatRow(R.drawable.widget_ic_checklist, "${s.dueCount}",
                                StudyWidgetSnapshotStore.chrome(context, R.string.widget_to_review),
                                if (s.dueCount > 0) vivid else off)
                            Spacer(GlanceModifier.height(8.dp))
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Icon(R.drawable.widget_ic_book, vivid, 13.dp)
                                Spacer(GlanceModifier.width(8.dp))
                                Value("${s.studyingWords}", vivid)
                                Spacer(GlanceModifier.width(4.dp))
                                Label(StudyWidgetSnapshotStore.chrome(context, R.string.words_efb893))
                                Spacer(GlanceModifier.width(8.dp))
                                Value("${s.studyingExpressions}", vivid)
                                Spacer(GlanceModifier.width(4.dp))
                                Label(StudyWidgetSnapshotStore.chrome(context, R.string.phrases_3895d1))
                            }
                        }
                    }
                }
            }
        }
    }

    /** Today's goal ring with the minutes inside (`ProgressCard.ring`). */
    @Composable
    private fun Ring(context: Context, s: StudyProgressSnapshot, vivid: Color, size: Dp, line: Float) {
        val progress = (s.todaySeconds.toDouble() / (maxOf(1, s.goalMinutes) * 60)).coerceAtMost(1.0)
        Box(GlanceModifier.size(size), contentAlignment = Alignment.Center) {
            Image(ImageProvider(ringBitmap(context, size.value, line, progress, vivid)),
                contentDescription = null, modifier = GlanceModifier.size(size))
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text("${s.todaySeconds / 60}", maxLines = 1,
                    style = TextStyle(fontSize = (size.value * 0.30f).sp,
                        fontFamily = FontFamily.Monospace, color = vivid.provider()))
                Text("/ ${s.goalMinutes}m", maxLines = 1,
                    style = TextStyle(fontSize = (size.value * 0.13f).sp,
                        fontFamily = FontFamily.Monospace,
                        color = Color.White.copy(alpha = 0.6f).provider()))
            }
        }
    }

    @Composable
    private fun StatRow(icon: Int, value: String, label: String, tint: Color) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(icon, tint, 13.dp)
            Spacer(GlanceModifier.width(8.dp))
            Value(value, tint)
            Spacer(GlanceModifier.width(6.dp))
            Label(label)
        }
    }

    @Composable
    private fun MiniStat(icon: Int, value: Int, tint: Color) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(icon, tint, 11.dp)
            Spacer(GlanceModifier.width(4.dp))
            Text("$value", style = TextStyle(fontSize = 14.sp, fontFamily = FontFamily.Monospace,
                color = tint.provider()))
        }
    }

    @Composable
    private fun Icon(res: Int, tint: Color, size: Dp) =
        Image(ImageProvider(res), contentDescription = null, modifier = GlanceModifier.size(size),
            colorFilter = ColorFilter.tint(tint.provider()))

    @Composable
    private fun Value(text: String, tint: Color) =
        Text(text, maxLines = 1, style = TextStyle(fontSize = 16.sp,
            fontFamily = FontFamily.Monospace, color = tint.provider()))

    @Composable
    private fun Label(text: String) =
        Text(text, maxLines = 1, style = TextStyle(fontSize = 12.sp,
            fontFamily = FontFamily.Monospace, color = Color.White.copy(alpha = 0.55f).provider()))
}

class ProgressWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = ProgressWidget()
}
