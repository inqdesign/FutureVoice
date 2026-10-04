package com.roro.futurevoice.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.automirrored.filled.LibraryBooks
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.Book
import androidx.compose.material.icons.filled.CalendarToday
import androidx.compose.material.icons.filled.CardGiftcard
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.ClosedCaption
import androidx.compose.material.icons.filled.EditNote
import androidx.compose.material.icons.filled.FactCheck
import androidx.compose.material.icons.filled.Flight
import androidx.compose.material.icons.filled.FormatQuote
import androidx.compose.material.icons.filled.Forum
import androidx.compose.material.icons.filled.GraphicEq
import androidx.compose.material.icons.filled.GridView
import androidx.compose.material.icons.filled.Language
import androidx.compose.material.icons.filled.Layers
import androidx.compose.material.icons.filled.Lightbulb
import androidx.compose.material.icons.filled.LocalCafe
import androidx.compose.material.icons.filled.LocalFireDepartment
import androidx.compose.material.icons.filled.MarkChatRead
import androidx.compose.material.icons.filled.Newspaper
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Phone
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.PlayCircle
import androidx.compose.material.icons.filled.RadioButtonUnchecked
import androidx.compose.material.icons.filled.Replay
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.TextFields
import androidx.compose.material.icons.filled.TouchApp
import androidx.compose.material.icons.filled.TrackChanges
import androidx.compose.material.icons.filled.Tune
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.WbTwilight
import androidx.compose.material.icons.filled.Work
import androidx.compose.material.icons.outlined.Lightbulb
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.scale
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.zIndex
import com.roro.futurevoice.R
import com.roro.futurevoice.ui.brand.AppSurfaces
import com.roro.futurevoice.ui.brand.ContinuousShape
import com.roro.futurevoice.ui.brand.Futureself
import com.roro.futurevoice.ui.brand.FutureselfMode
import com.roro.futurevoice.ui.brand.FutureselfTheme

/*
 * The guides' wireframes — iOS `PageIntroSheet`'s mocks at `ebf848e`, one for
 * one, each drawn after the real screen it explains. Illustrations, not UI:
 * grey bars ([TextBar]) stand in for text so the picture reads the same in
 * every language, and only the labels that name a control are real words.
 * Numbered spots are [Callout]s, lit by the page that hosts them.
 */

private val accent: Color @Composable get() = MaterialTheme.colorScheme.primary
private val mockCard: Color @Composable get() = AppSurfaces.card
private val tertiaryFill: Color @Composable get() = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.07f)
private val secondaryInk: Color @Composable get() = MaterialTheme.colorScheme.onSurfaceVariant

/** A line of text, as a wireframe draws it. */
@Composable
private fun TextBar(width: Dp, height: Dp = 7.dp, accentBar: Boolean = false) {
    Box(Modifier.size(width, height).background(
        if (accentBar) accent.copy(alpha = 0.45f) else MaterialTheme.colorScheme.onSurface.copy(alpha = 0.3f * 0.45f),
        CircleShape))
}

@Composable
private fun Caption(text: String, size: TextUnit = 12.sp, weight: FontWeight = FontWeight.Bold,
                    color: Color = MaterialTheme.colorScheme.onSurface, modifier: Modifier = Modifier) {
    Text(text, modifier, fontSize = size, fontWeight = weight, color = color, maxLines = 1,
        overflow = TextOverflow.Ellipsis)
}

@Composable
private fun Glyph(icon: ImageVector, size: Dp = 14.dp, tint: Color = accent) =
    Icon(icon, null, Modifier.size(size), tint = tint)

@Composable
private fun futureselfTheme(): FutureselfTheme {
    val context = LocalContext.current
    return remember { FutureselfTheme.stored(context) }
}

// MARK: - Talk

@Composable
internal fun TalkRingMock() {
    Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(18.dp)) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
            TextBar(150.dp, 9.dp); TextBar(96.dp, 9.dp)
        }
        Callout(2, corner = 68.dp) {
            Box(Modifier.size(136.dp), contentAlignment = Alignment.Center) {
                val track = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.08f)
                val a = accent
                Canvas(Modifier.fillMaxSize()) {
                    val w = 10.dp.toPx()
                    val inset = w / 2
                    val sz = Size(size.width - w, size.height - w)
                    drawArc(track, 0f, 360f, false, Offset(inset, inset), sz, style = Stroke(w))
                    drawArc(a, -90f, 360f * 0.62f, false, Offset(inset, inset), sz,
                        style = Stroke(w, cap = StrokeCap.Round))
                }
                Callout(1, corner = 49.dp, trailing = true) {
                    Futureself(mode = FutureselfMode.IDLE, level = 0f, theme = futureselfTheme(),
                        virtualHeight = 64f, modifier = Modifier.size(98.dp).clip(CircleShape))
                }
            }
        }
        Callout(3) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                TalkTile(Icons.Filled.LocalCafe, stringResource(R.string.guide_scenarios), Modifier.weight(1f))
                TalkTile(Icons.Filled.Newspaper, stringResource(R.string.guide_news), Modifier.weight(1f))
            }
        }
    }
}

