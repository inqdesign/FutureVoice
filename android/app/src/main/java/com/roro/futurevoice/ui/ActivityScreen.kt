package com.roro.futurevoice.ui

import android.content.Context
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.GraphicEq
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.VerticalDivider
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.roro.futurevoice.R
import com.roro.futurevoice.data.DailyCallStore
import com.roro.futurevoice.data.DayCardStore
import com.roro.futurevoice.data.PlannerDay
import com.roro.futurevoice.data.PracticeLog
import com.roro.futurevoice.data.PromiseJudge
import com.roro.futurevoice.data.PromiseLedger
import com.roro.futurevoice.data.PromiseStreak
import com.roro.futurevoice.data.RoutineText
import com.roro.futurevoice.data.SessionStore
import com.roro.futurevoice.data.StoreEvents
import com.roro.futurevoice.data.StudyPlan
import com.roro.futurevoice.data.StudyPlanStore
import com.roro.futurevoice.data.TalkTime
import com.roro.futurevoice.data.TalkTimeLog
import com.roro.futurevoice.data.WeeklyTestSettings
import com.roro.futurevoice.talk.Session
import com.roro.futurevoice.ui.brand.AppSurfaces
import com.roro.futurevoice.ui.brand.ContinuousShape
import com.roro.futurevoice.ui.brand.DayCard
import com.roro.futurevoice.ui.brand.DayCardData
import com.roro.futurevoice.ui.brand.DayCardFormat
import com.roro.futurevoice.ui.brand.FutureselfTheme
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

/** The meter PRUNES at 45 days; older minutes come from frozen day cards. */
private const val TALK_LOG_DAYS = 45

/** How far back the record (and the streak's active days) is read. */
private const val RECORD_SCAN_DAYS = 1100

private enum class Mode(val labelRes: Int) {
    DAY(R.string.routine_day), MONTH(R.string.routine_month), YEAR(R.string.routine_year)
}

private data class Record(
    val seconds: Map<String, Int> = emptyMap(),
    val active: Set<String> = emptySet(),
    val totalSeconds: Int = 0,
)

