package com.roro.futurevoice.widget

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
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
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.height
import androidx.glance.layout.size
import androidx.glance.layout.width
import androidx.glance.text.FontFamily
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import com.roro.futurevoice.R

/**
 * The Free Talk widget (`FreeTalkWidget`): one tap starts a call. It wears a
 * STATIC Futureself pill in the learner's chosen palette — the live surface
 * can't run on a home screen — with "Let's talk" inside, the words the app's
 * ring carries. The tap deep-links `futurevoice://freetalk`, which the root
 * sends through the SAME billing gate the in-app ring uses.
 *
 * The pill is a whole number of cells each way and the graph paper behind it
 * takes its lattice from the pill (`FutureselfLattice`), so the two read as
 * one display.
 */
class FreeTalkWidget : GlanceAppWidget() {

    override val sizeMode = SizeMode.Exact

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val theme = StudyWidgetSnapshotStore.themeIndex(context)
        provideContent { Body(theme) }
    }

    @Composable
    private fun Body(theme: Int) {
        val context = LocalContext.current
        val size = LocalSize.current
        val compact = size.width < 200.dp
        // The bezel eats 4dp a side; the lattice is laid in what's inside it.
        val w = size.width.value - 8f
        val h = size.height.value - 8f
        val (pw, ph) = FutureselfLattice.surfaceSize(w, h, compact)
        val phase = FutureselfLattice.phase(w, h, compact)
        WidgetSurface(context, theme, size.width, size.height, "futurevoice://freetalk",
            step = FUTURESELF_CELL_DP.dp, phase = phase) {
            Box(GlanceModifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Box(GlanceModifier.width(pw.dp).height(ph.dp), contentAlignment = Alignment.Center) {
                    Image(ImageProvider(freeTalkPillBitmap(context, theme, pw, ph, compact)),
                        contentDescription = null, modifier = GlanceModifier.size(pw.dp, ph.dp))
                    Text(StudyWidgetSnapshotStore.chrome(context, R.string.let_s_talk), maxLines = 1,
                        style = TextStyle(fontSize = (if (compact) 16 else 24).sp,
                            fontFamily = FontFamily.Monospace, fontWeight = FontWeight.Bold,
                            color = Color.White.provider()))
                }
            }
        }
    }
}

class FreeTalkWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = FreeTalkWidget()
}