@Composable
private fun TalkTile(icon: ImageVector, label: String, modifier: Modifier) {
    Column(modifier.background(mockCard, ContinuousShape(12.dp)).padding(10.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Glyph(icon, 16.dp)
        Caption(label)
        TextBar(64.dp, 6.dp)
    }
}

@Composable
internal fun TalkHeaderMock() {
    Column(Modifier.fillMaxWidth().padding(top = 6.dp), horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(22.dp)) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Callout(1, corner = 16.dp) {
                Row(Modifier.background(mockCard, CircleShape).padding(horizontal = 11.dp, vertical = 8.dp),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    Glyph(Icons.Filled.Language, 12.dp, MaterialTheme.colorScheme.onSurface)
                    Caption("EN", 13.sp, FontWeight.SemiBold)
                }
            }
            Spacer(Modifier.weight(1f))
            Callout(2, corner = 16.dp) {
                Row(Modifier.background(mockCard, CircleShape).padding(horizontal = 11.dp, vertical = 8.dp),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    Glyph(Icons.Filled.LocalFireDepartment, 14.dp, Color(0xFFFF9500))
                    Caption("5", 13.sp)
                }
            }
            Spacer(Modifier.weight(1f))
            Callout(3, corner = 22.dp) {
                Box(Modifier.size(44.dp).background(mockCard, CircleShape), contentAlignment = Alignment.Center) {
                    val a = accent
                    Canvas(Modifier.fillMaxSize().padding(3.dp)) {
                        val w = 3.dp.toPx()
                        drawArc(a, -90f, 360f * 0.35f, false, Offset(w / 2, w / 2),
                            Size(size.width - w, size.height - w), style = Stroke(w, cap = StrokeCap.Round))
                    }
                    Box(Modifier.size(28.dp).background(a.copy(alpha = 0.25f), CircleShape),
                        contentAlignment = Alignment.Center) { Glyph(Icons.Filled.Person, 12.dp) }
                }
            }
        }
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
            TextBar(150.dp, 9.dp); TextBar(96.dp, 9.dp)
        }
        val track = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.08f)
        Box(Modifier.size(84.dp).scale(1f), contentAlignment = Alignment.Center) {
            Canvas(Modifier.fillMaxSize()) {
                val w = 8.dp.toPx()
                drawArc(track.copy(alpha = track.alpha * 0.6f), 0f, 360f, false, Offset(w / 2, w / 2),
                    Size(size.width - w, size.height - w), style = Stroke(w))
            }
            Box(Modifier.size(64.dp).background(accent.copy(alpha = 0.12f * 0.6f), CircleShape))
        }
    }
}

@Composable
internal fun TalkCallMock() {
    Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Callout(3, corner = 12.dp) {
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                CallChip(true); CallChip(false); CallChip(false)
            }
        }
        Row(Modifier.fillMaxWidth()) {
            Bubble(listOf(130.dp, 92.dp), mine = false)
            Spacer(Modifier.weight(1f).widthIn(min = 28.dp))
        }
        Row(Modifier.fillMaxWidth()) {
            Spacer(Modifier.weight(1f).widthIn(min = 28.dp))
            Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Bubble(listOf(118.dp, 70.dp), mine = true)
                Callout(2, corner = 10.dp) {
                    Column(Modifier.background(accent.copy(alpha = 0.08f), ContinuousShape(10.dp)).padding(9.dp),
                        verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                            Glyph(Icons.Filled.AutoAwesome, 11.dp)
                            Caption(stringResource(R.string.guide_more_natural), 11.sp, color = accent)
                        }
                        TextBar(124.dp, accentBar = true)
                        TextBar(80.dp, accentBar = true)
                    }
                }
            }
        }
        Callout(1, corner = 24.dp) {
            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Futureself(mode = FutureselfMode.LISTENING, level = 0.45f, theme = futureselfTheme(),
                    modifier = Modifier.size(132.dp, 48.dp).clip(CircleShape))
                Caption(stringResource(R.string.guide_listening), 11.sp, FontWeight.Normal, secondaryInk)
            }
        }
    }
}

