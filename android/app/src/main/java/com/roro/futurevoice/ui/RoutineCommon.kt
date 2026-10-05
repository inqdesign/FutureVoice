package com.roro.futurevoice.ui

import android.content.Context
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.snapping.SnapPosition
import androidx.compose.foundation.gestures.snapping.rememberSnapFlingBehavior
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.FormatQuote
import androidx.compose.material.icons.filled.GraphicEq
import androidx.compose.material.icons.filled.LocalFireDepartment
import androidx.compose.material.icons.filled.Phone
import androidx.compose.material.icons.filled.PlayCircle
import androidx.compose.material.icons.filled.Replay
import androidx.compose.material.icons.filled.TextFields
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material.icons.filled.ViewAgenda
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.roro.futurevoice.R
import com.roro.futurevoice.data.ActivityEventLog
import com.roro.futurevoice.data.DrillIngest
import com.roro.futurevoice.data.DrillStore
import com.roro.futurevoice.data.LanguageScope
import com.roro.futurevoice.data.PlannerDay
import com.roro.futurevoice.data.PracticeLog
import com.roro.futurevoice.data.PromiseJudge
import com.roro.futurevoice.data.SessionStore
import com.roro.futurevoice.data.StudyPlan
import com.roro.futurevoice.data.StudyScheduleStore
import com.roro.futurevoice.data.TalkTimeLog
import com.roro.futurevoice.data.WeeklyTestSettings
import com.roro.futurevoice.ui.brand.AppSurfaces
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.filter

/** Opens the routine editor from anywhere (the Review tab's Today card). */
object RoutineNav {
    val editorOpen = MutableStateFlow(false)
}

// MARK: - Look

/** One colour per kind (iOS): a theme's accent can be green, so a talk is
 *  system blue, never the accent. */
fun StudyPlan.Kind.color(): Color = when (this) {
    StudyPlan.Kind.TALK -> Color(0xFF007AFF)
    StudyPlan.Kind.SAY_IT_AGAIN -> Color(0xFF30B0C7)
    StudyPlan.Kind.REVIEW -> Color(0xFF34C759)
    StudyPlan.Kind.WORDS -> Color(0xFFAF52DE)
    StudyPlan.Kind.EXPRESSIONS -> Color(0xFFFF2D55)
    StudyPlan.Kind.SHADOW -> Color(0xFFFFCC00)
    StudyPlan.Kind.TEST -> Color(0xFFFF9500)
}

fun StudyPlan.Kind.icon(): ImageVector = when (this) {
    StudyPlan.Kind.TALK -> Icons.Filled.Phone
    StudyPlan.Kind.REVIEW -> Icons.Filled.ViewAgenda
    StudyPlan.Kind.WORDS -> Icons.Filled.TextFields
    StudyPlan.Kind.EXPRESSIONS -> Icons.Filled.FormatQuote
    StudyPlan.Kind.SHADOW -> Icons.Filled.GraphicEq
    StudyPlan.Kind.SAY_IT_AGAIN -> Icons.Filled.Replay
    StudyPlan.Kind.TEST -> Icons.Filled.Verified
}

fun PlannerDay.Actual.Kind.color(): Color = when (this) {
    PlannerDay.Actual.Kind.TALK -> Color(0xFF007AFF)
    PlannerDay.Actual.Kind.REVIEW -> Color(0xFF34C759)
    PlannerDay.Actual.Kind.SHADOW, PlannerDay.Actual.Kind.SAY_IT_AGAIN -> Color(0xFF30B0C7)
    PlannerDay.Actual.Kind.SCENE -> Color(0xFF8E8E93)
}

fun PlannerDay.Actual.Kind.icon(): ImageVector = when (this) {
    PlannerDay.Actual.Kind.TALK -> Icons.Filled.Phone
    PlannerDay.Actual.Kind.REVIEW -> Icons.Filled.ViewAgenda
    PlannerDay.Actual.Kind.SHADOW -> Icons.Filled.GraphicEq
    PlannerDay.Actual.Kind.SAY_IT_AGAIN -> Icons.Filled.Replay
    PlannerDay.Actual.Kind.SCENE -> Icons.Filled.PlayCircle
}

@Composable
fun PlannerDay.Actual.Kind.label(): String = stringResource(when (this) {
    PlannerDay.Actual.Kind.TALK -> R.string.routine_kind_talk
    PlannerDay.Actual.Kind.REVIEW -> R.string.routine_kind_review
    PlannerDay.Actual.Kind.SHADOW -> R.string.routine_kind_shadowing
    PlannerDay.Actual.Kind.SAY_IT_AGAIN -> R.string.routine_kind_say_it_again
    PlannerDay.Actual.Kind.SCENE -> R.string.routine_watch_scene
})

