package com.roro.futurevoice.ui

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGesturesAfterLongPress
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.filled.NotificationsOff
import androidx.compose.material.icons.filled.Remove
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.zIndex
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.roro.futurevoice.R
import com.roro.futurevoice.data.DailyCallStore
import com.roro.futurevoice.data.PlanReminder
import com.roro.futurevoice.data.RoutineText
import com.roro.futurevoice.data.StudyPlan
import com.roro.futurevoice.data.StudyPlanStore
import com.roro.futurevoice.data.WeeklyTestSettings
import com.roro.futurevoice.ui.brand.AppSurfaces
import com.roro.futurevoice.ui.brand.IosSegmented
import com.roro.futurevoice.ui.brand.IosSwitch
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import kotlin.math.roundToInt

private val HOUR_HEIGHT = 40.dp
private val LABEL_WIDTH = 16.dp
private val GAP = 3.dp
/** The +'s height plus its margin, with some air. */
private val ADD_BUTTON_CLEARANCE = (56 + 4 + 24).dp
/** A drag moves the time in 10-minute steps, each one felt. */
private const val DRAG_STEP_MINUTES = 10

/** What the block editor is opened on: a spot in the week, or a block. */
sealed interface BlockTarget {
    data class NewInWeek(val weekday: Int, val hour: Int, val minute: Int) : BlockTarget
    data class InWeek(val blockId: String) : BlockTarget
}