@Composable
private fun CallChip(checked: Boolean) {
    Row(Modifier.background(mockCard, CircleShape).padding(horizontal = 8.dp, vertical = 5.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        Glyph(if (checked) Icons.Filled.CheckCircle else Icons.Filled.RadioButtonUnchecked, 11.dp,
            if (checked) Color(0xFF34C759) else secondaryInk)
        TextBar(32.dp, 6.dp)
    }
}

@Composable
private fun Bubble(widths: List<Dp>, mine: Boolean) {
    Column(Modifier.background(if (mine) accent.copy(alpha = 0.16f) else mockCard, ContinuousShape(14.dp))
        .padding(11.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        widths.forEach { TextBar(it) }
    }
}

@Composable
internal fun CallSettingsMock() {
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(14.dp, Alignment.CenterHorizontally),
            verticalAlignment = Alignment.CenterVertically) {
            Futureself(mode = FutureselfMode.IDLE, level = 0f, theme = futureselfTheme(),
                modifier = Modifier.size(112.dp, 42.dp).clip(CircleShape))
            Callout(1, corner = 19.dp, trailing = true) {
                Box(Modifier.size(38.dp).background(mockCard, CircleShape), contentAlignment = Alignment.Center) {
                    Glyph(Icons.Filled.Tune, 16.dp, secondaryInk)
                }
            }
        }
        Column(Modifier.fillMaxWidth().background(mockCard, ContinuousShape(14.dp))) {
            Callout(2, corner = 14.dp) {
                Row(Modifier.fillMaxWidth().padding(10.dp), horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                    SpeedPill(stringResource(R.string.guide_normal), false, Modifier.weight(1f))
                    SpeedPill(stringResource(R.string.guide_relaxed), true, Modifier.weight(1f))
                    SpeedPill(stringResource(R.string.guide_slow), false, Modifier.weight(1f))
                }
            }
            MockDivider()
            Callout(3, corner = 8.dp) {
                ToggleRow(Icons.Outlined.Lightbulb, stringResource(R.string.guide_coach_mode), true)
            }
            MockDivider()
            Callout(4, corner = 8.dp) {
                Column {
                    ToggleRow(Icons.Filled.ClosedCaption, stringResource(R.string.guide_subtitles), true)
                    ToggleRow(Icons.Filled.AutoAwesome, stringResource(R.string.guide_corrections), true)
                    ToggleRow(Icons.Filled.FactCheck, stringResource(R.string.guide_words_to_use), false)
                }
            }
        }
    }
}

@Composable
private fun MockDivider() =
    Box(Modifier.fillMaxWidth().height(0.5.dp).background(MaterialTheme.colorScheme.outlineVariant))

@Composable
private fun SpeedPill(label: String, on: Boolean, modifier: Modifier) {
    Box(modifier.background(if (on) accent else tertiaryFill, CircleShape).padding(vertical = 7.dp),
        contentAlignment = Alignment.Center) {
        Caption(label, 12.sp, FontWeight.SemiBold,
            if (on) MaterialTheme.colorScheme.onPrimary else MaterialTheme.colorScheme.onSurface)
    }
}

@Composable
private fun ToggleRow(icon: ImageVector, label: String, on: Boolean) {
    Row(Modifier.fillMaxWidth().padding(horizontal = 10.dp, vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Box(Modifier.width(18.dp), contentAlignment = Alignment.Center) { Glyph(icon, 13.dp) }
        Caption(label, 12.sp, FontWeight.SemiBold, modifier = Modifier.weight(1f))
        Box(Modifier.size(44.dp, 26.dp), contentAlignment = Alignment.Center) {
            Switch(checked = on, onCheckedChange = null, modifier = Modifier.scale(0.62f))
        }
    }
}

@Composable
internal fun CoachMock() {
    Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Callout(3, corner = 16.dp) {
            Row(Modifier.fillMaxWidth().background(mockCard, CircleShape).padding(horizontal = 10.dp, vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Glyph(Icons.Filled.TrackChanges, 13.dp, Color(0xFFFF9500))
                TextBar(54.dp)
                Glyph(Icons.AutoMirrored.Filled.ArrowForward, 11.dp, secondaryInk)
                TextBar(54.dp, accentBar = true)
            }
        }
        Row(Modifier.fillMaxWidth()) {
            Bubble(listOf(140.dp, 96.dp), mine = false)
            Spacer(Modifier.weight(1f).widthIn(min = 28.dp))
        }
        Callout(1) {
            Column(Modifier.fillMaxWidth().background(mockCard, ContinuousShape(12.dp)).padding(10.dp),
                verticalArrangement = Arrangement.spacedBy(7.dp)) {
                Caption(stringResource(R.string.guide_try_saying), 11.sp, color = secondaryInk)
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                    TextBar(64.dp, 8.dp)
                    DashedBox(40.dp, 14.dp, 3.dp)
                    TextBar(40.dp, 8.dp)
                }
                TextBar(110.dp, 6.dp)
            }
        }
        Callout(2, corner = 10.dp) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Caption(stringResource(R.string.guide_try_using), 11.sp, FontWeight.SemiBold, secondaryInk)
                TextBar(52.dp, 8.dp, accentBar = true)
                Glyph(Icons.Filled.RadioButtonUnchecked, 11.dp, secondaryInk)
            }
        }
        Futureself(mode = FutureselfMode.LISTENING, level = 0.4f, theme = futureselfTheme(),
            modifier = Modifier.size(120.dp, 44.dp).clip(CircleShape))
    }
}