/** 24-hour "8:05" — the axis beside it is 24-hour, and a 12-hour time with
 *  its AM/PM dropped read 21:00 as "9:00". */
fun clockText(at: Long): String {
    val c = StudyPlan.cal(at, java.util.TimeZone.getDefault())
    return String.format(java.util.Locale.US, "%d:%02d",
        c.get(java.util.Calendar.HOUR_OF_DAY), c.get(java.util.Calendar.MINUTE))
}

fun clockText(minuteOfDay: Int): String =
    String.format(java.util.Locale.US, "%d:%02d", minuteOfDay / 60, minuteOfDay % 60)

// MARK: - The week, read once

/** Everything one week of the routine needs, read once per (week, plan). */
data class PlannerSnapshot(
    val days: List<Long>,
    val planned: Map<Long, List<StudyPlan.Occurrence>>,
    val actuals: Map<Long, List<PlannerDay.Actual>> = emptyMap(),
    val done: Map<Long, Set<String>> = emptyMap(),
    /** Each planned block's progress, 0…1, per day. */
    val progress: Map<Long, Map<String, Double>> = emptyMap(),
    /** Items each upcoming review slot will find waiting, keyed by the slot. */
    val reviewLoad: Map<Long, Int> = emptyMap(),
    val startHour: Int = 6,
    val endHour: Int = 24,
) {
    companion object {
        /** The weekly plan itself, with no dates: next week's days as
         *  stand-ins, one-off edits and rest weekdays left out. */
        fun master(c: Context, plan: StudyPlan, now: Long = System.currentTimeMillis()): PlannerSnapshot {
            val template = plan.copy(exceptions = emptyMap(), restDays = emptySet())
            val start = StudyPlan.addDays(StudyPlan.startOfRoutineWeek(now), 7) // Monday–Sunday
            val off = plan.offWeekdays ?: emptySet()
            val days = (0 until 7).map { StudyPlan.addDays(start, it) }
                .filter { StudyPlan.weekday(it) !in off }
            val test = WeeklyTestSettings.schedule(c)
            val planned = days.associateWith { template.occurrences(it, test) }
            val earliest = planned.values.flatten().filter { !it.anytime }
                .minOfOrNull { StudyPlan.cal(it.start, java.util.TimeZone.getDefault()).get(java.util.Calendar.HOUR_OF_DAY) }
            return PlannerSnapshot(days, planned, startHour = minOf(6, earliest ?: 6), endHour = 24)
        }

        suspend fun make(c: Context, weekStart: Long, plan: StudyPlan,
                         now: Long = System.currentTimeMillis()): PlannerSnapshot {
            val days = (0 until 7).map { StudyPlan.addDays(weekStart, it) }
            val weekEnd = StudyPlan.addDays(weekStart, 7)
            val test = WeeklyTestSettings.schedule(c)
            val sessions = LanguageScope.enrolled(c).flatMap {
                runCatching { SessionStore.shared(c).load(it) }.getOrDefault(emptyList())
            }.filter { s -> val end = s.endedAt; end != null && end >= weekStart && s.startedAt < weekEnd }
            val testDays = PromiseJudge.testDays(c)
            val planned = HashMap<Long, List<StudyPlan.Occurrence>>()
            val actuals = HashMap<Long, List<PlannerDay.Actual>>()
            val done = HashMap<Long, Set<String>>()
            val progress = HashMap<Long, Map<String, Double>>()
            for (day in days) {
                val next = StudyPlan.addDays(day, 1)
                val occ = plan.occurrences(day, test)
                val events = ActivityEventLog.events(c, day, next)
                val talks = sessions.filter { it.startedAt in day until next }.map {
                    PlannerDay.Talk(it.id, it.startedAt, it.endedAt ?: it.startedAt,
                        it.displayTitle ?: c.getString(R.string.conversation))
                }
                planned[day] = occ
                actuals[day] = PlannerDay.actuals(talks, events)
                val totals = PlannerDay.totals(TalkTimeLog.secondsToday(c, day), PracticeLog.day(c, day),
                    events, StudyPlan.dayKey(day) in testDays)
                val p = PlannerDay.progress(occ, totals)
                progress[day] = p
                done[day] = p.filterValues { it >= 1.0 }.keys
            }
            var load: Map<Long, Int> = emptyMap()
            if (plan.hasReviewBlocks) {
                val language = LanguageScope.active(c)
                val cards = runCatching {
                    DrillStore.shared(c).load(language).filterNot { DrillIngest.isRetired(it) }.map { it.nextReviewAt }
                }.getOrDefault(emptyList())
                val study = runCatching {
                    StudyScheduleStore.shared(c).snapshot(language).upcoming(0L).map { it.at }
                }.getOrDefault(emptyList())
                load = StudyPlan.reviewLoad(plan.reviewSlots(now, 21), cards + study)
            }
            return PlannerSnapshot(days, planned, actuals, done, progress, load)
        }
    }
}