/**
 * The weekly plan, edited on its own page with room to work (iOS
 * `WeeklyPlanEditor`): Monday to Sunday with no dates, because what is being
 * changed is the plan every week follows. 40 dp per hour, every block showing
 * its 24-hour start. Tap an empty spot to add a block there (half-hour
 * steps); tap a block to edit it; hold and drag to move it — down for the
 * time (10-minute steps), sideways for the weekday. A dropped block is
 * ALREADY where it was dropped; only then, if it also runs on other weekdays
 * and only its time changed, a dialog asks whether the rest follow.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun WeeklyPlanEditor(onClose: () -> Unit, captureBlock: BlockTarget? = null) {
    androidx.activity.compose.BackHandler(onBack = onClose)
    NavCoverGuard()
    val context = LocalContext.current
    val res = context.resources
    val haptic = LocalHapticFeedback.current
    val scope = rememberCoroutineScope()
    val plan by StudyPlanStore.plan.collectAsStateWithLifecycle()
    val testRevision by WeeklyTestSettings.revision.collectAsStateWithLifecycle()
    LaunchedEffect(Unit) { StudyPlanStore.current(context) }
    val snapshot = remember(plan, testRevision) { PlannerSnapshot.master(context, plan) }

    var blockEditor by remember { mutableStateOf(captureBlock) }
    var showDays by remember { mutableStateOf(false) }
    var showTest by remember { mutableStateOf(false) }
    var pendingFollow by remember { mutableStateOf<Pair<String, Long>?>(null) }
    var refused by remember { mutableStateOf(false) }
    var dragTarget by remember { mutableStateOf<Long?>(null) }
    var landedId by remember { mutableStateOf<String?>(null) }
    var landedNote by remember { mutableStateOf<String?>(null) }
    var addMenu by remember { mutableStateOf(false) }
    val scroll = rememberScrollState()
    val density = LocalDensity.current
    val hourPx = with(density) { HOUR_HEIGHT.toPx() }

    // Said only when the routine's reminders CAN'T ring.
    var notificationsOn by remember { mutableStateOf(NotificationManagerCompat.from(context).areNotificationsEnabled()) }
    LifecycleEventEffect(Lifecycle.Event.ON_RESUME) {
        notificationsOn = NotificationManagerCompat.from(context).areNotificationsEnabled()
    }
    val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) {
        notificationsOn = NotificationManagerCompat.from(context).areNotificationsEnabled()
        scope.launch { PlanReminder.reschedule(context) }
    }
    val canAsk = Build.VERSION.SDK_INT >= 33 && ContextCompat.checkSelfPermission(context,
        Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED &&
        !context.getSharedPreferences("futurevoice", 0).getBoolean(ASKED_KEY, false)
    fun askOnce() {
        if (canAsk) {
            context.getSharedPreferences("futurevoice", 0).edit().putBoolean(ASKED_KEY, true).apply()
            permission.launch(Manifest.permission.POST_NOTIFICATIONS)
        }
    }

    LaunchedEffect(Unit) { scroll.scrollTo(((7 - snapshot.startHour) * hourPx).roundToInt()) }

    fun update(next: StudyPlan): Boolean {
        val ok = StudyPlanStore.update(context, next, byLearner = true)
        if (!ok) refused = true
        return ok
    }

    fun handleMove(occ: StudyPlan.Occurrence, day: Long, newStart: Long) {
        when (val source = occ.source) {
            StudyPlan.Occurrence.Source.Test -> {
                val c = StudyPlan.cal(newStart, java.util.TimeZone.getDefault())
                WeeklyTestSettings.setWeekday(context, StudyPlan.weekday(newStart))
                WeeklyTestSettings.setTime(context, c.get(Calendar.HOUR_OF_DAY), c.get(Calendar.MINUTE))
            }
            is StudyPlan.Occurrence.Source.Template -> {
                val spans = (plan.blocks.firstOrNull { it.id == source.id }?.weekdays?.size ?: 1) > 1
                val sameDay = StudyPlan.isSameDay(day, newStart)
                val moved = plan.moving(source.id, day, newStart, StudyPlan.Scope.EVERY_WEEK)
                if (moved == null || !update(moved)) { refused = true; return }
                haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                com.roro.futurevoice.core.Analytics.capture("plan_block_moved",
                    mapOf("kind" to occ.kind.raw, "scope" to "weekday"))
                if (spans && sameDay) pendingFollow = source.id to newStart
            }
            is StudyPlan.Occurrence.Source.Exception -> Unit
        }
    }

    fun addBlock(kind: StudyPlan.Kind) {
        val days = (1..7).toSet() - (plan.offWeekdays ?: emptySet())
        val length = kind.drawnMinutes(kind.defaultAmount)
        // A talk in the morning (the call's default), say it again right
        // after it, review in the evening.
        val usual = when (kind) {
            StudyPlan.Kind.TALK -> 8 * 60
            StudyPlan.Kind.SAY_IT_AGAIN -> 8 * 60 + 15
            else -> 20 * 60
        }
        fun isFree(start: Int): Boolean {
            if (start < 0 || start + length > 24 * 60) return false
            return plan.blocks.all { b ->
                b.isAnytime || b.weekdays.intersect(days).isEmpty() || start + length <= b.startMinute ||
                    b.startMinute + b.kind.drawnMinutes(b.minutes) <= start
            }
        }
        val later = (usual..23 * 60 step 30).toList()
        val earlier = (usual - 30 downTo 6 * 60 step 30).toList()
        val start = (later + earlier).firstOrNull(::isFree) ?: usual
        val next = plan.copy(blocks = plan.blocks + StudyPlan.Block(kind = kind, weekdays = days,
            hour = start / 60, minute = start % 60, minutes = kind.defaultAmount)).mergingTwins()
        if (!update(next)) return
        haptic.performHapticFeedback(HapticFeedbackType.LongPress)
        val id = StudyPlanStore.plan.value.blocks.firstOrNull {
            it.kind == kind && it.startMinute == start && !it.isAnytime
        }?.id
        landedId = id
        landedNote = "${RoutineText.label(res, kind)} · ${clockText(start)}"
        scope.launch {
            scroll.animateScrollTo(((start / 60.0 - snapshot.startHour - 2) * hourPx).roundToInt().coerceAtLeast(0))
            delay(2500)
            if (landedId == id) { landedId = null; landedNote = null }
        }
        com.roro.futurevoice.core.Analytics.capture("plan_block_saved",
            mapOf("kind" to kind.raw, "new" to true, "via" to "add_button"))
        if (kind != StudyPlan.Kind.TALK) askOnce()
    }

    Scaffold(
        containerColor = AppSurfaces.ground,
        topBar = {
            TopAppBar(
                colors = AppSurfaces.topBarColors(),
                title = { Text(stringResource(R.string.routine_my_routine)) },
                // Study days are set once and rarely touched: behind the gear.
                navigationIcon = {
                    IconButton(onClick = { showDays = true }) {
                        Icon(Icons.Filled.Settings, contentDescription = stringResource(R.string.routine_study_days))
                    }
                },
                actions = { TextButton(onClick = onClose) { Text(stringResource(R.string.routine_done)) } },
            )
        },
    ) { padding ->
        // The timeline runs to the screen's bottom edge; only the top bar is
        // padded off.
        Column(Modifier.padding(top = padding.calculateTopPadding()).fillMaxSize()) {
            if (!notificationsOn) {
                Row(Modifier.fillMaxWidth().background(AppSurfaces.card).clickable {
                    if (canAsk) askOnce() else context.startActivity(
                        Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                            .putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
                            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                }.padding(horizontal = 16.dp, vertical = 10.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Icon(if (canAsk) Icons.Filled.Notifications else Icons.Filled.NotificationsOff, null,
                        tint = if (canAsk) MaterialTheme.colorScheme.primary else Color(0xFFFF9500))
                    Text(stringResource(if (canAsk) R.string.routine_allow_notifications
                        else R.string.routine_notifications_off),
                        style = MaterialTheme.typography.bodySmall, modifier = Modifier.weight(1f))
                    Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null,
                        tint = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.size(16.dp))
                }
            }
            WeekdayHeader(snapshot) { occ -> occ.blockId?.let { blockEditor = BlockTarget.InWeek(it) } }
            Box(Modifier.weight(1f).fillMaxWidth()) {
                Column(Modifier.fillMaxSize().verticalScroll(scroll)
                    // Room for the + to float over without covering the
                    // last hours.
                    .padding(start = 8.dp, end = 8.dp, top = 6.dp).bottomBarInsets()
                    .padding(bottom = ADD_BUTTON_CLEARANCE)) {
                    WeekGrid(
                        snapshot = snapshot, highlightId = landedId,
                        onAdd = { day, minute ->
                            blockEditor = BlockTarget.NewInWeek(StudyPlan.weekday(day), minute / 60, minute % 60)
                        },
                        onEdit = { occ ->
                            val id = occ.blockId
                            if (id != null) blockEditor = BlockTarget.InWeek(id)
                            else if (occ.kind == StudyPlan.Kind.TEST) showTest = true
                        },
                        onMove = ::handleMove,
                        onDragTarget = { t -> dragTarget = t; if (t != null) { landedId = null; landedNote = null } },
                    )
                }
                val pill = dragTarget?.let {
                    "${SimpleDateFormat("EEE", Locale.getDefault()).format(Date(it))} ${clockText(it)}"
                } ?: landedNote
                if (pill != null) {
                    Text(pill, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold,
                        color = MaterialTheme.colorScheme.surface,
                        modifier = Modifier.align(Alignment.TopCenter).padding(top = 8.dp)
                            .clip(CircleShape).background(MaterialTheme.colorScheme.onSurface)
                            .padding(horizontal = 16.dp, vertical = 8.dp))
                }
                // The + : the three blocks a routine is made of, put straight
                // on the grid at the first free slot from the kind's usual time.
                // Out of the way while a block is being dragged — it would sit
                // over the very hours the block is being dropped on.
                androidx.compose.animation.AnimatedVisibility(visible = dragTarget == null,
                    enter = androidx.compose.animation.fadeIn(), exit = androidx.compose.animation.fadeOut(),
                    modifier = Modifier.align(Alignment.BottomEnd)) {
                Box(Modifier.bottomBarInsets().padding(end = 20.dp, bottom = 4.dp)) {
                    Box(Modifier.size(56.dp).shadow(8.dp, CircleShape).clip(CircleShape)
                        .background(MaterialTheme.colorScheme.primary).clickable { addMenu = true },
                        contentAlignment = Alignment.Center) {
                        Icon(Icons.Filled.Add, contentDescription = stringResource(R.string.routine_add_block),
                            tint = Color.White, modifier = Modifier.size(28.dp))
                    }
                    com.roro.futurevoice.ui.brand.IosDropdownMenu(expanded = addMenu, onDismissRequest = { addMenu = false }) {
                        StudyPlan.Kind.placeable.forEach { k ->
                            com.roro.futurevoice.ui.brand.IosDropdownMenuItem(
                                text = { Text(RoutineText.label(res, k)) },
                                leadingIcon = { Icon(k.icon(), null, tint = k.color()) },
                                onClick = { addMenu = false; addBlock(k) })
                        }
                    }
                }
                }
            }
        }
    }

    blockEditor?.let { target ->
        PlanBlockSheet(target, onDismiss = { blockEditor = null }, onRefused = { refused = true },
            onAskPermission = ::askOnce)
    }
    if (showDays) StudyDaysSheet(plan, onDismiss = { showDays = false }) { update(it) }
    if (showTest) {
        ModalBottomSheet(sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
            onDismissRequest = { showTest = false }) {
            Column(Modifier.sheetBody().padding(horizontal = 20.dp).padding(bottom = 32.dp)) {
                Text(RoutineText.label(res, StudyPlan.Kind.TEST), style = MaterialTheme.typography.titleLarge,
                    modifier = Modifier.padding(bottom = 8.dp))
                WeeklyTestSettingsSection()
            }
        }
    }
    pendingFollow?.let { (id, newStart) ->
        AlertDialog(
            onDismissRequest = { pendingFollow = null },
            title = { Text(stringResource(R.string.routine_move_others)) },
            confirmButton = {
                TextButton(onClick = {
                    pendingFollow = null
                    val c = StudyPlan.cal(newStart, java.util.TimeZone.getDefault())
                    val next = plan.following(id, c.get(Calendar.HOUR_OF_DAY), c.get(Calendar.MINUTE))
                    if (next == null || !update(next)) refused = true
                    else com.roro.futurevoice.core.Analytics.capture("plan_block_moved", mapOf("scope" to "all_days"))
                }) { Text(stringResource(R.string.routine_every_day_it_runs)) }
            },
            // Already done: the dragged one moved on release.
            dismissButton = {
                TextButton(onClick = { pendingFollow = null }) {
                    Text(stringResource(R.string.routine_only_on,
                        SimpleDateFormat("EEEE", Locale.getDefault()).format(Date(newStart))))
                }
            },
        )
    }
    if (refused) TooManyCallsAlert { refused = false }
}

private const val ASKED_KEY = "futurevoice.routine.askedNotifications"

@Composable
private fun TooManyCallsAlert(onDismiss: () -> Unit) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.routine_too_many_calls)) },
        text = { Text(stringResource(R.string.routine_too_many_calls_body)) },
        confirmButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.routine_ok)) } },
    )
}

/** Stays put above the scrolling hours. Under the day names, the day's
 *  "any time" blocks — no hour, so no place on the grid. */