/** A dashed accent outline — a blank, or an empty spot about to be filled. */
@Composable
private fun DashedBox(width: Dp?, height: Dp, corner: Dp, modifier: Modifier = Modifier,
                      content: @Composable () -> Unit = {}) {
    val a = accent
    Box((if (width != null) modifier.size(width, height) else modifier.height(height)).drawBehind {
        val s = 1.3.dp.toPx()
        drawRoundRect(a, topLeft = Offset(s / 2, s / 2), size = Size(size.width - s, size.height - s),
            cornerRadius = CornerRadius(corner.toPx()),
            style = Stroke(s, pathEffect = PathEffect.dashPathEffect(floatArrayOf(3.dp.toPx(), 2.dp.toPx()))))
    }, contentAlignment = Alignment.Center) { content() }
}

// MARK: - Watch

@Composable
internal fun CastMock() {
    Row(Modifier.padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(16.dp)) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Box(Modifier.size(64.dp).background(accent.copy(alpha = 0.15f), CircleShape),
                contentAlignment = Alignment.Center) {
                Caption("M", 22.sp, color = accent)
            }
            TextBar(56.dp, 8.dp)
            Column(Modifier.background(mockCard, ContinuousShape(8.dp)).padding(8.dp),
                verticalArrangement = Arrangement.spacedBy(5.dp)) {
                TextBar(70.dp, 5.dp); TextBar(52.dp, 5.dp); TextBar(62.dp, 5.dp)
            }
        }
        Glyph(Icons.AutoMirrored.Filled.ArrowForward, 18.dp, tertiaryLabel())
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            CastScene(Icons.Filled.Work, 76.dp)
            CastScene(Icons.Filled.LocalCafe, 64.dp)
            CastScene(Icons.Filled.Flight, 84.dp)
            CastScene(Icons.Filled.CardGiftcard, 58.dp)
        }
    }
}

@Composable
private fun CastScene(icon: ImageVector, width: Dp) {
    Row(Modifier.width(150.dp).background(mockCard, ContinuousShape(10.dp))
        .padding(horizontal = 10.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Box(Modifier.width(18.dp), contentAlignment = Alignment.Center) { Glyph(icon, 13.dp) }
        TextBar(width)
        Spacer(Modifier.weight(1f))
        Glyph(Icons.Filled.PlayArrow, 10.dp, secondaryInk)
    }
}

@Composable
internal fun WatchHomeMock() {
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Text(stringResource(R.string.guide_watch), style = MaterialTheme.typography.titleLarge,
            fontWeight = FontWeight.Bold)
        Callout(1, corner = 18.dp) {
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                listOf("M", "J", "S").forEach { initial ->
                    Box(Modifier.size(36.dp).background(accent.copy(alpha = 0.15f), CircleShape),
                        contentAlignment = Alignment.Center) { Caption(initial, color = accent) }
                }
                val a = accent
                Box(Modifier.size(36.dp).drawBehind {
                    val s = 1.5.dp.toPx()
                    drawCircle(a.copy(alpha = 0.5f), radius = size.minDimension / 2 - s / 2,
                        style = Stroke(s, pathEffect = PathEffect.dashPathEffect(floatArrayOf(3.dp.toPx(), 3.dp.toPx()))))
                }, contentAlignment = Alignment.Center) { Glyph(Icons.Filled.Add, 12.dp) }
            }
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Callout(2, modifier = Modifier.weight(1f)) {
                WatchDoor(Icons.Filled.EditNote, stringResource(R.string.guide_your_own_situation))
            }
            Callout(3, modifier = Modifier.weight(1f)) {
                WatchDoor(Icons.Filled.GridView, stringResource(R.string.guide_common_situations))
            }
        }
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Caption(stringResource(R.string.guide_your_scenarios), color = secondaryInk)
            Row(Modifier.fillMaxWidth().background(mockCard, ContinuousShape(12.dp)).padding(10.dp),
                verticalAlignment = Alignment.CenterVertically) {
                TextBar(130.dp)
                Spacer(Modifier.weight(1f))
                Glyph(Icons.Filled.PlayCircle, 18.dp)
            }
        }
    }
}

@Composable
private fun WatchDoor(icon: ImageVector, label: String) {
    Column(Modifier.fillMaxWidth().heightIn(min = 64.dp).background(mockCard, ContinuousShape(12.dp)).padding(10.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Glyph(icon, 16.dp)
        Text(label, fontSize = 12.sp, fontWeight = FontWeight.Bold, maxLines = 2, overflow = TextOverflow.Ellipsis)
    }
}

/** Drawn after the real scene screen: the header, a name label over each
 *  line, the action row under every line, the playing line outlined, and
 *  the two buttons pinned at the bottom. */
@Composable
internal fun WatchSceneMock() {
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Column(verticalArrangement = Arrangement.spacedBy(5.dp)) {
            TextBar(70.dp, 5.dp); TextBar(120.dp, 10.dp); TextBar(170.dp, 5.dp)
        }
        SceneLine(mine = false, widths = listOf(118.dp), actionsCallout = 2)
        SceneLine(mine = true, widths = listOf(150.dp, 72.dp), playing = true, bubbleCallout = 1)
        SceneLine(mine = false, widths = listOf(96.dp), actions = false)
        Callout(3, corner = 17.dp, modifier = Modifier.padding(top = 4.dp)) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                SceneButton(Icons.Filled.Replay, stringResource(R.string.guide_watch_again), false, Modifier.weight(1f))
                SceneButton(Icons.AutoMirrored.Filled.LibraryBooks, stringResource(R.string.study_this), true,
                    Modifier.weight(1f))
            }
        }
    }
}