/**
 * "My routine" — a journal of the learner's routine (iOS `ActivityView`,
 * 1.1.4). The view switch spans the top (Day | Month | Year); under it the
 * streak and the chosen period are ONE header, then a strip of days (or
 * months, or years) to scroll through, then a panel pinned to the bottom: the
 * day's list (what was planned, what happened, a ring per block) with the
 * day's share card at its foot, or the period's calendar.
 *
 * Reached from Talk's streak chip. Edit opens the weekly plan editor.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ActivityScreen(
    language: String,
    onOpenTalk: (String) -> Unit,
    onBack: () -> Unit,
    /** A routine line asked for a free talk. */
    onStartTalk: () -> Unit = {},
    /** A review line: the review deck. */
    onOpenReview: () -> Unit = {},
    /** The weekly test line. */
    onOpenTest: () -> Unit = {},
    /** Capture: open on this view, or straight in the editor. */
    initialMode: String? = null,
    startEditing: Boolean = false,
) {
    androidx.activity.compose.BackHandler(onBack = onBack)
    val context = LocalContext.current
    val revision by StoreEvents.revision.collectAsStateWithLifecycle()
    val plan by StudyPlanStore.plan.collectAsStateWithLifecycle()
    var mode by remember { mutableStateOf(Mode.entries.firstOrNull { it.name.equals(initialMode, true) } ?: Mode.DAY) }
    val today = StudyPlan.startOfDay(System.currentTimeMillis())
    var selected by remember { mutableStateOf(today) }
    var periodAnchor by remember { mutableStateOf(startOfMonth(today)) }
    var record by remember { mutableStateOf(Record()) }
    var activeKeys by remember { mutableStateOf<Set<String>>(emptySet()) }
    var streak by remember { mutableStateOf(0) }
    var sessions by remember { mutableStateOf<List<Session>>(emptyList()) }
    var snapshot by remember { mutableStateOf<PlannerSnapshot?>(null) }
    var editing by remember { mutableStateOf(startEditing) }
    var picking by remember { mutableStateOf(false) }
    var photos by remember { mutableStateOf<Map<String, ImageBitmap>>(emptyMap()) }
    var selectedPhoto by remember { mutableStateOf<ImageBitmap?>(null) }
    var showCard by remember { mutableStateOf(false) }

    LaunchedEffect(language, revision) {
        StudyPlanStore.current(context)
        val talks = SessionStore.shared(context).load(language)
        sessions = talks
        withContext(Dispatchers.IO) {
            runCatching { PromiseJudge.refresh(context) }
            record = readRecord(context, talks)
            activeKeys = TalkTimeLog.activeDayKeys(context, RECORD_SCAN_DAYS)
            streak = TalkTimeLog.streakDays(context)
        }
    }
    val weekStart = StudyPlan.startOfWeek(selected)
    LaunchedEffect(weekStart, plan, revision) {
        snapshot = withContext(Dispatchers.IO) { PlannerSnapshot.make(context, weekStart, plan) }
    }
    LaunchedEffect(periodAnchor, mode) {
        photos = if (mode == Mode.MONTH) withContext(Dispatchers.IO) {
            daysIn(periodAnchor).filterNotNull().mapNotNull { day ->
                DayCardStore.photo(context, day)?.let { dayKey(day) to it.asImageBitmap() }
            }.toMap()
        } else emptyMap()
    }
    LaunchedEffect(selected) {
        selectedPhoto = withContext(Dispatchers.IO) { DayCardStore.photo(context, selected)?.asImageBitmap() }
    }

    if (editing) {
        WeeklyPlanEditor(onClose = { editing = false })
        return
    }
    if (picking) {
        SayItAgainPicker(language = language, onClose = { picking = false; StoreEvents.bump() })
        return
    }

    fun standing(day: Long) = PromiseStreak.standing(context, day) { dayKey(it) in activeKeys }
    val isPromise = plan.streakSince != null

    fun open(kind: StudyPlan.Kind) {
        com.roro.futurevoice.core.Analytics.capture("routine_line_opened", mapOf("kind" to kind.raw))
        when (kind) {
            StudyPlan.Kind.TALK -> onStartTalk()
            StudyPlan.Kind.SAY_IT_AGAIN -> picking = true
            StudyPlan.Kind.TEST -> onOpenTest()
            else -> onOpenReview()
        }
    }

    Scaffold(
        containerColor = AppSurfaces.ground,
        topBar = {
            TopAppBar(
                colors = AppSurfaces.topBarColors(),
                title = { Text(stringResource(R.string.routine_my_routine)) },
                navigationIcon = {
                    IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = null) }
                },
                actions = {
                    // The page is the routine, so its Edit is the page's own.
                    TextButton(onClick = {
                        com.roro.futurevoice.core.Analytics.capture("plan_edit_opened")
                        editing = true
                    }) { Text(stringResource(R.string.routine_edit)) }
                },
            )
        },
    ) { padding ->
        Column(
            Modifier.padding(padding).fillMaxSize().background(AppSurfaces.ground).padding(top = 8.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            com.roro.futurevoice.ui.brand.IosSegmented(Mode.entries.map { stringResource(it.labelRes) },
                Mode.entries.indexOf(mode), {
                    val next = Mode.entries[it]
                    if (next != Mode.DAY) periodAnchor = periodKey(selected, next)
                    mode = next
                }, Modifier.fillMaxWidth().padding(horizontal = 20.dp))

            if (mode == Mode.DAY) {
                val days = remember(today) { (-180..30).map { StudyPlan.addDays(today, it) } }
                val idx = days.indexOfFirst { it == selected }.coerceAtLeast(0)
                JourneyHeader(
                    title = skeleton(selected, "EEEMMMd"),
                    streak = streak,
                    away = if (selected == today) null else selected < today,
                    onToday = { selected = today },
                )
                CenteredStrip(days, idx, { selected = days[it] }) { d, isSel ->
                    Column(horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        Text(SimpleDateFormat("EEEEE", Locale.getDefault()).format(Date(d)),
                            style = MaterialTheme.typography.labelSmall,
                            fontWeight = if (isSel) FontWeight.SemiBold else FontWeight.Normal,
                            color = if (isSel) MaterialTheme.colorScheme.onSurface
                            else MaterialTheme.colorScheme.onSurfaceVariant)
                        DayMarkCircle(dayOfMonth(d), mark(context, d, today, plan, isPromise, ::standing))
                    }
                }
                val daySessions = sessions.filter { StudyPlan.isSameDay(it.endedAt ?: it.startedAt, selected) }
                PinnedPanel(footer = {
                    DayJournal(context, selected, record.seconds[dayKey(selected)] ?: 0, daySessions,
                        selectedPhoto) { showCard = true }
                }) {
                    DayList(
                        snapshot = snapshot, day = selected, isPromise = isPromise,
                        onSwipe = { selected = StudyPlan.addDays(selected, it) },
                        onOpen = ::open, onOpenTalk = onOpenTalk,
                    )
                }
            } else {
                val periods = remember(mode, today) { periodsFor(mode, today) }
                val idx = periods.indexOf(periodKey(periodAnchor, mode)).takeIf { it >= 0 } ?: periods.lastIndex
                val current = periodKey(today, mode)
                JourneyHeader(
                    title = periodTitle(periodAnchor, mode),
                    streak = streak,
                    away = if (periodKey(periodAnchor, mode) == current) null else true,
                    onToday = { periodAnchor = current },
                )
                // Keyed by the view: months and years are different strips.
                androidx.compose.runtime.key(mode) {
                    CenteredStrip(periods, idx, { periodAnchor = periods[it] }) { p, isSel ->
                        PeriodCell(p, mode, isSel, today, ::standing)
                    }
                }
                PinnedPanel(footer = { StatsBar(record, periodAnchor, mode) }) {
                    if (mode == Mode.MONTH) {
                        MonthWall(periodAnchor, record.seconds, record.active, photos, selected) {
                            selected = it; mode = Mode.DAY
                        }
                    } else {
                        YearWall(periodAnchor, record.seconds, record.active, selected) {
                            selected = it; mode = Mode.DAY
                        }
                    }
                    Text(periodFooter(record, periodAnchor, mode),
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
    }

    if (showCard) {
        val daySessions = sessions.filter { StudyPlan.isSameDay(it.endedAt ?: it.startedAt, selected) }
        val secs = record.seconds[dayKey(selected)] ?: 0
        val card = remember(selected, secs, daySessions) {
            DayCardStore.resolve(context, selected) { DayCardStore.make(context, selected, secs, daySessions) }
        }
        DayCardSheet(card) { showCard = false }
    }
}

// MARK: - The day strip's marks

private fun mark(c: Context, d: Long, today: Long, plan: StudyPlan, isPromise: Boolean,
                 standing: (Long) -> PromiseStreak.Standing): DayMark {
    if (d > today) return DayMark.Ahead(plan.occurrences(d, WeeklyTestSettings.schedule(c)).isNotEmpty())
    val s = standing(d)
    if (d == today) {
        if (s == PromiseStreak.Standing.KEPT) return DayMark.Kept
        val e = PromiseLedger.entry(c, d)
        if (isPromise && e != null && e.planned > 0) return DayMark.Today(e.done.toDouble() / e.planned)
        return DayMark.Today(0.0)
    }
    return when (s) {
        PromiseStreak.Standing.KEPT -> DayMark.Kept
        PromiseStreak.Standing.MISSED -> DayMark.Missed
        PromiseStreak.Standing.REST -> DayMark.Rest
    }
}

// MARK: - The day

private sealed interface DayItem {
    val key: String
    val start: Long
    data class Plan(val occ: StudyPlan.Occurrence, val done: Boolean) : DayItem {
        override val key get() = "p" + occ.id
        override val start get() = occ.start
    }
    data class Actual(val a: PlannerDay.Actual) : DayItem {
        override val key get() = "a" + a.id
        override val start get() = a.start
    }
}

/**
 * The day as a list in time order, drawn like a Reminders row — time · the
 * kind's icon (the ONLY colour) · title over one detail line · a ring that
 * fills as the block is done. What happened outside the plan is listed too,
 * so the day reads as the day. Every line is a door. Swipe for the next or
 * previous day.
 */
@Composable
private fun DayList(
    snapshot: PlannerSnapshot?,
    day: Long,
    isPromise: Boolean,
    onSwipe: (Int) -> Unit,
    onOpen: (StudyPlan.Kind) -> Unit,
    onOpenTalk: (String) -> Unit,
) {
    val context = LocalContext.current
    val res = context.resources
    val haptic = LocalHapticFeedback.current
    val key = snapshot?.days?.firstOrNull { it == day }
    val planned = key?.let { snapshot.planned[it] }.orEmpty()
    val actuals = key?.let { snapshot.actuals[it] }.orEmpty()
    val done = key?.let { snapshot.done[it] }.orEmpty()
    val progress = key?.let { snapshot.progress[it] }.orEmpty()
    val items = (planned.map { DayItem.Plan(it, it.id in done) } +
        PlannerDay.unplanned(actuals, planned).map { DayItem.Actual(it) }).sortedBy { it.start }
    val talkThatDidIt = actuals.lastOrNull { it.kind == PlannerDay.Actual.Kind.TALK }?.sessionId
    val callOn = DailyCallStore.isEnabled(context)

    Column(
        Modifier.fillMaxWidth().pointerInput(day) {
            var dx = 0f
            detectHorizontalDragGestures(
                onDragStart = { dx = 0f },
                onDragEnd = {
                    if (kotlin.math.abs(dx) > 60.dp.toPx()) {
                        haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                        onSwipe(if (dx < 0) 1 else -1)
                    }
                },
            ) { _, amount -> dx += amount }
        },
    ) {
        if (snapshot == null) return@Column
        if (items.isEmpty()) {
            Text(stringResource(if (isPromise) R.string.routine_rest_day else R.string.routine_nothing_planned),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(vertical = 12.dp))
        }
        items.forEachIndexed { i, item ->
            if (i > 0) HorizontalDivider(Modifier.padding(start = 48.dp), color = MaterialTheme.colorScheme.outlineVariant)
            when (item) {
                is DayItem.Actual -> {
                    val a = item.a
                    RoutineRow(
                        time = "${clockText(a.start)}–${clockText(a.end)}",
                        icon = a.kind.icon(), tint = a.kind.color(),
                        title = a.title ?: a.kind.label(),
                        detail = stringResource(R.string.routine_extra),
                        progress = 1.0,
                        onClick = {
                            val id = a.sessionId
                            if (id != null) onOpenTalk(id) else a.planKind?.let(onOpen)
                        },
                    )
                }
                is DayItem.Plan -> {
                    val occ = item.occ
                    val lapsed = !item.done && occ.isOver()
                    val p = if (item.done) 1.0 else progress[occ.id] ?: 0.0
                    val detail: String? = when {
                        item.done -> null
                        p > 0 && occ.amount > 1 -> stringResource(R.string.routine_n_of,
                            (p * occ.amount).toInt(), RoutineText.amount(res, occ.kind, occ.amount))
                        occ.kind == StudyPlan.Kind.REVIEW && (snapshot.reviewLoad[occ.start] ?: 0) > 0 ->
                            stringResource(R.string.routine_about_waiting, snapshot.reviewLoad[occ.start] ?: 0)
                        occ.kind == StudyPlan.Kind.SAY_IT_AGAIN -> stringResource(R.string.routine_pick_a_talk)
                        // A timed talk IS the daily call; with the call off it won't ring.
                        occ.kind == StudyPlan.Kind.TALK && !occ.anytime && !callOn ->
                            stringResource(R.string.routine_no_call)
                        else -> null
                    }
                    RoutineRow(
                        time = if (occ.anytime) stringResource(R.string.routine_anytime) else clockText(occ.start),
                        icon = occ.kind.icon(),
                        tint = if (lapsed) MaterialTheme.colorScheme.onSurfaceVariant else occ.kind.color(),
                        title = RoutineText.titled(res, occ.kind, occ.amount),
                        detail = detail, progress = p, faded = lapsed,
                        onClick = {
                            val id = talkThatDidIt
                            if (occ.kind == StudyPlan.Kind.TALK && item.done && id != null) onOpenTalk(id)
                            else onOpen(occ.kind)
                        },
                    )
                }
            }
        }
    }
}

@Composable
private fun RoutineRow(time: String, icon: ImageVector, tint: Color, title: String, detail: String?,
                       progress: Double, faded: Boolean = false, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().clickable(onClick = onClick).padding(vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Box(Modifier.size(36.dp).clip(ContinuousShape(10.dp)).background(tint.copy(alpha = 0.14f)),
            contentAlignment = Alignment.Center) {
            Icon(icon, contentDescription = null, tint = tint, modifier = Modifier.size(18.dp))
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(title, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.Medium,
                color = if (faded) MaterialTheme.colorScheme.onSurfaceVariant else MaterialTheme.colorScheme.onSurface,
                maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(listOfNotNull(time, detail).joinToString(" · "), style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        ProgressRing(progress, faded)
    }
}

/**
 * The foot of the day's panel: its share card beside the day's numbers. The
 * day's talks are rows in the list above, so they aren't listed again here.
 * An empty day has nothing to put on a card, so it draws nothing.
 */
@Composable
private fun DayJournal(context: Context, day: Long, seconds: Int, talks: List<Session>,
                       photo: ImageBitmap?, onShare: () -> Unit) {
    val log = remember(day, seconds) { PracticeLog.day(context, day) }
    val shadowed = log?.shadowReps ?: 0
    val reviewed = log?.drillReps ?: 0
    val card = remember(day, seconds, talks) {
        DayCardStore.resolve(context, day) { DayCardStore.make(context, day, seconds, talks) }
    }
    val study = card.studyMinutes
    if (seconds == 0 && talks.isEmpty() && shadowed == 0 && reviewed == 0 && study == 0) return
    val theme = remember { FutureselfTheme.stored(context).ordinal }
    HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
    Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
        Box(Modifier.size(PREVIEW_WIDTH, PREVIEW_WIDTH * 5 / 4).clip(ContinuousShape(10.dp)).clickable(onClick = onShare),
            contentAlignment = Alignment.Center) {
            Box(Modifier.requiredSize(DayCardFormat.FEED.width.dp, DayCardFormat.FEED.height.dp)
                .scale(PREVIEW_WIDTH / DayCardFormat.FEED.width.dp)) {
                DayCard(card, photo, theme = theme)
            }
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(Modifier.fillMaxWidth().clickable(onClick = onShare), horizontalArrangement = Arrangement.End,
                verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Filled.Share, null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(16.dp))
                Spacer(Modifier.width(4.dp))
                Text(stringResource(R.string.routine_share_card), style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.primary)
            }
            Fact(stringResource(R.string.routine_talk_time), TalkTime.clock(seconds))
            if (talks.isNotEmpty()) Fact(stringResource(R.string.routine_talks), "${talks.size}")
            if (study > 0) Fact(stringResource(R.string.routine_study_time), stringResource(R.string.routine_n_min, study))
            if (shadowed > 0) Fact(stringResource(R.string.routine_kind_shadowing), "$shadowed")
            if (reviewed > 0) Fact(stringResource(R.string.routine_drills), "$reviewed")
        }
    }
}

private val PREVIEW_WIDTH = 132.dp

@Composable
private fun Fact(label: String, value: String) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Text(label, style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.weight(1f), maxLines = 1)
        Text(value, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold)
    }
}

// MARK: - Month / year

/** One month (or year) in the strip: its name, and a ring holding the days
 *  the promise was kept in it — filled as that share of its counted days. */
@Composable
private fun PeriodCell(start: Long, mode: Mode, isSel: Boolean, today: Long,
                       standing: (Long) -> PromiseStreak.Standing) {
    val (kept, share) = remember(start, mode, today) {
        val end = minOf(shiftPeriod(start, mode, 1), StudyPlan.addDays(today, 1))
        var k = 0; var counted = 0
        var d = start
        while (d < end) {
            when (standing(d)) {
                PromiseStreak.Standing.KEPT -> { k++; counted++ }
                PromiseStreak.Standing.MISSED -> counted++
                PromiseStreak.Standing.REST -> Unit
            }
            d = StudyPlan.addDays(d, 1)
        }
        k to if (counted > 0) k.toFloat() / counted else 0f
    }
    val green = Color(0xFF34C759)
    val track = MaterialTheme.colorScheme.surfaceVariant
    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(SimpleDateFormat(if (mode == Mode.YEAR) "yyyy" else "MMM", Locale.getDefault()).format(Date(start)),
            style = MaterialTheme.typography.labelSmall, maxLines = 1,
            fontWeight = if (isSel) FontWeight.SemiBold else FontWeight.Normal,
            color = if (isSel) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.onSurfaceVariant)
        Box(Modifier.size(32.dp), contentAlignment = Alignment.Center) {
            Canvas(Modifier.fillMaxSize()) {
                val w = 3.dp.toPx()
                drawCircle(track, this.size.minDimension / 2 - w / 2, style = Stroke(w))
                if (share > 0) drawArc(green, -90f, 360 * share, false, topLeft = Offset(w / 2, w / 2),
                    size = Size(this.size.width - w, this.size.height - w), style = Stroke(w, cap = StrokeCap.Round))
            }
            Text("$kept", style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.SemiBold,
                color = if (kept > 0) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

/** The past's totals. The streak lives in the header, by the learner's own rule. */
@Composable
private fun StatsBar(record: Record, anchor: Long, mode: Mode) {
    val minutes = maxOf(0, record.totalSeconds) / 60
    val total = if (minutes < 60) stringResource(R.string.lld_m, minutes)
    else stringResource(R.string.lld_h_lld_m, minutes / 60, minutes % 60)
    Row(Modifier.fillMaxWidth().background(AppSurfaces.ground, ContinuousShape(16.dp)).padding(vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically) {
        Stat(Icons.Filled.GraphicEq, total, stringResource(R.string.routine_total), Modifier.weight(1f))
        VerticalDivider(Modifier.height(26.dp), color = MaterialTheme.colorScheme.outlineVariant)
        Stat(Icons.Filled.CalendarMonth, "${record.active.size}", stringResource(R.string.routine_days), Modifier.weight(1f))
    }
}

@Composable
private fun Stat(icon: ImageVector, value: String, label: String, modifier: Modifier) {
    Column(modifier, horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(3.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            Icon(icon, null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(12.dp))
            Text(value, style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.Bold, maxLines = 1)
        }
        Text(label, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

/** ONE line under the grid: how much of the period was used, then how it
 *  compares with the one before. */
@Composable
private fun periodFooter(record: Record, anchor: Long, mode: Mode): String {
    val days = periodDays(anchor, mode)
    val active = days.count { dayKey(it) in record.active }
    fun minutes(of: List<Long>) = of.sumOf { (record.seconds[dayKey(it)] ?: 0) / 60 }
    val mins = minutes(days)
    val summary = if (mode == Mode.MONTH) stringResource(R.string.routine_active_days_min, active, mins)
    else stringResource(R.string.routine_active_days_min_year, active, mins)
    val prev = shiftPeriod(anchor, mode, -1)
    val prevMins = minutes(periodDays(prev, mode))
    if (prevMins <= 0) return summary
    val delta = mins - prevMins
    val name = SimpleDateFormat(if (mode == Mode.MONTH) "LLLL" else "yyyy", Locale.getDefault()).format(Date(prev))
    return summary + " · " + stringResource(R.string.routine_min_vs, (if (delta >= 0) "+" else "") + delta, name)
}

/** The month as a photo wall: full-width rounded tiles, a photo day shows its
 *  photo, an active day its heat blue, an empty day a faint fill. */
@Composable
private fun MonthWall(month: Long, secondsByDay: Map<String, Int>, activeDays: Set<String>,
                      photos: Map<String, ImageBitmap>, selected: Long, onSelect: (Long) -> Unit) {
    val accent = MaterialTheme.colorScheme.primary
    val today = StudyPlan.startOfDay(System.currentTimeMillis())
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            weekdayLabels().forEach { label ->
                Text(label, style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.weight(1f),
                    textAlign = androidx.compose.ui.text.style.TextAlign.Center)
            }
        }
        daysIn(month).chunked(7).forEach { week ->
            Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                week.forEach { day ->
                    if (day == null) { Box(Modifier.weight(1f).aspectRatio(1f)); return@forEach }
                    val key = dayKey(day)
                    val seconds = secondsByDay[key] ?: 0
                    val photo = photos[key]
                    val future = day > today
                    val active = key in activeDays
                    val heat = heatAlpha(seconds)
                    Box(Modifier.weight(1f).aspectRatio(1f).clip(ContinuousShape(9.dp))
                        .background(if (active) accent.copy(alpha = heat)
                        else MaterialTheme.colorScheme.surfaceVariant.copy(alpha = if (future) 0.3f else 0.55f))
                        .border(if (day == selected) 2.5.dp else 1.5.dp, when {
                            day == selected -> accent
                            day == today -> accent.copy(alpha = 0.45f)
                            else -> Color.Transparent
                        }, ContinuousShape(9.dp))
                        .clickable(enabled = !future) { onSelect(day) }) {
                        if (photo != null) Image(photo, null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
                        Text(dayOfMonth(day), style = MaterialTheme.typography.labelSmall, fontWeight = FontWeight.SemiBold,
                            color = if (photo != null || (active && heat >= 0.6f)) Color.White
                            else MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(4.dp))
                    }
                }
            }
        }
    }
}

/** The year as twelve mini months, three across — no photos (a cell this
 *  size shows one as a smudge). */
@Composable
private fun YearWall(year: Long, secondsByDay: Map<String, Int>, activeDays: Set<String>,
                     selected: Long, onSelect: (Long) -> Unit) {
    val accent = MaterialTheme.colorScheme.primary
    val today = StudyPlan.startOfDay(System.currentTimeMillis())
    Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
        monthsOfYear(year).chunked(3).forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                row.forEach { month ->
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(5.dp)) {
                        Text(SimpleDateFormat("MMM", Locale.getDefault()).format(Date(month)),
                            style = MaterialTheme.typography.labelSmall, fontWeight = FontWeight.Medium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                            daysIn(month).chunked(7).forEach { week ->
                                Row(horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                                    week.forEach { day ->
                                        if (day == null) { Box(Modifier.weight(1f).aspectRatio(1f)); return@forEach }
                                        val key = dayKey(day)
                                        val future = day > today
                                        Box(Modifier.weight(1f).aspectRatio(1f).clip(RoundedCornerShape(2.dp))
                                            .background(if (key in activeDays) accent.copy(alpha = heatAlpha(secondsByDay[key] ?: 0))
                                            else MaterialTheme.colorScheme.surfaceVariant.copy(alpha = if (future) 0.4f else 1f))
                                            .border(if (day == selected) 1.5.dp else if (day == today) 1.dp else 0.dp,
                                                if (day == selected || day == today) accent else Color.Transparent,
                                                RoundedCornerShape(2.dp))
                                            .clickable(enabled = !future) { onSelect(day) })
                                    }
                                }
                            }
                        }
                    }
                }
                repeat(3 - row.size) { Box(Modifier.weight(1f)) }
            }
        }
    }
}

// MARK: - The record

/**
 * Everything the calendar draws, read once: the METER while it holds the day,
 * then that day's frozen card once the meter has pruned it. A day with
 * neither can still be ACTIVE — a saved talk or a practice rep says the
 * learner showed up.
 */
private fun readRecord(context: Context, talks: List<Session>): Record {
    val now = System.currentTimeMillis()
    val today = StudyPlan.startOfDay(now)
    val metered = TalkTimeLog.recentSeconds(context, TALK_LOG_DAYS, now).associate { (at, s) -> dayKey(at) to s }
    val talkDays = talks.map { dayKey(it.endedAt ?: it.startedAt) }.toSet()
    val windowStart = StudyPlan.addDays(today, -(TALK_LOG_DAYS - 1))
    val firstTalk = talks.minOfOrNull { it.endedAt ?: it.startedAt }?.let { StudyPlan.startOfDay(it) }
    val start = maxOf(minOf(firstTalk ?: windowStart, windowStart), StudyPlan.addDays(today, -RECORD_SCAN_DAYS))
    val days = generateSequence(start) { StudyPlan.addDays(it, 1) }.takeWhile { it <= today }.toList()
    val practice = PracticeLog.recent(context, days.size, now).toMap()
    val seconds = HashMap<String, Int>()
    val active = HashSet<String>()
    days.forEach { day ->
        val key = dayKey(day)
        val secs = metered[key]?.takeIf { it > 0 } ?: ((DayCardStore.snapshot(context, day)?.talkMinutes ?: 0) * 60)
        if (secs > 0) seconds[key] = secs
        if (secs > 0 || key in talkDays || (practice[key]?.didSomething == true)) active += key
    }
    return Record(seconds, active, seconds.values.sum())
}

// MARK: - Calendar arithmetic

private fun cal(at: Long) = Calendar.getInstance().apply { timeInMillis = at }

private fun startOfMonth(at: Long): Long =
    cal(StudyPlan.startOfDay(at)).apply { set(Calendar.DAY_OF_MONTH, 1) }.timeInMillis

private fun startOfYear(at: Long): Long = cal(startOfMonth(at)).apply { set(Calendar.DAY_OF_YEAR, 1) }.timeInMillis

private fun periodKey(at: Long, mode: Mode) = if (mode == Mode.YEAR) startOfYear(at) else startOfMonth(at)

private fun shiftPeriod(at: Long, mode: Mode, by: Int): Long =
    cal(at).apply { add(if (mode == Mode.YEAR) Calendar.YEAR else Calendar.MONTH, by) }.timeInMillis

/** Three years of months, or five years, ending now. */
private fun periodsFor(mode: Mode, today: Long): List<Long> {
    val now = periodKey(today, mode)
    val back = if (mode == Mode.YEAR) 4 else 35
    return (-back..0).map { shiftPeriod(now, mode, it) }
}

private fun daysIn(month: Long): List<Long?> {
    val first = startOfMonth(month)
    val c = cal(first)
    val lead = (c.get(Calendar.DAY_OF_WEEK) - c.firstDayOfWeek + 7) % 7
    val count = c.getActualMaximum(Calendar.DAY_OF_MONTH)
    val days = (0 until count).map { StudyPlan.addDays(first, it) }
    val cells: List<Long?> = List(lead) { null } + days
    return cells + List((7 - cells.size % 7) % 7) { null }
}

private fun monthsOfYear(at: Long): List<Long> = startOfYear(at).let { jan -> (0 until 12).map { shiftPeriod(jan, Mode.MONTH, it) } }

private fun periodDays(anchor: Long, mode: Mode): List<Long> = when (mode) {
    Mode.YEAR -> monthsOfYear(anchor).flatMap { daysIn(it).filterNotNull() }
    else -> daysIn(anchor).filterNotNull()
}

private fun weekdayLabels(): List<String> {
    val fmt = SimpleDateFormat("EEEEE", Locale.getDefault())
    val c = Calendar.getInstance().apply { set(Calendar.DAY_OF_WEEK, firstDayOfWeek) }
    return (0 until 7).map { fmt.format(c.time).also { c.add(Calendar.DAY_OF_YEAR, 1) } }
}

private fun dayKey(at: Long) = StudyPlan.dayKey(at)
private fun dayOfMonth(at: Long) = SimpleDateFormat("d", Locale.US).format(Date(at))

/** A SKELETON, never a fixed pattern — each language orders the pieces its own way. */
private fun skeleton(at: Long, skeleton: String): String {
    val locale = Locale.getDefault()
    return SimpleDateFormat(android.text.format.DateFormat.getBestDateTimePattern(locale, skeleton), locale).format(Date(at))
}

private fun periodTitle(anchor: Long, mode: Mode) =
    skeleton(anchor, if (mode == Mode.YEAR) "y" else "yMMMM")

/** Seconds → heat bucket, anchored to the ~10-minute daily-goal scale. */
private fun heatAlpha(seconds: Int): Float = when {
    seconds < 60 -> 0.25f
    seconds < 5 * 60 -> 0.4f
    seconds < 10 * 60 -> 0.65f
    seconds < 20 * 60 -> 0.85f
    else -> 1.0f
}