// MARK: - Shared pieces

/** How long the promise has been kept, one line wherever it is shown. */
@Composable
fun StreakLine(streak: Int, modifier: Modifier = Modifier) {
    Row(modifier, verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        Icon(Icons.Filled.LocalFireDepartment, contentDescription = null,
            tint = if (streak > 0) Color(0xFFFF9500) else MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.size(16.dp))
        Text(if (streak > 0) stringResource(R.string.routine_kept_for_days, streak)
            else stringResource(R.string.routine_keep_it_today),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

/**
 * The header over a journey strip: what is chosen, how long the promise has
 * been kept, and a "Today" capsule when the strip is elsewhere — the same for
 * a day, a month and a year.
 */
@Composable
fun JourneyHeader(title: String, streak: Int, away: Boolean?, onToday: () -> Unit) {
    // away: null = on today; true = in the past; false = in the future.
    Row(Modifier.fillMaxWidth().padding(horizontal = 20.dp), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(title, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold, maxLines = 1)
            StreakLine(streak)
        }
        if (away != null) {
            Row(Modifier.clip(CircleShape).background(com.roro.futurevoice.ui.brand.iosFill())
                .clickable(onClick = onToday).padding(horizontal = 12.dp, vertical = 6.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                if (!away) Icon(Icons.AutoMirrored.Filled.ArrowBack, null, Modifier.size(14.dp),
                    tint = MaterialTheme.colorScheme.primary)
                Text(stringResource(R.string.routine_today), style = MaterialTheme.typography.labelLarge,
                    color = MaterialTheme.colorScheme.primary, fontWeight = FontWeight.SemiBold)
                if (away) Icon(Icons.AutoMirrored.Filled.ArrowForward, null, Modifier.size(14.dp),
                    tint = MaterialTheme.colorScheme.primary)
            }
        }
    }
}

/**
 * One continuous row you scroll through, the chosen item held in the middle
 * on a soft tile, the row running off both edges with a fade. Where the
 * scroll settles is the selection; a tap scrolls that item to the middle;
 * each new item in the middle ticks like a picker wheel.
 */
@Composable
fun <T> CenteredStrip(
    items: List<T>,
    selected: Int,
    onSelect: (Int) -> Unit,
    cellWidth: Dp = 52.dp,
    cell: @Composable (T, Boolean) -> Unit,
) {
    val state = rememberLazyListState(initialFirstVisibleItemIndex = selected.coerceAtLeast(0))
    val haptic = LocalHapticFeedback.current
    val currentSelected by rememberUpdatedState(selected)
    val select by rememberUpdatedState(onSelect)
    // The item in the middle once a scroll settles is the selection.
    LaunchedEffect(state) {
        snapshotFlow { state.isScrollInProgress to state.firstVisibleItemIndex }
            .filter { !it.first }
            .distinctUntilChanged()
            .collect { (_, _) ->
                val info = state.layoutInfo
                val center = (info.viewportStartOffset + info.viewportEndOffset) / 2
                val mid = info.visibleItemsInfo.minByOrNull { kotlin.math.abs(it.offset + it.size / 2 - center) }
                if (mid != null && mid.index != currentSelected) {
                    haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                    select(mid.index)
                }
            }
    }
    // A selection made elsewhere (a tap, a swipe of the day below) scrolls here.
    LaunchedEffect(selected) {
        val info = state.layoutInfo
        val center = (info.viewportStartOffset + info.viewportEndOffset) / 2
        val mid = info.visibleItemsInfo.minByOrNull { kotlin.math.abs(it.offset + it.size / 2 - center) }
        if (mid?.index != selected && selected in items.indices) state.animateScrollToItem(selected)
    }
    BoxWithConstraints(Modifier.fillMaxWidth().height(76.dp)) {
        val side = ((maxWidth - cellWidth) / 2).coerceAtLeast(0.dp)
        LazyRow(
            state = state,
            flingBehavior = rememberSnapFlingBehavior(state, SnapPosition.Center),
            contentPadding = PaddingValues(horizontal = side),
            horizontalArrangement = Arrangement.spacedBy(6.dp),
            modifier = Modifier.fillMaxSize()
                .graphicsLayer(compositingStrategy = CompositingStrategy.Offscreen)
                .drawWithContent {
                    drawContent()
                    drawRect(Brush.horizontalGradient(
                        0f to Color.Transparent, 0.12f to Color.Black,
                        0.88f to Color.Black, 1f to Color.Transparent), blendMode = BlendMode.DstIn)
                },
        ) {
            itemsIndexed(items) { i, item ->
                val isSel = i == selected
                Box(
                    Modifier.width(cellWidth).height(72.dp)
                        .clip(RoundedCornerShape(16.dp))
                        .background(if (isSel) AppSurfaces.card else Color.Transparent)
                        .border(0.5.dp, if (isSel) MaterialTheme.colorScheme.outlineVariant else Color.Transparent,
                            RoundedCornerShape(16.dp))
                        .clickable { if (i != selected) { haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove); select(i) } },
                    contentAlignment = Alignment.Center,
                ) { cell(item, isSel) }
            }
        }
    }
}

/**
 * The panel a journey's content lives in: pinned to the bottom of the page,
 * its height never following its content, which scrolls inside it. [footer]
 * sits at the panel's foot — a short day leaves the space above it, a long
 * one pushes it down.
 */
@Composable
fun ColumnScope.PinnedPanel(footer: (@Composable ColumnScope.() -> Unit)? = null,
                            content: @Composable ColumnScope.() -> Unit) {
    BoxWithConstraints(
        Modifier.weight(1f).fillMaxWidth()
            .clip(RoundedCornerShape(topStart = 28.dp, topEnd = 28.dp))
            .background(AppSurfaces.card),
    ) {
        val minH = maxHeight
        Column(
            Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).heightIn(min = minH)
                .padding(start = 20.dp, end = 20.dp, top = 12.dp, bottom = 24.dp),
            verticalArrangement = Arrangement.SpaceBetween,
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(14.dp)) { content() }
            if (footer != null) Column(verticalArrangement = Arrangement.spacedBy(14.dp)) { footer() }
        }
    }
}