@Composable
private fun SceneButton(icon: ImageVector, label: String, filled: Boolean, modifier: Modifier) {
    val ink = if (filled) MaterialTheme.colorScheme.onPrimary else accent
    Row(modifier.background(if (filled) accent else accent.copy(alpha = 0.15f), CircleShape).padding(vertical = 9.dp),
        horizontalArrangement = Arrangement.spacedBy(4.dp, Alignment.CenterHorizontally),
        verticalAlignment = Alignment.CenterVertically) {
        Glyph(icon, 12.dp, ink)
        Caption(label, 12.sp, FontWeight.SemiBold, ink)
    }
}

@Composable
private fun SceneLine(mine: Boolean, widths: List<Dp>, playing: Boolean = false, actions: Boolean = true,
                      actionsCallout: Int? = null, bubbleCallout: Int? = null) {
    Column(Modifier.fillMaxWidth(), horizontalAlignment = if (mine) Alignment.End else Alignment.Start,
        verticalArrangement = Arrangement.spacedBy(5.dp)) {
        TextBar(34.dp, 5.dp)
        val bubble: @Composable () -> Unit = {
            Column(Modifier.background(mockCard, ContinuousShape(14.dp))
                .then(if (playing) Modifier.border(1.5.dp, accent, ContinuousShape(14.dp)) else Modifier)
                .padding(10.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                widths.forEach { TextBar(it) }
            }
        }
        if (bubbleCallout != null) Callout(bubbleCallout, corner = 14.dp, trailing = mine) { bubble() } else bubble()
        if (actions) {
            val row: @Composable () -> Unit = {
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(3.dp)) {
                        Glyph(Icons.Filled.GraphicEq, 10.dp); Caption(stringResource(R.string.guide_shadow_this), 9.sp, FontWeight.SemiBold, accent)
                    }
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(3.dp)) {
                        Glyph(Icons.Filled.Add, 10.dp); Caption(stringResource(R.string.guide_save_phrase), 9.sp, FontWeight.SemiBold, accent)
                    }
                }
            }
            if (actionsCallout != null) Callout(actionsCallout, corner = 6.dp) { row() } else row()
        }
    }
}

// MARK: - Review

/** Drawn after the real Review page: the title with the week's buttons, the
 *  shelf chips, the four library tiles, then a book with its chapters. */
@Composable
internal fun ReviewHomeMock() {
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        ReviewHeaderMock()
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.background(MaterialTheme.colorScheme.onSurface, CircleShape)
                .padding(horizontal = 10.dp, vertical = 6.dp)) {
                Caption(stringResource(R.string.guide_studying), 11.sp, color = MaterialTheme.colorScheme.surface)
            }
            listOf(28.dp, 40.dp, 26.dp).forEach { w ->
                Box(Modifier.background(mockCard, CircleShape).padding(horizontal = 10.dp, vertical = 9.dp)) {
                    TextBar(w, 6.dp)
                }
            }
        }
        Callout(3, corner = 14.dp) {
            Row(Modifier.fillMaxWidth().background(mockCard, ContinuousShape(14.dp)).padding(vertical = 8.dp)) {
                LibraryTile(Icons.Filled.Book, stringResource(R.string.guide_words), Modifier.weight(1f))
                LibraryTile(Icons.Filled.FormatQuote, stringResource(R.string.guide_expressions), Modifier.weight(1f))
                LibraryTile(Icons.Filled.Layers, stringResource(R.string.guide_sentences), Modifier.weight(1f))
                LibraryTile(Icons.Filled.GraphicEq, stringResource(R.string.guide_shadowing), Modifier.weight(1f))
            }
        }
        Callout(1, corner = 14.dp) {
            Column(Modifier.fillMaxWidth().background(mockCard, ContinuousShape(14.dp)).padding(10.dp),
                verticalArrangement = Arrangement.spacedBy(9.dp)) {
                Box(Modifier.size(28.dp).background(accent.copy(alpha = 0.15f), CircleShape),
                    contentAlignment = Alignment.Center) { Glyph(Icons.Filled.Forum, 12.dp) }
                Column(verticalArrangement = Arrangement.spacedBy(5.dp)) { TextBar(60.dp, 5.dp); TextBar(150.dp, 8.dp) }
                Callout(2, corner = 10.dp) {
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        Chapter(Icons.Filled.Book, 0.6f, Modifier.weight(1f))
                        Chapter(Icons.Filled.FormatQuote, 0f, Modifier.weight(1f))
                        Chapter(Icons.Filled.GraphicEq, 0.8f, Modifier.weight(1f))
                        Chapter(Icons.Filled.MarkChatRead, 0f, Modifier.weight(1f))
                    }
                }
            }
        }
    }
}

