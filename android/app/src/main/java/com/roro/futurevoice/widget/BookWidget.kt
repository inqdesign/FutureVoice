package com.roro.futurevoice.widget

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
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
import androidx.glance.appwidget.LinearProgressIndicator
import androidx.glance.appwidget.SizeMode
import androidx.glance.appwidget.provideContent
import androidx.glance.layout.Alignment
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
import androidx.glance.text.TextAlign
import androidx.glance.text.TextStyle
import com.roro.futurevoice.R

/**
 * The Continue widget (`BookWidget`): the one book the learner is mid-way
 * through — Talk or Watch — with its mastery bar, tapping straight into that
 * book's page. With nothing in progress it says so and opens Practice.
 */
class BookWidget : GlanceAppWidget() {

    override val sizeMode = SizeMode.Exact

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val snapshot = StudyWidgetSnapshotStore.loadBook(context)
        val theme = StudyWidgetSnapshotStore.themeIndex(context)
        provideContent { Body(snapshot, theme) }
    }

    @Composable
    private fun Body(s: StudyBookSnapshot, theme: Int) {
        val context = LocalContext.current
        val size = LocalSize.current
        val compact = size.width < 200.dp
        val vivid = WidgetTheme.vivid(theme)
        WidgetSurface(context, theme, size.width, size.height, s.deepLink) {
            Column(
                GlanceModifier.fillMaxSize().padding(if (compact) 12.dp else 15.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Text(StudyWidgetSnapshotStore.chrome(context, R.string.studying), maxLines = 1,
                    style = TextStyle(fontSize = (if (compact) 11 else 13).sp,
                        fontFamily = FontFamily.Monospace,
                        color = Color.White.copy(alpha = 0.85f).provider()))
                if (s.hasBook) {
                    Column(
                        GlanceModifier.fillMaxWidth().defaultWeight(),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(s.title, maxLines = if (compact) 2 else 3,
                            style = TextStyle(fontSize = (if (compact) 14 else 18).sp,
                                fontFamily = FontFamily.Monospace, textAlign = TextAlign.Center,
                                color = vivid.provider()))
                        if (!compact && s.subtitle.isNotEmpty()) {
                            Spacer(GlanceModifier.height(5.dp))
                            Text(s.subtitle, maxLines = 1,
                                style = TextStyle(fontSize = 12.sp, fontFamily = FontFamily.Monospace,
                                    color = Color.White.copy(alpha = 0.55f).provider()))
                        }
                    }
                    val progress = if (s.total == 0) 0f
                        else (s.mastered.toFloat() / s.total).coerceAtMost(1f)
                    LinearProgressIndicator(
                        progress = progress,
                        modifier = GlanceModifier.fillMaxWidth().height(6.dp),
                        color = vivid.provider(),
                        backgroundColor = Color.White.copy(alpha = 0.14f).provider(),
                    )
                    Spacer(GlanceModifier.height(5.dp))
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text("${s.mastered}/${s.total}",
                            style = TextStyle(fontSize = (if (compact) 12 else 14).sp,
                                fontFamily = FontFamily.Monospace, color = vivid.provider()))
                        Spacer(GlanceModifier.width(5.dp))
                        Text(StudyWidgetSnapshotStore.chrome(context, R.string.mastered_84d9a8),
                            maxLines = 1,
                            style = TextStyle(fontSize = (if (compact) 11 else 12).sp,
                                fontFamily = FontFamily.Monospace,
                                color = Color.White.copy(alpha = 0.55f).provider()))
                    }
                } else {
                    Column(
                        GlanceModifier.fillMaxWidth().defaultWeight(),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Image(ImageProvider(R.drawable.widget_ic_books), contentDescription = null,
                            modifier = GlanceModifier.size(if (compact) 24.dp else 30.dp),
                            colorFilter = ColorFilter.tint(vivid.copy(alpha = 0.85f).provider()))
                        Spacer(GlanceModifier.height(8.dp))
                        Text(StudyWidgetSnapshotStore.chrome(context, R.string.nothing_in_progress),
                            style = TextStyle(fontSize = (if (compact) 12 else 14).sp,
                                fontFamily = FontFamily.Monospace, textAlign = TextAlign.Center,
                                color = Color.White.copy(alpha = 0.6f).provider()))
                    }
                }
            }
        }
    }
}

class BookWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = BookWidget()
}
