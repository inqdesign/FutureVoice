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
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
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
    /** Everything else done that day, each in the unit the app counts it in
     *  (only a talk is measured in minutes). Null on snapshots written before
     *  2026-11-10; those days list what they have (iOS `DayCardData`). */
    val sayItAgainRuns: Int? = null,
    val speechTakes: Int? = null,
    /** Podcast episodes and situations heard in the player. */
    val listens: Int? = null,
    val reads: Int? = null,
    val scenes: Int? = null,
    /** Word and expression cards worked through. */
    val words: Int? = null,
) {
    val hasActivity: Boolean get() = talkMinutes > 0 || talks > 0 || studyMinutes > 0 || lines.isNotEmpty()

    /** The list at the card's bottom left: everything done that day, one
     *  line each, a zero never printed. Talk is minutes (metered); the rest
     *  are counts, because that is what the app records for them. */
    val lines: List<Pair<String, String>>
        get() {
            fun n(count: Int?, one: String, many: String): String? =
                if (count != null && count > 0) "$count ${if (count == 1) one else many}" else null
            return listOf(
                "Talk" to (if (talkMinutes > 0) "$talkMinutes min" else n(talks, "talk", "talks")),
                "Say it again" to n(sayItAgainRuns, "run", "runs"),
                "Speech" to n(speechTakes, "take", "takes"),
                "Listening" to n(listens, "episode", "episodes"),
                "Reading" to n(reads, "article", "articles"),
                "Scenes" to n(scenes, "scene", "scenes"),
                "Shadowing" to n(shadowTakes, "take", "takes"),
                "Review" to n(reviews, "card", "cards"),
                "Words" to n(words, "word", "words"),
            ).mapNotNull { (label, value) -> value?.let { label to it } }
        }
}

enum class DayCardFormat(val width: Int, val height: Int, val maxLines: Int) {
    /** 9:16 — the tall card, with room for the whole day's list (iOS 2026-11-10). */
    STORY(360, 640, 9),
    /** Instagram's tall feed frame, which Threads takes as is. */
    FEED(360, 450, 5),
    SQUARE(360, 360, 3);

    companion object { const val EXPORT_SCALE = 3 }
}

private val INK = Color(20 / 255f, 19 / 255f, 16 / 255f)
private val PAPER = Color(252 / 255f, 251 / 255f, 248 / 255f)