@Composable
private fun LibraryTile(icon: ImageVector, label: String, modifier: Modifier) {
    Column(modifier, horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(3.dp)) {
        Glyph(icon, 13.dp)
        TextBar(14.dp, 7.dp)
        Caption(label, 9.sp, FontWeight.SemiBold, secondaryInk)
    }
}

@Composable
private fun Chapter(icon: ImageVector, progress: Float, modifier: Modifier) {
    Column(modifier.background(tertiaryFill.copy(alpha = tertiaryFill.alpha * 0.6f), ContinuousShape(10.dp))
        .padding(8.dp),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(5.dp)) {
        val dim = if (progress == 0f) 0.5f else 1f
        Glyph(icon, 13.dp, accent.copy(alpha = dim))
        BoxWithConstraints(Modifier.fillMaxWidth().height(3.dp).background(tertiaryFill, CircleShape)) {
            Box(Modifier.width(maxWidth * progress).fillMaxHeight().background(accent, CircleShape))
        }
    }
}

/** The Review title and its header buttons: put-off cards and the week's
 *  report together, the test's face apart. */
@Composable
private fun ReviewHeaderMock(putOffMark: Int? = null, weekMark: Int? = null, testMark: Int? = null) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(stringResource(R.string.guide_review), style = MaterialTheme.typography.headlineSmall,
            fontWeight = FontWeight.Bold)
        Spacer(Modifier.weight(1f))
        Row(Modifier.background(mockCard, CircleShape).padding(horizontal = 4.dp),
            horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            HeaderIcon(Icons.Filled.Layers, Color(0xFFFF9500), putOffMark)
            HeaderIcon(Icons.Filled.CalendarToday, accent, weekMark)
        }
        val face: @Composable () -> Unit = {
            Box(Modifier.size(32.dp).background(mockCard, CircleShape), contentAlignment = Alignment.Center) {
                WeeklyTestCharacter(WeeklyTestHost.Mood.WAITING, 0L, Modifier.size(24.dp), tile = tertiaryFill)
                Box(Modifier.align(Alignment.TopEnd).offset(x = (-2).dp, y = 3.dp).size(7.dp)
                    .background(accent, CircleShape))
            }
        }
        if (testMark != null) Callout(testMark, corner = 16.dp, trailing = true) { face() } else face()
    }
}

@Composable
private fun HeaderIcon(icon: ImageVector, dot: Color, mark: Int?) {
    val view: @Composable () -> Unit = {
        Box(Modifier.size(32.dp), contentAlignment = Alignment.Center) {
            Glyph(icon, 16.dp, MaterialTheme.colorScheme.onSurface)
            Box(Modifier.align(Alignment.TopEnd).offset(x = (-3).dp, y = 4.dp).size(7.dp).background(dot, CircleShape))
        }
    }
    if (mark != null) Callout(mark, corner = 16.dp) { view() } else view()
}

/** The week's header buttons, and what two of them open: the week's report
 *  card and a test question. */
@Composable
internal fun ReviewWeekMock() {
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        ReviewHeaderMock(putOffMark = 1, weekMark = 2, testMark = 3)
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Column(Modifier.weight(1f).background(mockCard, ContinuousShape(12.dp)).padding(10.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(3.dp)) {
                    Text("5", fontSize = 26.sp, fontWeight = FontWeight.Bold)
                    Caption("/ 7", 12.sp, FontWeight.SemiBold, secondaryInk, Modifier.padding(bottom = 4.dp))
                }
                Row(horizontalArrangement = Arrangement.spacedBy(3.dp)) {
                    repeat(7) { i ->
                        Box(Modifier.size(11.dp).background(if (i == 2 || i == 5) tertiaryFill else accent, CircleShape))
                    }
                }
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    Glyph(Icons.Filled.LocalFireDepartment, 11.dp, Color(0xFFFF9500)); TextBar(40.dp, 6.dp)
                }
                TextBar(80.dp, 5.dp); TextBar(64.dp, 5.dp)
            }
            Column(Modifier.weight(1f).background(mockCard, ContinuousShape(12.dp)).padding(10.dp),
                verticalArrangement = Arrangement.spacedBy(7.dp)) {
                Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                    WeeklyTestCharacter(WeeklyTestHost.Mood.WAITING, 0L, Modifier.size(30.dp), tile = tertiaryFill)
                }
                TextBar(90.dp, 7.dp)
                listOf(70.dp, 54.dp, 62.dp).forEach { w ->
                    Box(Modifier.fillMaxWidth().background(accent.copy(alpha = 0.12f), CircleShape)
                        .padding(horizontal = 8.dp, vertical = 6.dp)) { TextBar(w, 6.dp, accentBar = true) }
                }
            }
        }
    }
}