@Composable
private fun WeekdayHeader(snapshot: PlannerSnapshot, onTap: (StudyPlan.Occurrence) -> Unit) {
    val anytime = snapshot.days.map { d -> snapshot.planned[d].orEmpty().filter { it.anytime } }
    Column(Modifier.fillMaxWidth().background(AppSurfaces.card).padding(horizontal = 8.dp, vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(GAP)) {
            Spacer(Modifier.width(LABEL_WIDTH))
            snapshot.days.forEach { d ->
                Text(SimpleDateFormat("EEE", Locale.getDefault()).format(Date(d)),
                    style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.SemiBold,
                    color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center,
                    maxLines = 1, modifier = Modifier.weight(1f))
            }
        }
        if (anytime.any { it.isNotEmpty() }) {
            Text(stringResource(R.string.routine_any_time_of_day), style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(start = LABEL_WIDTH + GAP))
            Row(horizontalArrangement = Arrangement.spacedBy(GAP), verticalAlignment = Alignment.Top) {
                Spacer(Modifier.width(LABEL_WIDTH))
                anytime.forEach { list ->
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                        list.forEach { occ ->
                            Row(Modifier.fillMaxWidth().heightIn(min = 22.dp).clip(RoundedCornerShape(5.dp))
                                .background(occ.kind.color().copy(alpha = 0.18f)).clickable { onTap(occ) },
                                horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) {
                                Icon(occ.kind.icon(), null, tint = occ.kind.color(), modifier = Modifier.size(11.dp))
                                if (occ.amount > 1 || occ.kind.isTimed) {
                                    Text("${occ.amount}", fontSize = 10.sp, fontWeight = FontWeight.SemiBold,
                                        color = occ.kind.color(), maxLines = 1)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

/**
 * Seven columns, time running down, every block where it starts. A short
 * block is drawn taller than its minutes so its icon fits, and each block
 * starts no higher than the bottom of the one before (`stackedTops`).
 */
@Composable
private fun WeekGrid(
    snapshot: PlannerSnapshot,
    highlightId: String?,
    onAdd: (day: Long, minuteOfDay: Int) -> Unit,
    onEdit: (StudyPlan.Occurrence) -> Unit,
    onMove: (StudyPlan.Occurrence, Long, Long) -> Unit,
    onDragTarget: (Long?) -> Unit,
) {
    val density = LocalDensity.current
    val haptic = LocalHapticFeedback.current
    val hourPx = with(density) { HOUR_HEIGHT.toPx() }
    val start = snapshot.startHour
    val gridHeight = HOUR_HEIGHT * (snapshot.endHour - start)
    val fill = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f)
    val line = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f)
    val labelColor = MaterialTheme.colorScheme.onSurfaceVariant
    var dragging by remember { mutableStateOf<String?>(null) }
    var dragOffset by remember { mutableStateOf(Offset.Zero) }
    var target by remember { mutableStateOf<Long?>(null) }

    BoxWithConstraints(Modifier.fillMaxWidth().height(gridHeight)) {
        val cols = maxOf(1, snapshot.days.size)
        val colW = (maxWidth - LABEL_WIDTH - GAP * cols) / cols
        val colWPx = with(density) { colW.toPx() }
        val gapPx = with(density) { GAP.toPx() }
        val labelPx = with(density) { LABEL_WIDTH.toPx() }
        fun colX(i: Int) = labelPx + gapPx + i * (colWPx + gapPx)
        fun y(at: Long): Float {
            val c = StudyPlan.cal(at, java.util.TimeZone.getDefault())
            return (c.get(Calendar.HOUR_OF_DAY) * 60 + c.get(Calendar.MINUTE) - start * 60) / 60f * hourPx
        }
        fun snapped(dy: Float): Float =
            ((dy / hourPx * 60 / DRAG_STEP_MINUTES).roundToInt() * DRAG_STEP_MINUTES) / 60f * hourPx
        fun newStart(occ: StudyPlan.Occurrence, d: Offset): Long? {
            val minutes = (d.y / hourPx * 60 / DRAG_STEP_MINUTES).roundToInt() * DRAG_STEP_MINUTES
            // By COLUMN, not by calendar day: a rest weekday has no column.
            val steps = (d.x / (colWPx + gapPx)).roundToInt()
            val from = snapshot.days.indexOfFirst { StudyPlan.isSameDay(it, occ.start) }
            val to = from + steps
            if (from < 0 || to !in snapshot.days.indices) return null
            val c = StudyPlan.cal(occ.start, java.util.TimeZone.getDefault())
            val offset = c.get(Calendar.HOUR_OF_DAY) * 60 + c.get(Calendar.MINUTE)
            val clamped = (offset + minutes).coerceIn(0, 24 * 60 - maxOf(DRAG_STEP_MINUTES, occ.minutes))
            return StudyPlan.at(snapshot.days[to], clamped / 60, clamped % 60)
        }

        // The ground: column fills, hour lines and labels; a tap adds there.
        Canvas(Modifier.fillMaxSize().pointerInput(snapshot.days, colWPx) {
            detectTapGestures { pos ->
                val i = ((pos.x - labelPx - gapPx) / (colWPx + gapPx)).toInt()
                if (i !in snapshot.days.indices || pos.x < labelPx) return@detectTapGestures
                // Half-hour steps for a new block; dragging refines it.
                val minutes = ((pos.y / hourPx * 60 / 30).toInt() * 30 + start * 60).coerceIn(0, 23 * 60 + 30)
                onAdd(snapshot.days[i], minutes)
            }
        }) {
            for (i in snapshot.days.indices) {
                drawRoundRect(fill, Offset(colX(i), 0f), Size(colWPx, size.height), CornerRadius(6.dp.toPx()))
                for (h in start until snapshot.endHour) {
                    drawRect(line, Offset(colX(i), (h - start) * hourPx), Size(colWPx, 0.5.dp.toPx()))
                }
            }
        }
        for (h in start..snapshot.endHour) {
            Text("$h", fontSize = 9.sp, color = labelColor, textAlign = TextAlign.End,
                modifier = Modifier.width(LABEL_WIDTH).offset { IntOffset(0, ((h - start) * hourPx - 6.dp.toPx()).roundToInt()) })
        }
        snapshot.days.forEachIndexed { i, day ->
            val shown = snapshot.planned[day].orEmpty().filter { !it.anytime }
            val minH = with(density) { 16.dp.toPx() }
            // Blocks that run into each other keep a visible gap between them
            // (the founder's ask, 2026-10-05; iOS stacks them 1 pt apart).
            val gap = with(density) { 3.dp.toPx() }
            var bottom = Float.NEGATIVE_INFINITY
            shown.sortedBy { it.start }.forEach { occ ->
                val h = maxOf(minH, occ.minutes / 60f * hourPx)
                val top = maxOf(y(occ.start), bottom + gap)
                bottom = top + h
                val isDragging = dragging == occ.id
                val draggable = occ.blockId != null || occ.kind == StudyPlan.Kind.TEST
                val color = occ.kind.color()
                val hDp = with(density) { h.toDp() }
                Box(
                    Modifier
                        .offset { IntOffset(
                            (colX(i) + 1.dp.toPx() + if (isDragging) dragOffset.x else 0f).roundToInt(),
                            (top + if (isDragging) snapped(dragOffset.y) else 0f).roundToInt()) }
                        .zIndex(if (isDragging) 10f else 1f)
                        .width(colW - 2.dp).height(hDp)
                        .clip(RoundedCornerShape(4.dp))
                        .background(color.copy(alpha = if (isDragging) 0.3f else 0.18f))
                        .then(if (occ.blockId != null && occ.blockId == highlightId) Modifier.landedRing(color) else Modifier)
                        .pointerInput(occ.id) { detectTapGestures { onEdit(occ) } }
                        .then(if (!draggable) Modifier else Modifier.pointerInput(occ.id, snapshot) {
                            detectDragGesturesAfterLongPress(
                                onDragStart = {
                                    dragging = occ.id; dragOffset = Offset.Zero; target = occ.start
                                    haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                                    onDragTarget(occ.start)
                                },
                                onDrag = { change, amount ->
                                    change.consume()
                                    dragOffset += amount
                                    val t = newStart(occ, dragOffset) ?: occ.start
                                    if (t != target) {
                                        target = t
                                        haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                                        onDragTarget(t)
                                    }
                                },
                                onDragEnd = {
                                    val t = newStart(occ, dragOffset)
                                    dragging = null; dragOffset = Offset.Zero; target = null
                                    onDragTarget(null)
                                    if (t != null && t != occ.start) onMove(occ, day, t)
                                },
                                onDragCancel = {
                                    dragging = null; dragOffset = Offset.Zero; target = null
                                    onDragTarget(null)
                                },
                            )
                        }),
                    contentAlignment = if (h >= with(density) { 30.dp.toPx() }) Alignment.TopStart else Alignment.CenterStart,
                ) {
                    Row(Modifier.padding(start = 4.dp, end = 2.dp, top = if (h >= with(density) { 30.dp.toPx() }) 4.dp else 0.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(3.dp)) {
                        Icon(occ.kind.icon(), null, tint = color, modifier = Modifier.size(10.dp))
                        // The theme's body line height is ~2.5x this size, so the
                        // glyphs sat at the bottom of a too-tall box and the block
                        // clipped them (seen on the phone). One tight, centred line.
                        Text(clockText(occ.start), fontSize = 9.sp, fontWeight = FontWeight.SemiBold,
                            color = color, maxLines = 1, softWrap = false,
                            style = androidx.compose.material3.LocalTextStyle.current.copy(
                                lineHeight = 10.sp,
                                lineHeightStyle = androidx.compose.ui.text.style.LineHeightStyle(
                                    androidx.compose.ui.text.style.LineHeightStyle.Alignment.Center,
                                    androidx.compose.ui.text.style.LineHeightStyle.Trim.Both),
                                platformStyle = androidx.compose.ui.text.PlatformTextStyle(includeFontPadding = false)))
                    }
                }
            }
        }
    }
}

/** The ring on a block just added: soft pulses, then the editor clears it. */
@Composable
private fun Modifier.landedRing(color: Color): Modifier {
    val t = rememberInfiniteTransition(label = "landed")
    val a by t.animateFloat(1f, 0.3f, infiniteRepeatable(tween(450), RepeatMode.Reverse), label = "a")
    return this.border(2.dp, color.copy(alpha = a), RoundedCornerShape(4.dp))
}

/**
 * One block: what, which weekdays, when, how much (iOS `PlanBlockEditor`).
 * A talk is promised in minutes; everything else in the count the app keeps.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PlanBlockSheet(target: BlockTarget, onDismiss: () -> Unit, onRefused: () -> Unit, onAskPermission: () -> Unit) {
    val context = LocalContext.current
    val res = context.resources
    val plan = remember { StudyPlanStore.current(context) }
    val existing = (target as? BlockTarget.InWeek)?.let { t -> plan.blocks.firstOrNull { it.id == t.blockId } }
    var kind by remember { mutableStateOf(existing?.kind ?: StudyPlan.Kind.REVIEW) }
    var weekdays by remember { mutableStateOf(existing?.weekdays ?: setOf((target as? BlockTarget.NewInWeek)?.weekday ?: 2)) }
    var minuteOfDay by remember { mutableStateOf(existing?.startMinute
        ?: (target as? BlockTarget.NewInWeek)?.let { it.hour * 60 + it.minute } ?: (20 * 60)) }
    var amount by remember { mutableStateOf(existing?.minutes ?: StudyPlan.Kind.REVIEW.defaultAmount) }
    var remind by remember { mutableStateOf(existing?.remind ?: true) }
    var anytime by remember { mutableStateOf(existing?.isAnytime ?: false) }
    val callOn = DailyCallStore.isEnabled(context)
    val range = when (kind) { StudyPlan.Kind.TALK -> 5..60; StudyPlan.Kind.REVIEW -> 5..100; else -> 1..50 }
    val step = if (kind == StudyPlan.Kind.TALK || kind == StudyPlan.Kind.REVIEW) 5 else 1

    fun save() {
        val base = existing ?: StudyPlan.Block(kind = kind, weekdays = emptySet(), hour = 0, minute = 0, minutes = amount)
        val edited = base.copy(kind = kind, weekdays = weekdays, hour = minuteOfDay / 60, minute = minuteOfDay % 60,
            minutes = amount, remind = if (kind == StudyPlan.Kind.TALK) true else remind,
            anytime = if (anytime) true else null)
        val current = StudyPlanStore.current(context)
        val blocks = if (existing != null) current.blocks.map { if (it.id == existing.id) edited else it }
        else current.blocks + edited
        if (!StudyPlanStore.update(context, current.copy(blocks = blocks).mergingTwins(), byLearner = true)) {
            onRefused(); return
        }
        com.roro.futurevoice.core.Analytics.capture("plan_block_saved", mapOf("kind" to kind.raw, "new" to (existing == null)))
        if (kind != StudyPlan.Kind.TALK && remind) onAskPermission()
        onDismiss()
    }

    ModalBottomSheet(sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true), onDismissRequest = onDismiss) {
        Column(Modifier.fillMaxWidth().bottomBarInsets().verticalScroll(rememberScrollState())
            .padding(horizontal = 20.dp).padding(bottom = 32.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                TextButton(onClick = onDismiss) { Text(stringResource(R.string.routine_cancel)) }
                Text(stringResource(if (existing == null) R.string.routine_new_block else R.string.routine_block),
                    style = MaterialTheme.typography.titleMedium, textAlign = TextAlign.Center, modifier = Modifier.weight(1f))
                TextButton(onClick = ::save, enabled = weekdays.isNotEmpty()) {
                    Text(stringResource(R.string.routine_save), fontWeight = FontWeight.SemiBold)
                }
            }
            GroupedSectionHeader(stringResource(R.string.routine_activity))
            GroupedCard {
                StudyPlan.Kind.placeable.forEachIndexed { i, k ->
                    if (i > 0) GroupedRowDivider()
                    Row(Modifier.fillMaxWidth().clickable {
                        // A new kind starts from its own amount.
                        if (k != kind) amount = k.defaultAmount
                        kind = k
                    }.padding(horizontal = 16.dp, vertical = 12.dp),
                        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        Icon(k.icon(), null, tint = k.color(), modifier = Modifier.size(20.dp))
                        Text(RoutineText.label(res, k), Modifier.weight(1f))
                        if (k == kind) Icon(Icons.Filled.Check, null, tint = MaterialTheme.colorScheme.primary)
                    }
                }
            }
            when (kind) {
                StudyPlan.Kind.REVIEW -> GroupedFooter(stringResource(R.string.routine_review_footer))
                StudyPlan.Kind.TALK -> GroupedFooter(stringResource(when {
                    !callOn -> R.string.routine_talk_call_off_footer
                    anytime -> R.string.routine_talk_anytime_footer
                    else -> R.string.routine_talk_rings_footer
                }))
                else -> Unit
            }
            GroupedSectionHeader(stringResource(R.string.routine_days_header))
            WeekdayChips(on = weekdays, lit = { it in weekdays }) { wd ->
                weekdays = if (wd in weekdays) weekdays - wd else weekdays + wd
            }
            GroupedSectionSpacer()
            GroupedCard {
                SwitchRow(stringResource(R.string.routine_any_time_of_day), anytime) { anytime = it }
                if (!anytime) {
                    GroupedRowDivider()
                    // iOS `DatePicker("Time", .hourAndMinute)`: compact capsule
                    // + wheel popover, not Material's clock dialog.
                    Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
                        verticalAlignment = Alignment.CenterVertically) {
                        Text(stringResource(R.string.routine_time), Modifier.weight(1f))
                        com.roro.futurevoice.ui.brand.IosCompactTimePicker(minuteOfDay / 60, minuteOfDay % 60) { h, m ->
                            minuteOfDay = h * 60 + m
                        }
                    }
                }
                GroupedRowDivider()
                Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 6.dp),
                    verticalAlignment = Alignment.CenterVertically) {
                    Text(stringResource(if (kind.isTimed) R.string.routine_length else R.string.routine_how_many),
                        Modifier.weight(1f))
                    Text(RoutineText.amount(res, kind, amount).ifEmpty { "1" },
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                    IconButton(onClick = { amount = (amount - step).coerceIn(range) }, enabled = amount > range.first) {
                        Icon(Icons.Filled.Remove, null)
                    }
                    IconButton(onClick = { amount = (amount + step).coerceIn(range) }, enabled = amount < range.last) {
                        Icon(Icons.Filled.Add, null)
                    }
                }
                if (kind != StudyPlan.Kind.TALK) {
                    GroupedRowDivider()
                    SwitchRow(stringResource(R.string.routine_remind_me), remind) { remind = it }
                }
            }
            when (kind) {
                StudyPlan.Kind.TALK -> GroupedFooter(stringResource(R.string.routine_talk_block_footer))
                StudyPlan.Kind.SAY_IT_AGAIN -> GroupedFooter(stringResource(R.string.routine_say_again_footer))
                StudyPlan.Kind.SPEECH -> GroupedFooter(stringResource(R.string.any_script_counts_once_you_finish_a_take))
                else -> Unit
            }
            if (existing != null) {
                GroupedSectionSpacer()
                GroupedCard {
                    Text(stringResource(R.string.routine_delete_block), color = MaterialTheme.colorScheme.error,
                        modifier = Modifier.fillMaxWidth().clickable {
                            val current = StudyPlanStore.current(context)
                            StudyPlanStore.update(context, current.copy(blocks = current.blocks.filter { it.id != existing.id }),
                                byLearner = true)
                            onDismiss()
                        }.padding(16.dp))
                }
            }
        }
    }
}

@Composable
private fun SwitchRow(label: String, checked: Boolean, onChange: (Boolean) -> Unit) {
    Row(Modifier.fillMaxWidth().clickable { onChange(!checked) }.padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically) {
        Text(label, Modifier.weight(1f))
        IosSwitch(checked, onChange)
    }
}

/** Seven weekday chips from the phone's first weekday (iOS PlanEditorSheets
 *  `cal.firstWeekday`); lit = on. */
@Composable
private fun WeekdayChips(on: Set<Int>, lit: (Int) -> Boolean, onTap: (Int) -> Unit) {
    val order = StudyPlan.weekOrder()
    val fmt = SimpleDateFormat("EEEEE", Locale.getDefault())
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        order.forEach { wd ->
            val isOn = lit(wd)
            val label = fmt.format(Calendar.getInstance().apply { set(Calendar.DAY_OF_WEEK, wd) }.time)
            Box(Modifier.weight(1f).height(34.dp).clip(CircleShape)
                .background(if (isOn) MaterialTheme.colorScheme.primary else com.roro.futurevoice.ui.brand.iosFill())
                .clickable { onTap(wd) }, contentAlignment = Alignment.Center) {
                Text(label, fontWeight = if (isOn) FontWeight.SemiBold else FontWeight.Normal,
                    color = if (isOn) Color.White else MaterialTheme.colorScheme.onSurface)
            }
        }
    }
}

/**
 * Rest is a property of the WEEK, which is one plan that repeats: every
 * day, weekends off, or the learner's own days. A chip is a STUDY day; at
 * least one stays lit — a week of rest is no routine.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun StudyDaysSheet(plan: StudyPlan, onDismiss: () -> Unit, onUpdate: (StudyPlan) -> Unit) {
    val off = plan.offWeekdays ?: emptySet()
    var choosing by remember { mutableStateOf(false) }
    val choice = when {
        choosing -> 2
        off.isEmpty() -> 0
        off == setOf(1, 7) -> 1
        else -> 2
    }
    fun setOff(days: Set<Int>) = onUpdate(plan.copy(offWeekdays = days))
    ModalBottomSheet(sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true), onDismissRequest = onDismiss) {
        Column(Modifier.sheetBody().padding(horizontal = 20.dp).padding(bottom = 32.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(stringResource(R.string.routine_study_days), style = MaterialTheme.typography.titleLarge,
                    modifier = Modifier.weight(1f))
                TextButton(onClick = onDismiss) { Text(stringResource(R.string.routine_done)) }
            }
            IosSegmented(listOf(stringResource(R.string.routine_every_day), stringResource(R.string.routine_weekdays),
                stringResource(R.string.routine_choose)), choice, {
                when (it) {
                    0 -> { choosing = false; setOff(emptySet()) }
                    1 -> { choosing = false; setOff(setOf(1, 7)) }
                    else -> choosing = true
                }
            }, Modifier.fillMaxWidth())
            if (choice == 2) {
                WeekdayChips(on = off, lit = { it !in off }) { wd ->
                    val next = if (wd in off) off - wd else if (off.size < 6) off + wd else off
                    setOff(next)
                }
            }
            Text(stringResource(R.string.routine_rest_footer), style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}
