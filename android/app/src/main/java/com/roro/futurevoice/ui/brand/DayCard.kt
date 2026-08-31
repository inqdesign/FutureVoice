package com.roro.futurevoice.ui.brand

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * What goes on a day's card — the day as the app already counts it. Every
 * value is one some screen already shows; the card RESTATES the day, it
 * never computes something of its own (`DayCardData`).
 */
data class DayCardData(
    val date: Long,
    /** Metered talk minutes (`TalkTimeLog`) — the ring's number. */
    val talkMinutes: Int,
    /** Foreground minutes, never less than the talk time. */
    val studyMinutes: Int,
    val streakDays: Int,
    val talks: Int,
    val reviews: Int = 0,
    val shadowTakes: Int = 0,
    /** The day's talks, MAIN one first. Only the first is printed. */
    val topics: List<String> = emptyList(),
) {
    val hasActivity: Boolean get() = talkMinutes > 0 || talks > 0 || studyMinutes > 0

    /** Talk and study always, then whatever else the day has — up to four. */
    val stats: List<Pair<String, String>>
        get() = buildList {
            add("Talk" to "$talkMinutes min")
            add("Study" to "$studyMinutes min")
            if (streakDays > 0) add("Streak" to "$streakDays d")
            if (talks > 0) add("Talks" to "$talks")
            if (reviews > 0) add("Reviews" to "$reviews")
            if (shadowTakes > 0) add("Shadow" to "$shadowTakes")
        }.take(4)
}

enum class DayCardFormat(val width: Int, val height: Int) {
    /** Instagram's tall feed frame, which Threads takes as is. */
    FEED(360, 450),
    SQUARE(360, 360);

    companion object { const val EXPORT_SCALE = 3 }
}

private val INK = Color(20 / 255f, 19 / 255f, 16 / 255f)
private val PAPER = Color(252 / 255f, 251 / 255f, 248 / 255f)

/**
 * The day's card: the place photo full-bleed, the day's topic in the pixel
 * face, talk and study minutes, then the call pill (in the learner's own
 * Futureself theme) stamped with the date, and the URL. Nothing else — a
 * card that has to be READ isn't a card.
 *
 * It is an exported PICTURE, not app chrome, so it wears the brand (ink,
 * paper, the mosaic) rather than system colours — and it is in ENGLISH
 * whatever the app language: it is for a feed, not for the learner, so it
 * has to read the same to everyone it reaches. The one surface where chrome
 * does not follow the learner's choice.
 */
@Composable
fun DayCard(
    data: DayCardData,
    photo: ImageBitmap?,
    modifier: Modifier = Modifier,
    format: DayCardFormat = DayCardFormat.FEED,
    theme: Int = 0,
) {
    val isFeed = format == DayCardFormat.FEED
    val margin = if (isFeed) 24.dp else 21.dp
    Box(
        modifier.size(format.width.dp, format.height.dp).background(INK),
        contentAlignment = Alignment.BottomStart,
    ) {
        photo?.let {
            Image(it, contentDescription = null, contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize())
        }
        Box(Modifier.fillMaxSize().background(Brush.verticalGradient(
            colorStops = if (isFeed) arrayOf(
                0f to INK.copy(alpha = 0.18f), 0.26f to INK.copy(alpha = 0f),
                0.40f to INK.copy(alpha = 0f), 0.72f to INK.copy(alpha = 0.86f),
                1f to INK.copy(alpha = 0.94f))
            else arrayOf(
                0f to INK.copy(alpha = 0.16f), 0.30f to INK.copy(alpha = 0f),
                0.72f to INK.copy(alpha = 0.88f), 1f to INK.copy(alpha = 0.94f)))))

        Column(
            Modifier.fillMaxWidth().padding(horizontal = margin)
                .padding(bottom = if (isFeed) 26.dp else 21.dp),
            verticalArrangement = Arrangement.spacedBy(if (isFeed) 15.dp else 11.dp),
        ) {
            data.topics.firstOrNull()?.let { topic ->
                Text(topic, color = PAPER, maxLines = 3, overflow = TextOverflow.Ellipsis,
                    style = DisplayFace.style(topic, TextStyle(
                        fontSize = (if (isFeed) 35 else 29).sp, lineHeight = (if (isFeed) 40 else 34).sp)))
            }
            // Up to four numbers — the value in the pixel face, the label
            // small and tracked beneath, like the stat row under a run.
            Row(Modifier.fillMaxWidth()) {
                data.stats.forEach { (label, value) ->
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Text(value, color = PAPER, style = DisplayFace.style(value,
                            TextStyle(fontSize = (if (isFeed) 15 else 13).sp)))
                        Text(label.uppercase(), color = PAPER.copy(alpha = 0.72f),
                            style = TextStyle(fontSize = (if (isFeed) 7.3f else 6.7f).sp,
                                letterSpacing = 1.sp))
                    }
                }
            }
            Spacer(Modifier.height(if (isFeed) 10.dp else 8.dp))
            Box(Modifier.fillMaxWidth().height(0.5.dp).background(PAPER.copy(alpha = 0.28f)))
            Row(Modifier.fillMaxWidth().padding(top = if (isFeed) 10.dp else 8.dp),
                verticalAlignment = Alignment.CenterVertically) {
                DatePill(data.date, theme, isFeed)
                Spacer(Modifier.weight(1f))
                Column(horizontalAlignment = Alignment.End,
                    verticalArrangement = Arrangement.spacedBy(3.dp)) {
                    Text("Learn a language from your fluent self.", color = PAPER,
                        style = DisplayFace.style("Learn",
                            TextStyle(fontSize = (if (isFeed) 8.7f else 8f).sp)))
                    Text("nawana.app", color = PAPER.copy(alpha = 0.72f),
                        style = TextStyle(fontSize = (if (isFeed) 8.7f else 8f).sp,
                            letterSpacing = 1.2.sp))
                }
            }
        }
    }
}

/**
 * The call screen's pill, shrunk to a badge and carrying the DATE — the
 * thing the learner talked to, stamped with the day. Quiet on purpose: low
 * drive and a steep colour falloff leave most cells dark so the date reads
 * and the theme shows as an accent, not a flood. Dark palette whatever the
 * phone's mode: the card's ground is ink.
 */
@Composable
private fun DatePill(date: Long, theme: Int, isFeed: Boolean) {
    val w = if (isFeed) 88.dp else 80.dp
    val h = if (isFeed) 32.dp else 29.dp
    Box(Modifier.width(w).height(h).clip(RoundedCornerShape(percent = 50)),
        contentAlignment = Alignment.Center) {
        FutureselfPixels(
            modifier = Modifier.fillMaxSize(), theme = theme,
            mode = FutureselfMode.SPEAKING, level = 0.42f, time = 3.2f,
            cell = 6.4f * 3f, colourFalloff = 1.25f, maxStep = 3, dark = true)
        Box(Modifier.fillMaxSize().background(INK.copy(alpha = 0.18f)))
        val text = SimpleDateFormat("MMM d", Locale.US).format(Date(date))
        Text(text, color = PAPER, style = DisplayFace.style(text,
            TextStyle(fontSize = (if (isFeed) 10.7f else 9.7f).sp)))
    }
}