/** Drawn after the real deck: one large accent card — the prompt, the word,
 *  "tap to see the meaning" — and the four folders it can be dropped on. */
@Composable
internal fun ReviewCardMock() {
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Callout(1, corner = 18.dp) {
            Box(Modifier.fillMaxWidth().height(150.dp)) {
                Column(Modifier.fillMaxSize().background(accent, ContinuousShape(18.dp)).padding(14.dp),
                    verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    val on = MaterialTheme.colorScheme.onPrimary
                    Box(Modifier.size(120.dp, 6.dp).background(on.copy(alpha = 0.55f), CircleShape))
                    Box(Modifier.size(110.dp, 13.dp).background(on, CircleShape))
                    Spacer(Modifier.weight(1f))
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterHorizontally),
                        verticalAlignment = Alignment.CenterVertically) {
                        Glyph(Icons.Filled.Visibility, 11.dp, on.copy(alpha = 0.85f))
                        Box(Modifier.size(60.dp, 6.dp).background(on.copy(alpha = 0.85f), CircleShape))
                    }
                }
                Icon(Icons.Filled.TouchApp, null,
                    Modifier.align(Alignment.BottomEnd).offset(x = (-16).dp, y = 14.dp).size(24.dp),
                    tint = MaterialTheme.colorScheme.onPrimary)
            }
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Callout(2, corner = 12.dp, modifier = Modifier.weight(3f)) {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Folder(Icons.Filled.Schedule, stringResource(R.string.guide_10_min), Modifier.weight(1f))
                    Folder(Icons.Filled.WbTwilight, stringResource(R.string.guide_tomorrow), Modifier.weight(1f))
                    Folder(Icons.Filled.CalendarToday, stringResource(R.string.guide_3_days), Modifier.weight(1f))
                }
            }
            Callout(3, corner = 12.dp, trailing = true, modifier = Modifier.widthIn(max = 72.dp).weight(1f)) {
                Folder(Icons.Filled.CheckCircle, stringResource(R.string.guide_got_it), Modifier.fillMaxWidth())
            }
        }
    }
}

@Composable
private fun Folder(icon: ImageVector, label: String, modifier: Modifier) {
    Column(modifier.background(mockCard, ContinuousShape(12.dp)).padding(vertical = 9.dp),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Glyph(icon, 16.dp, secondaryInk)
        Caption(label, 10.sp, FontWeight.SemiBold, secondaryInk)
    }
}

// MARK: - Progress

@Composable
internal fun ProgressHomeMock() {
    val ladder = listOf("A1", "A2", "B1", "B2", "C1", "C2")
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Callout(1, corner = 14.dp) {
            Column(Modifier.fillMaxWidth().background(mockCard, ContinuousShape(14.dp)).padding(12.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Caption(stringResource(R.string.guide_your_level), color = secondaryInk)
                Text("≈ B1", fontSize = 32.sp, fontWeight = FontWeight.Bold)
                Row(horizontalArrangement = Arrangement.spacedBy(3.dp)) {
                    ladder.forEachIndexed { i, band ->
                        Box(Modifier.weight(1f).background(
                            when { i == 2 -> accent; i < 2 -> accent.copy(alpha = 0.3f); else -> tertiaryFill },
                            RoundedCornerShape(5.dp)).padding(vertical = 4.dp),
                            contentAlignment = Alignment.Center) {
                            Caption(band, 9.sp, color = if (i == 2) MaterialTheme.colorScheme.onPrimary else secondaryInk)
                        }
                    }
                }
            }
        }
        Callout(2, corner = 10.dp) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Skill(stringResource(R.string.guide_vocabulary), "B1", Modifier.weight(1f))
                Skill(stringResource(R.string.guide_grammar), "A2", Modifier.weight(1f))
                Skill(stringResource(R.string.guide_fluency), "B1", Modifier.weight(1f))
            }
        }
        Callout(3) {
            Row(Modifier.fillMaxWidth().background(mockCard, ContinuousShape(12.dp)).padding(10.dp).height(44.dp),
                verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                listOf(0.3f, 0.5f, 0.2f, 0f, 0.6f, 0.8f, 0.4f, 0.7f, 0.5f, 0f, 0.9f, 0.6f, 0.75f, 1f).forEach { h ->
                    Box(Modifier.weight(1f).height(maxOf(4f, 44f * h).dp)
                        .background(accent.copy(alpha = if (h == 0f) 0.15f else 0.7f), RoundedCornerShape(2.dp)))
                }
            }
        }
    }
}

