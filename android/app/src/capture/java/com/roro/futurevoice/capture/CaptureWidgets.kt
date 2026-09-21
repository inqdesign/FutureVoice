package com.roro.futurevoice.capture

import android.content.Context
import android.widget.FrameLayout
import android.widget.RemoteViews
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.glance.appwidget.compose
import com.roro.futurevoice.ui.brand.AppSurfaces
import com.roro.futurevoice.widget.StudyWidget
import com.roro.futurevoice.widget.StudyWidgetRefresher
import com.roro.futurevoice.widget.StudyWidgetSection

/**
 * Capture modes for the Widgets area. This file owns exactly these iOS modes:
 *
 *   widget
 *   widget-book
 *   widget-progress
 *   widget-streak
 *   widget-freetalk
 *   widget-freetalk-themes
 *
 * A mode is either WIRED (the real Android screen over `CaptureSeed` data),
 * NOT PORTED (the Android app has no such screen or feature yet — the reason
 * names the master-plan item), or absent (still NOT WIRED in the gallery).
 *
 * A home-screen widget can't be shown inside the app, so `widget` runs the
 * REAL Glance widget ([StudyWidget]) through Glance's own composer into the
 * same `RemoteViews` the launcher would get, and inflates that here at the
 * widget's real sizes. Its data is the real path too: `seedVocab`, then the
 * app's own `StudyWidgetRefresher` writes the snapshot the widget reads.
 */
object CaptureWidgets {
    val wired: Map<String, @Composable (Context) -> Unit> = mapOf(
        "widget" to { context -> StudyWidgetGallery(context) },
    )

    private const val NO_WIDGET = "Android ships only the Words and Expressions list widgets"

    /** mode → why Android can't show it yet (name the master-plan item). */
    val notPorted: Map<String, String> = mapOf(
        "widget-book" to "$NO_WIDGET — no Continue (book) widget; 4.7",
        "widget-progress" to "$NO_WIDGET — no Progress widget; 4.7",
        "widget-streak" to "$NO_WIDGET — no Streak widget; 4.7",
        "widget-freetalk" to "$NO_WIDGET — no Free Talk widget; 4.7",
        "widget-freetalk-themes" to "$NO_WIDGET — no Free Talk widget (or its themes); 4.7",
    )

    /** The declared minimum (`widget_*_info.xml`: 180×110 dp, 3×2 cells) and a
     *  full-width 4×2, the same width iOS's medium card is shot at. */
    private val sizes = listOf(DpSize(180.dp, 110.dp), DpSize(338.dp, 158.dp))

    @Composable
    private fun StudyWidgetGallery(context: Context) {
        val views by produceState<List<Pair<DpSize, RemoteViews>>?>(null) {
            CaptureSeed.once("widget") {
                CaptureSeed.seedVocab(context)
                StudyWidgetRefresher.refresh(context)
            }
            value = StudyWidgetSection.entries.flatMap { section ->
                sizes.map { size -> size to StudyWidget(section).compose(context, size = size) }
            }
        }
        Column(
            Modifier.fillMaxSize().background(AppSurfaces.ground)
                .verticalScroll(rememberScrollState()).padding(24.dp),
            verticalArrangement = Arrangement.spacedBy(18.dp),
        ) {
            val list = views
            if (list == null) {
                Text("…", style = MaterialTheme.typography.bodyMedium)
                return@Column
            }
            list.forEach { (size, rv) ->
                AndroidView(
                    factory = { ctx -> FrameLayout(ctx).apply { addView(rv.apply(ctx, this)) } },
                    modifier = Modifier.size(size.width, size.height),
                )
            }
        }
    }
}
