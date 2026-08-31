package com.roro.futurevoice.widget

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.compose.runtime.Composable
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.GlanceTheme
import androidx.glance.appwidget.action.actionStartActivity
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.provideContent
import androidx.glance.background
import androidx.glance.layout.Alignment
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.padding
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import androidx.glance.currentState
import androidx.glance.appwidget.cornerRadius
import androidx.glance.layout.height
import androidx.glance.unit.Dimension
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/**
 * A study widget — one per section (`FutureVoiceWidget`): a list of what the
 * learner is studying right now, with the collection's size as the badge.
 *
 * It only ever READS the snapshot the app wrote; the stores are never
 * touched from here, so a home-screen redraw can't be blocked on a decode.
 * The chrome speaks the APP's language, not the phone's — mirrored into the
 * snapshot store for the same reason iOS mirrors it into the App Group.
 */
class StudyWidget(private val section: StudyWidgetSection) : GlanceAppWidget() {

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val snapshot = StudyWidgetSnapshotStore.load(context, section)
        provideContent {
            GlanceTheme {
                Body(snapshot)
            }
        }
    }

    @Composable
    private fun Body(snapshot: StudyWidgetSnapshot) {
        // The tap deep-links into the app on the same scheme iOS uses.
        val open = actionStartActivity(
            Intent(Intent.ACTION_VIEW, Uri.parse(section.deepLink)).apply {
                setPackage("com.roro.futurevoice")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            })
        Column(
            GlanceModifier.fillMaxSize()
                .background(GlanceTheme.colors.widgetBackground)
                .cornerRadius(16.dp)
                .padding(12.dp)
                .clickable(open),
        ) {
            Row(GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Text(
                    if (section == StudyWidgetSection.WORDS) "Words" else "Expressions",
                    style = TextStyle(fontSize = 13.sp, fontWeight = FontWeight.Medium,
                        color = GlanceTheme.colors.onSurfaceVariant),
                    modifier = GlanceModifier.defaultWeight(),
                )
                if (snapshot.total > 0) {
                    Text("${snapshot.total}",
                        style = TextStyle(fontSize = 13.sp, fontWeight = FontWeight.Bold,
                            color = GlanceTheme.colors.primary))
                }
            }
            Spacer(GlanceModifier.height(6.dp))
            if (snapshot.items.isEmpty()) {
                Text("Nothing to study yet.",
                    style = TextStyle(fontSize = 13.sp,
                        color = GlanceTheme.colors.onSurfaceVariant))
            } else {
                snapshot.items.take(6).forEach { item ->
                    Row(GlanceModifier.fillMaxWidth().padding(vertical = 3.dp)) {
                        Text(item.text,
                            style = TextStyle(fontSize = 14.sp,
                                color = GlanceTheme.colors.onSurface),
                            modifier = GlanceModifier.defaultWeight(), maxLines = 1)
                        if (section.showsNote && item.note.isNotBlank()) {
                            Text(item.note,
                                style = TextStyle(fontSize = 11.sp,
                                    color = GlanceTheme.colors.onSurfaceVariant))
                        }
                    }
                }
            }
        }
    }
}

class WordsWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = StudyWidget(StudyWidgetSection.WORDS)
}

class ExpressionsWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = StudyWidget(StudyWidgetSection.EXPRESSIONS)
}