@Composable
private fun Skill(label: String, band: String, modifier: Modifier) {
    Column(modifier.background(mockCard, ContinuousShape(10.dp)).padding(vertical = 8.dp),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(3.dp)) {
        Caption(label, 10.sp, FontWeight.SemiBold)
        Caption(band, 12.sp, color = accent)
    }
}

// MARK: - My routine

/** The weekly plan editor: weekday columns, hour rows, a few blocks, an
 *  empty spot about to be filled and a block being dragged. */
@Composable
internal fun RoutineTimelineMock() {
    val row = 26.dp
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Callout(3, corner = 6.dp, trailing = true) {
            Row(Modifier.fillMaxWidth().height(12.dp), horizontalArrangement = Arrangement.spacedBy(4.dp),
                verticalAlignment = Alignment.CenterVertically) {
                Spacer(Modifier.width(14.dp))
                repeat(7) { Box(Modifier.weight(1f), contentAlignment = Alignment.Center) { TextBar(10.dp, 5.dp) } }
            }
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            Column(Modifier.width(14.dp)) {
                repeat(6) { Box(Modifier.height(row)) { TextBar(10.dp, 4.dp) } }
            }
            repeat(7) { day ->
                // The dragged block hangs over the next column.
                Box(Modifier.weight(1f).height(row * 6).zIndex(if (day == 1) 1f else 0f)) {
                    Box(Modifier.fillMaxSize().background(mockCard, ContinuousShape(5.dp)))
                    Column(Modifier.padding(top = 4.dp)) {
                        if (day < 5) PlanBlock(Icons.Filled.Phone, Color(0xFF007AFF)) else Spacer(Modifier.height(18.dp))
                    }
                    if (day == 1) {
                        Box(Modifier.offset(x = 6.dp, y = row * 2.4f)) {
                            Callout(2, corner = 5.dp, trailing = true) {
                                Box(Modifier.shadow(4.dp, ContinuousShape(5.dp))) {
                                    PlanBlock(Icons.Filled.TextFields, Color(0xFFAF52DE), opaque = true)
                                }
                            }
                        }
                    }
                    if (day == 3) {
                        Box(Modifier.offset(y = row * 3.6f).padding(horizontal = 2.dp)) {
                            Callout(1, corner = 5.dp) {
                                DashedBox(null, 18.dp, 5.dp, Modifier.fillMaxWidth()) { Glyph(Icons.Filled.Add, 10.dp) }
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun PlanBlock(icon: ImageVector, tint: Color, opaque: Boolean = false) {
    Box(Modifier.fillMaxWidth().padding(horizontal = 2.dp).height(18.dp)
        .background(if (opaque) mockCard else Color.Transparent, ContinuousShape(5.dp))
        .background(tint.copy(alpha = 0.2f), ContinuousShape(5.dp)),
        contentAlignment = Alignment.Center) { Glyph(icon, 9.dp, tint) }
}

/** The date strip, reduced to the looks a day can have: done (green), left
 *  undone (grey ring), a rest day (just the number), today filling. */
@Composable
internal fun RoutineDaysMock() {
    val green = Color(0xFF34C759)
    val grey4 = MaterialTheme.colorScheme.outline
    val grey5 = MaterialTheme.colorScheme.outlineVariant
    Row(Modifier.fillMaxWidth().padding(vertical = 18.dp)) {
        RoutineDay(1, Modifier.weight(1f)) {
            Box(Modifier.fillMaxSize().background(green, CircleShape))
            DayNumber(14, Color.White)
        }
        RoutineDay(null, Modifier.weight(1f)) {
            Box(Modifier.fillMaxSize().border(2.dp, grey4, CircleShape))
            DayNumber(15, secondaryInk)
        }
        RoutineDay(null, Modifier.weight(1f)) { DayNumber(16, tertiaryLabel()) }
        RoutineDay(2, Modifier.weight(1f)) {
            Canvas(Modifier.fillMaxSize()) {
                val w = 3.dp.toPx()
                drawCircle(grey5, radius = size.minDimension / 2 - w / 2, style = Stroke(w))
                drawArc(green, -90f, 360f * 0.55f, false, Offset(w, w),
                    Size(size.width - 2 * w, size.height - 2 * w), style = Stroke(w, cap = StrokeCap.Round))
            }
            DayNumber(17, MaterialTheme.colorScheme.onSurface)
        }
    }
}

@Composable
private fun DayNumber(n: Int, color: Color) =
    Text("$n", fontSize = 16.sp, fontWeight = FontWeight.SemiBold, color = color)

@Composable
private fun RoutineDay(callout: Int?, modifier: Modifier, face: @Composable () -> Unit) {
    Box(modifier, contentAlignment = Alignment.Center) {
        val circle: @Composable () -> Unit = {
            Box(Modifier.size(40.dp), contentAlignment = Alignment.Center) { face() }
        }
        if (callout != null) Callout(callout, corner = 20.dp) { circle() } else circle()
    }
}