/**
 * The day's card: the place photo full-bleed, the day's topic in the pixel
 * face, talk and study minutes, the nawana mark with the date, and the URL. Nothing else — a
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
) {
    // A picture of fixed size, so its type is pinned as iOS pins Dynamic Type
    // on `DayCardView.render`: at a 1.3 font the numbers row ran together
    // ("25 min7 days").
    val d = androidx.compose.ui.platform.LocalDensity.current
    androidx.compose.runtime.CompositionLocalProvider(
        androidx.compose.ui.platform.LocalDensity provides androidx.compose.ui.unit.Density(d.density, 1f),
    ) { DayCardBody(data, photo, modifier, format) }
}

@Composable
private fun DayCardBody(
    data: DayCardData,
    photo: ImageBitmap?,
    modifier: Modifier,
    format: DayCardFormat,
) {
    val isFeed = format != DayCardFormat.SQUARE
    val isStory = format == DayCardFormat.STORY
    val margin = if (isFeed) 24.dp else 21.dp
    // Top: the mark, then the date and the streak. Bottom: the headline, then the day's
    // list at the left with the day's total at the right, then the name. The
    // photo keeps the middle (iOS `DayCardView`, 2026-11-10).
    Box(modifier.size(format.width.dp, format.height.dp).background(INK)) {
        photo?.let {
            Image(it, contentDescription = null, contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize())
        }
        Box(Modifier.fillMaxSize().background(Brush.verticalGradient(
            // The story's content sits inside Instagram's safe area, so its
            // dark ground starts higher at both ends.
            0f to INK.copy(alpha = if (isStory) 0.45f else 0.34f),
            (if (isStory) 0.24f else 0.2f) to INK.copy(alpha = 0f),
            (if (isStory) 0.34f else 0.26f) to INK.copy(alpha = 0f),
            0.6f to INK.copy(alpha = 0.88f),
            1f to INK.copy(alpha = 0.95f))))

        Column(
            Modifier.fillMaxSize().padding(horizontal = margin)
                // A story is posted under Instagram's own chrome: the date
                // and the streak sit below the profile row, the footer off
                // the bottom edge (iOS `safeTop` / `safeBottom`; 84 / 114
                // were tried first and left the card half empty).
                .padding(top = if (isStory) 64.dp else margin,
                    bottom = if (isStory) 44.dp else if (isFeed) 22.dp else 18.dp),
        ) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                // The mark alone, small, at the top left; the date is plain
                // text (no mosaic behind it since iOS 2026-11-13).
                NawanaMark(Modifier.size(if (isFeed) 18.dp else 16.dp), PAPER)
                Spacer(Modifier.weight(1f))
                Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(3.dp)) {
                    val date = SimpleDateFormat("MMM d", Locale.US).format(Date(data.date))
                    Text(date, color = PAPER, style = DisplayFace.style(date,
                        TextStyle(fontSize = (if (isFeed) 10.7f else 9.7f).sp)))
                    if (data.streakDays > 0) {
                        Text("${data.streakDays} day streak".uppercase(), color = PAPER.copy(alpha = 0.72f),
                            style = TextStyle(fontSize = (if (isFeed) 7.3f else 6.7f).sp, letterSpacing = 1.sp,
                                fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace))
                    }
                }
            }
            Spacer(Modifier.weight(1f))
            data.topics.firstOrNull()?.let { topic ->
                // iOS `.lineLimit(3 / 2).minimumScaleFactor(0.6)`: a long
                // headline SHRINKS until it fits, and is cut only past 60%.
                var scale by remember(topic, format) { mutableStateOf(1f) }
                Text(topic, color = PAPER, maxLines = if (isStory) 3 else 2, overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.padding(bottom = if (isFeed) 14.dp else 10.dp),
                    style = DisplayFace.style(topic, TextStyle(
                        fontSize = (if (isFeed) 31 else 25).sp * scale,
                        lineHeight = (if (isFeed) 36 else 30).sp * scale)),
                    onTextLayout = { r ->
                        if (r.hasVisualOverflow && scale > 0.6f) scale = (scale - 0.05f).coerceAtLeast(0.6f)
                    })
            }
            Rule()
            Row(Modifier.fillMaxWidth().padding(vertical = if (isFeed) 12.dp else 9.dp),
                verticalAlignment = Alignment.Bottom) {
                // What was done, one line each: the name small and tracked,
                // the amount in the pixel face beside it.
                val lines = data.lines.take(format.maxLines)
                Row(horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                    val gap = if (isFeed) 7.dp else 5.dp
                    val rowH = if (isFeed) 16.dp else 14.dp
                    Column(verticalArrangement = Arrangement.spacedBy(gap)) {
                        lines.forEach { (label, _) ->
                            Box(Modifier.height(rowH), contentAlignment = Alignment.CenterStart) {
                                Text(label.uppercase(), color = PAPER.copy(alpha = 0.72f), maxLines = 1,
                                    style = TextStyle(fontSize = (if (isFeed) 8f else 7.3f).sp,
                                        letterSpacing = 1.sp,
                                        fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace))
                            }
                        }
                    }
                    Column(verticalArrangement = Arrangement.spacedBy(gap)) {
                        lines.forEach { (_, value) ->
                            Box(Modifier.height(rowH), contentAlignment = Alignment.CenterStart) {
                                Text(value, color = PAPER, maxLines = 1, style = DisplayFace.style(value,
                                    TextStyle(fontSize = (if (isFeed) 13 else 12).sp)))
                            }
                        }
                    }
                }
                Spacer(Modifier.weight(1f))
                // The day's whole time in the app, large, at the bottom right.
                Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    val total = "${data.studyMinutes}"
                    Text(total, color = PAPER, style = DisplayFace.style(total,
                        TextStyle(fontSize = (if (isFeed) 40 else 32).sp)))
                    Text("MIN TODAY", color = PAPER.copy(alpha = 0.72f),
                        style = TextStyle(fontSize = (if (isFeed) 7.3f else 6.7f).sp, letterSpacing = 1.sp,
                            fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace))
                }
            }
            Rule()
            Row(Modifier.fillMaxWidth().padding(top = if (isFeed) 10.7.dp else 8.7.dp),
                verticalAlignment = Alignment.CenterVertically) {
                Text("Learn a language from your fluent self.", color = PAPER,
                    style = DisplayFace.style("Learn",
                        TextStyle(fontSize = (if (isFeed) 8.7f else 8f).sp)))
                Spacer(Modifier.weight(1f))
                Text("nawana.app", color = PAPER.copy(alpha = 0.72f),
                    style = TextStyle(fontSize = (if (isFeed) 8.7f else 8f).sp, letterSpacing = 1.2.sp,
                        fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace))
            }
        }
    }
}

@Composable
private fun Rule() = Box(Modifier.fillMaxWidth().height(0.5.dp).background(PAPER.copy(alpha = 0.28f)))

/** The nawana mark (iOS `NawanaMark`): five rects on a 1024 grid. */
@Composable
private fun NawanaMark(modifier: Modifier, color: Color) {
    androidx.compose.foundation.Canvas(modifier) {
        val k = size.width / 1024f
        listOf(
            floatArrayOf(290f, 237f, 410f, 100f), floatArrayOf(186f, 337f, 104f, 349f),
            floatArrayOf(700f, 337f, 104f, 349f), floatArrayOf(290f, 686f, 410f, 100f),
            floatArrayOf(806f, 686f, 95f, 100f),
        ).forEach { r ->
            drawRect(color, topLeft = androidx.compose.ui.geometry.Offset(r[0] * k, r[1] * k),
                size = androidx.compose.ui.geometry.Size(r[2] * k, r[3] * k))
        }
    }
}