/** Empty circle → filling ring → green tick. */
@Composable
fun ProgressRing(progress: Double, faded: Boolean = false, size: Dp = 22.dp) {
    val green = Color(0xFF34C759)
    if (progress >= 1.0) {
        Icon(Icons.Filled.CheckCircle, contentDescription = null, tint = green, modifier = Modifier.size(size + 2.dp))
        return
    }
    val track = MaterialTheme.colorScheme.outlineVariant.copy(alpha = if (faded) 0.6f else 1f)
    Canvas(Modifier.size(size)) {
        val w = 2.dp.toPx()
        drawCircle(track, radius = (this.size.minDimension - w) / 2, style = Stroke(w))
        if (progress > 0) {
            val inset = 1.5.dp.toPx()
            drawArc(green, -90f, (360 * progress).toFloat(), false,
                topLeft = Offset(inset, inset), size = Size(this.size.width - 2 * inset, this.size.height - 2 * inset),
                style = Stroke(2.5.dp.toPx(), cap = StrokeCap.Round))
        }
    }
}

/** A day circle in a strip: kept (green), missed (grey ring), rest (just the
 *  number), today filling as it goes, a planned future day dashed. */
@Composable
fun DayMarkCircle(number: String, mark: DayMark, size: Dp = 32.dp) {
    val green = Color(0xFF34C759)
    val grey = MaterialTheme.colorScheme.outlineVariant
    val faint = MaterialTheme.colorScheme.surfaceVariant
    Box(Modifier.size(size), contentAlignment = Alignment.Center) {
        Canvas(Modifier.fillMaxSize()) {
            val r = this.size.minDimension / 2
            when (mark) {
                DayMark.Kept -> drawCircle(green, r)
                DayMark.Missed -> drawCircle(grey, r - 1.dp.toPx(), style = Stroke(2.dp.toPx()))
                DayMark.Rest -> Unit
                is DayMark.Today -> {
                    val w = 3.dp.toPx()
                    drawCircle(faint, r - w / 2, style = Stroke(w))
                    drawArc(green, -90f, (360 * maxOf(0.001, mark.progress)).toFloat(), false,
                        topLeft = Offset(w / 2, w / 2), size = Size(this.size.width - w, this.size.height - w),
                        style = Stroke(w, cap = StrokeCap.Round))
                }
                is DayMark.Ahead -> if (mark.planned) drawCircle(grey, r - 1.dp.toPx(),
                    style = Stroke(1.5.dp.toPx(), pathEffect = androidx.compose.ui.graphics.PathEffect
                        .dashPathEffect(floatArrayOf(3.dp.toPx(), 3.dp.toPx()))))
            }
        }
        Text(number, style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.SemiBold,
            color = when (mark) {
                DayMark.Kept -> Color.White
                DayMark.Rest -> MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f)
                is DayMark.Today -> MaterialTheme.colorScheme.onSurface
                else -> MaterialTheme.colorScheme.onSurfaceVariant
            })
    }
}

sealed interface DayMark {
    data object Kept : DayMark
    data object Missed : DayMark
    data object Rest : DayMark
    data class Today(val progress: Double) : DayMark
    data class Ahead(val planned: Boolean) : DayMark
}

/** Dp helper for the editor's grid maths. */
@Composable
fun Dp.px(): Float = with(LocalDensity.current) { this@px.toPx() }
