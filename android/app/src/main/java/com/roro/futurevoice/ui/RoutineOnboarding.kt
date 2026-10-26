package com.roro.futurevoice.ui

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateContentSize
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.tween
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowLeft
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.EditCalendar
import androidx.compose.material.icons.outlined.Circle
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.boundsInRoot
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.roro.futurevoice.R
import com.roro.futurevoice.data.DailyCallStore
import com.roro.futurevoice.data.RoutineText
import com.roro.futurevoice.data.StoreEvents
import com.roro.futurevoice.data.StudyPlan
import com.roro.futurevoice.data.StudyPlanStore
import com.roro.futurevoice.data.WeeklyTestReminder
import com.roro.futurevoice.data.WeeklyTestSettings
import com.roro.futurevoice.ui.brand.AppSurfaces
import com.roro.futurevoice.ui.brand.IosCompactTimePicker
import com.roro.futurevoice.ui.brand.IosSegmented
import com.roro.futurevoice.ui.brand.IosButton as Button
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch
import java.time.LocalTime
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.time.format.TextStyle

/**
 * Where the routine builder lands when it is done (iOS `RoutineHandoff`): the
 * Talk header's Activity chip reports its bounds here, and the builder
 * shrinks into it. The chip then shows a one-time hint that the routine lives
 * behind it.
 */
object RoutineHandoff {
    /** The Activity chip, in root coordinates. Null until it has drawn. */
    val chipBounds = MutableStateFlow<Rect?>(null)
    /** The hint under the chip, right after the builder went into it. */
    val showHint = MutableStateFlow(false)
    /** Bumped when the builder lands, so the chip can bounce. */
    val landed = MutableStateFlow(0)

    /** Outlives the builder, which leaves the screen the moment it lands —
     *  the hint is timed from here, as iOS's `asyncAfter` blocks are. */
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    fun land(context: Context) {
        HapticEngine.light(context)
        landed.value += 1
        scope.launch {
            delay(300)
            showHint.value = true
        }
        // It closes on its own too: the sheets that waited for the builder
        // (Talk's guide) come after it.
        scope.launch {
            delay(5_000)
            showHint.value = false
        }
    }
}

/** The first sheet is the intro AND the list: "Make my routine" grows it in
 *  place into the list (founder: no second window). `REVIEW`: the blocks are
 *  on the grid, the sheet is down so the grid can be edited (a block's
 *  editor is a sheet of its own), and a bar under it asks for the learner's
 *  OK. `DONE` is only for a routine left empty. */
private enum class RoutineStep { INTRO, REVIEW, DONE }

/** Every kind, in the order of a day. The call is set by hand (length, time,
 *  days); the rest are ticked from a list. */
private val ROUTINE_KINDS = listOf(StudyPlan.Kind.TALK, StudyPlan.Kind.LISTEN, StudyPlan.Kind.SHADOW,
    StudyPlan.Kind.SAY_IT_AGAIN, StudyPlan.Kind.REVIEW, StudyPlan.Kind.SPEECH)

private val ROUTINE_OTHERS = ROUTINE_KINDS.filter { it != StudyPlan.Kind.TALK }
private val CALL_CHOICES = listOf(5, 10, 15, 20)

/** The evening sitting (founder, 2026-10-20: say it again, review and speech
 *  around 9, one after another), in this order. */
private val ROUTINE_EVENING = listOf(StudyPlan.Kind.SAY_IT_AGAIN, StudyPlan.Kind.REVIEW, StudyPlan.Kind.SPEECH)
private const val EVENING_START = 21 * 60

/** Where each block goes and how much it asks for (iOS
 *  `RoutineOnboardingView.slot`). A time the learner set on the block
 *  ([times], minutes past midnight) wins; otherwise the evening kinds that
 *  are [selected] (and not set by hand) follow one another from 21:00 with
 *  no gap, and a row not ticked shows where it WOULD go. [callStart] is minutes past midnight. */
private data class RoutineSlot(val hour: Int, val minute: Int, val amount: Int)

private fun routineAmount(kind: StudyPlan.Kind, callMinutes: Int): Int = when (kind) {
    StudyPlan.Kind.REVIEW -> 10
    StudyPlan.Kind.TALK -> callMinutes
    else -> 1
}

private fun slot(kind: StudyPlan.Kind, callStart: Int, callMinutes: Int, selected: Set<StudyPlan.Kind>,
                 times: Map<StudyPlan.Kind, Int>): RoutineSlot {
    val amount = routineAmount(kind, callMinutes)
    // A time the learner set on the block wins.
    if (kind != StudyPlan.Kind.TALK) times[kind]?.let { return RoutineSlot(it / 60, it % 60, amount) }
    return when (kind) {
        StudyPlan.Kind.TALK -> RoutineSlot(callStart / 60, callStart % 60, callMinutes)
        StudyPlan.Kind.LISTEN -> RoutineSlot(8, 30, amount)
        StudyPlan.Kind.SHADOW -> RoutineSlot(12, 30, amount)
        else -> {
            val mine = ROUTINE_EVENING.indexOf(kind)
            var start = EVENING_START
            ROUTINE_EVENING.forEachIndexed { i, k ->
                if (k != kind && k in selected && k !in times && mine >= 0 && i < mine) {
                    start += k.drawnMinutes(if (k == StudyPlan.Kind.REVIEW) 10 else 1)
                }
            }
            RoutineSlot(start / 60, start % 60, amount)
        }
    }
}

/**
 * Onboarding's routine (iOS `RoutineOnboardingView`, 2026-10-18, founder:
 * "making the routine is the core"). It replaced three places that each set a
 * piece of it — setup's daily goal and purpose-made week, then a weekly-test
 * screen and a daily-call screen after the clone — with ONE: the My routine
 * grid itself, and a sheet over it.
 *
 * The sheet asks what goes IN the routine (iOS `72e4610f` / `82cc3d3b`,
 * 2026-10-20, founder): "Make my routine" grows the intro sheet itself into
 * the list — no second window. On top, the daily call as before (length,
 * time, the days the whole routine runs on); under "Add more", every other
 * kind as a row — what it is, in two lines, and when it would go — ticked
 * as many as they like, at the defaults in [slot]. Dragging the sheet up
 * opens it too; it never folds back. Shown over the Talk tab once; Done
 * shrinks it into the Activity chip, which is where it lives from then on.
 *
 * The sheet is drawn in place, not as a modal: iOS lets the grid behind it
 * scroll (`presentationBackgroundInteraction(.enabled)`) and it cannot be
 * swiped away (`interactiveDismissDisabled`).
 */
@Composable
fun RoutineOnboardingOverlay(onFinished: () -> Unit, debugStep: String? = null) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()

    var step by remember { mutableStateOf(RoutineStep.INTRO) }
    var sheetUp by remember { mutableStateOf(false) }
    var spotlight by remember { mutableStateOf<PlanSpotlight?>(null) }
    var working by remember { mutableStateOf(false) }
    var callMinutes by remember { mutableIntStateOf(5) }
    var callHour by remember { mutableIntStateOf(8) }
    var callMinute by remember { mutableIntStateOf(0) }
    /** A block on the grid is being dragged (review step). */
    var dragging by remember { mutableStateOf(false) }
    /** Times set by hand on an "Add more" block, minutes past midnight. */
    var times by remember { mutableStateOf<Map<StudyPlan.Kind, Int>>(emptyMap()) }
    /** The days the whole routine runs on; the rest are rest days. */
    var days by remember { mutableStateOf((1..7).toSet()) }
    /** The intro has grown into the list. */
    var expanded by remember { mutableStateOf(false) }
    /** Notifications weren't allowed: the routine stands, but nothing can ring. */
    var callBlocked by remember { mutableStateOf(false) }
    /** The call is ticked to begin with: it is what the app is. */
    var selected by remember { mutableStateOf(setOf(StudyPlan.Kind.TALK)) }
    /** What was saved — the done step speaks about this, not the ticks. */
    var saved by remember { mutableStateOf(emptySet<StudyPlan.Kind>()) }
    /** The notification question was put once in this sheet already
     *  (iOS asks only while the answer is undetermined). */
    var askedPermission by remember { mutableStateOf(false) }

    var ownBounds by remember { mutableStateOf<Rect?>(null) }
    val shrink = remember { Animatable(0f) }
    val fade = remember { Animatable(1f) }
    val chip by RoutineHandoff.chipBounds.collectAsStateWithLifecycle()

    var permissionAnswer by remember { mutableStateOf<CompletableDeferred<Boolean>?>(null) }
    val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        permissionAnswer?.complete(granted)
    }
    /** iOS `DailyCallScheduler.requestPermission`: the one question the call needs. */
    suspend fun requestPermission(): Boolean {
        askedPermission = true
        if (Build.VERSION.SDK_INT >= 33 && ContextCompat.checkSelfPermission(context,
                Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            val answer = CompletableDeferred<Boolean>()
            permissionAnswer = answer
            permission.launch(Manifest.permission.POST_NOTIFICATIONS)
            return answer.await()
        }
        return NotificationManagerCompat.from(context).areNotificationsEnabled()
    }

    /** iOS `PlanReminder.requestPermissionIfNeeded`: asked only while it was
     *  never answered; the reminders are then laid out again, since the
     *  plan's own pass ran before the answer. */
    suspend fun requestReminderPermissionIfNeeded() {
        if (askedPermission || Build.VERSION.SDK_INT < 33 || ContextCompat.checkSelfPermission(context,
                Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) return
        if (requestPermission()) {
            runCatching { com.roro.futurevoice.data.PlanReminder.reschedule(context) }
            runCatching { com.roro.futurevoice.data.DrillReminder.reschedule(context) }
        }
    }

    fun finish() {
        com.roro.futurevoice.core.Analytics.capture("routine_onboarding", mapOf(
            "call_minutes" to (if (StudyPlan.Kind.TALK in saved) callMinutes else 0),
            "call_hour" to callHour,
            "days" to days.size,
            "picked" to ROUTINE_KINDS.filter { it in saved }.joinToString(",") { it.raw },
            "call_on" to (StudyPlan.Kind.TALK in saved && !callBlocked),
        ))
        sheetUp = false
        // The sheet goes down first, then the page is drawn into the chip,
        // fading out as it reaches it.
        scope.launch {
            delay(350)
            launch { shrink.animateTo(1f, tween(500, easing = EaseInCurve)) }
            launch { delay(400); fade.animateTo(0f, tween(150, easing = EaseInCurve)) }
            delay(580)
            RoutineHandoff.land(context)
            onFinished()
        }
    }

    /** The ticked blocks on the grid, then the permission they need — the
     *  call's when the call is in, otherwise notifications for the
     *  reminders. */
    suspend fun save() {
        val blocks = ROUTINE_KINDS.filter { it in selected }.map { kind ->
            val s = slot(kind, callHour * 60 + callMinute, callMinutes, selected, times)
            StudyPlan.Block(kind = kind, weekdays = days, hour = s.hour, minute = s.minute,
                minutes = s.amount)
        }
        saved = selected
        val plan = StudyPlanStore.current(context).withOnboardingRoutine(blocks, days)
        StudyPlanStore.update(context, plan, byLearner = true)
        val first = blocks.firstOrNull()
        if (first == null) {
            step = RoutineStep.DONE
            return
        }
        // The card folds down into the check, and the grid becomes the page
        // to check.
        step = RoutineStep.REVIEW
        spotlight = PlanSpotlight(first.kind, first.startMinute, (spotlight?.token ?: 0) + 1)
        delay(700)
        if (StudyPlan.Kind.TALK in saved) {
            context.getSharedPreferences("futurevoice", 0).edit()
                .putInt("futurevoice.dailyGoalMinutes", callMinutes).apply()
            StoreEvents.bump()
            // The weekly test's "it's ready" notice rides on the same answer.
            WeeklyTestSettings.setReminderOn(context, true)
            val granted = requestPermission()
            WeeklyTestReminder.settleAfterPermission(context)
            DailyCallStore.setTimes(context, granted, StudyPlanStore.current(context).callTimes)
            callBlocked = !granted
        } else {
            DailyCallStore.setTimes(context, false, DailyCallStore.times(context))
            requestReminderPermissionIfNeeded()
        }
    }

    LaunchedEffect(Unit) {
        if (debugStep == "review") { saved = setOf(StudyPlan.Kind.TALK); step = RoutineStep.REVIEW }
        // A beat for the grid to be seen on its own first.
        delay(500)
        sheetUp = true
        // Capture build: `routine-onboarding-<step>` lands on a step
        // (pick | pickall | review | advance | flow | done | finish); `advance`
        // grows the intro into the list after a moment (for a recording),
        // `flow` then saves too, `finish` runs Done.
        when (debugStep) {
            "flow" -> {
                delay(1_500)
                expanded = true
                delay(2_500)
                save()
            }
            "pick" -> expanded = true
            "pickall" -> { selected = ROUTINE_KINDS.toSet(); expanded = true }
            "advance" -> {
                delay(2_500)
                expanded = true
            }
            "done" -> step = RoutineStep.DONE
            "finish" -> {
                step = RoutineStep.DONE
                delay(2_500)
                finish()
            }
        }
    }

    BoxWithConstraints(Modifier.fillMaxSize().onGloballyPositioned { ownBounds = it.boundsInRoot() }) {
        val own = ownBounds
        val target = chip
        Box(Modifier.fillMaxSize().graphicsLayer {
            val s = shrink.value
            if (s > 0f && own != null && target != null && own.width > 0f && target.width > 0f) {
                scaleX = 1f + (target.width / own.width - 1f) * s
                scaleY = 1f + (target.height / own.height - 1f) * s
                translationX = (target.center.x - own.center.x) * s
                translationY = (target.center.y - own.center.y) * s
            }
            alpha = fade.value
            shape = RoundedCornerShape((44 * minOf(1f, s * 3)).dp)
            clip = s > 0f
        }) {
            WeeklyPlanEditor(onClose = {}, onboarding = true, onboardingEditing = step == RoutineStep.REVIEW,
                spotlight = spotlight, onDragChange = { dragging = it })
        }

        // One card from start to end (iOS `98c7f9fb`): the intro, the list,
        // the check and the done card are the SAME surface, and only its
        // height moves — intro 300, the list to just under the status bar,
        // the check its content's height, done 300. It sits above the
        // navigation bar, as the routine sheet always has.
        val tall = step == RoutineStep.INTRO && expanded
        val large = maxHeight - WindowInsets.statusBars.asPaddingValues().calculateTopPadding() -
            WindowInsets.navigationBars.asPaddingValues().calculateBottomPadding() - 8.dp - 7.dp
        AnimatedVisibility(visible = sheetUp && !(step == RoutineStep.REVIEW && dragging),
            modifier = Modifier.align(Alignment.BottomCenter),
            // Out of the way quickly while a block is dragged: it covers the
            // evening hours the block may be going to.
            enter = slideInVertically(tween(if (dragging) 150 else 300)) { it } + fadeIn(tween(300)),
            exit = slideOutVertically(tween(if (step == RoutineStep.REVIEW) 150 else 250)) { it } +
                fadeOut(tween(250))) {
            Column(Modifier.fillMaxWidth()
                .windowInsetsPadding(WindowInsets.navigationBars.only(WindowInsetsSides.Bottom))
                .padding(start = 7.dp, end = 7.dp, bottom = 7.dp)
                .shadow(16.dp, SHEET_CARD_SHAPE)
                .background(AppSurfaces.ground, SHEET_CARD_SHAPE)
                // The card swallows touches — the grid behind still scrolls.
                .clickable(interactionSource = null, indication = null) {}
                .animateContentSize(tween(350))) {
                when (step) {
                    RoutineStep.INTRO -> Box(Modifier.fillMaxWidth().then(if (tall) Modifier.height(large) else Modifier)) {
                        RoutinePick(
                            expanded = expanded,
                            selected = selected,
                            times = times, onTime = { k, at -> times = times + (k to at) },
                            onToggle = { k -> selected = if (k in selected) selected - k else selected + k },
                            callMinutes = callMinutes, onCallMinutes = { callMinutes = it },
                            callHour = callHour, callMinute = callMinute,
                            onCallTime = { h, m -> callHour = h; callMinute = m },
                            days = days,
                            onToggleDay = { wd ->
                                days = if (wd in days) { if (days.size > 1) days - wd else days } else days + wd
                            },
                            saving = working,
                            onButton = {
                                if (!expanded) expanded = true
                                else { working = true; scope.launch { save(); working = false } }
                            },
                        )
                    }
                    // Under the grid once the blocks are on it: fix them on
                    // the grid, then say it's right.
                    RoutineStep.REVIEW -> ConfirmContent(callBlocked = callBlocked, working = working,
                        // Back to the list, ticks as they were. Saving again
                        // rewrites the blocks from the list.
                        onBack = { step = RoutineStep.INTRO; expanded = true },
                        onKeep = { finish() })
                    RoutineStep.DONE -> Box(Modifier.fillMaxWidth()) {
                        val empty = saved.isEmpty()
                        RoutineMessage(if (empty) Icons.Filled.CalendarMonth else Icons.Filled.CheckCircle,
                            if (empty) MaterialTheme.colorScheme.onSurfaceVariant else Color(0xFF34C759),
                            stringResource(if (empty) R.string.routine_make_it_later else R.string.your_routine_is_ready),
                            stringResource(when {
                                empty -> R.string.routine_under_activity_whenever
                                StudyPlan.Kind.TALK in saved && callBlocked ->
                                    R.string.notifications_are_off_so_i_can_t_call_you_yet_turn_them_on_i_52c0b7
                                else -> R.string.try_it_like_this_for_a_week_it_s_under_activity_on_the_talk_f71c6f
                            }),
                            stringResource(R.string.done)) { finish() }
                    }
                }
            }
        }
    }
}

/** The intro, and — once "Make my routine" is tapped — the list under it,
 *  in the same card. The button sits below the list, inside the card. */
@Composable
private fun RoutinePick(expanded: Boolean, selected: Set<StudyPlan.Kind>,
                        times: Map<StudyPlan.Kind, Int>, onTime: (StudyPlan.Kind, Int) -> Unit,
                        onToggle: (StudyPlan.Kind) -> Unit,
                        callMinutes: Int, onCallMinutes: (Int) -> Unit,
                        callHour: Int, callMinute: Int, onCallTime: (Int, Int) -> Unit,
                        days: Set<Int>, onToggleDay: (Int) -> Unit,
                        saving: Boolean, onButton: () -> Unit) {
    val res = LocalContext.current.resources
    val callStart = callHour * 60 + callMinute
    // Closed, the card is only as tall as its words and button; open, the
    // list fills it.
    Column(if (expanded) Modifier.fillMaxSize() else Modifier.fillMaxWidth()) {
        if (!expanded) {
            PickHeader(expanded = false,
                modifier = Modifier.padding(start = 24.dp, end = 24.dp, top = 28.dp, bottom = 20.dp))
        } else Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 16.dp)) {
            PickHeader(expanded = true,
                modifier = Modifier.padding(start = 8.dp, end = 8.dp, top = 16.dp, bottom = 4.dp))
                Column {
                    GroupedSectionHeader(stringResource(R.string.your_daily_call))
                    GroupedCard {
                        RoutineRow(StudyPlan.Kind.TALK, StudyPlan.Kind.TALK in selected, whenLine = null) {
                            onToggle(StudyPlan.Kind.TALK)
                        }
                        if (StudyPlan.Kind.TALK in selected) {
                            GroupedRowDivider()
                            Box(Modifier.padding(horizontal = 16.dp, vertical = 8.dp)) {
                                IosSegmented(CALL_CHOICES.map { res.getString(R.string.lld_min_b61908, it) },
                                    selected = CALL_CHOICES.indexOf(callMinutes).coerceAtLeast(0),
                                    onSelect = { onCallMinutes(CALL_CHOICES[it]) },
                                    modifier = Modifier.fillMaxWidth())
                            }
                            GroupedRowDivider()
                            Row(Modifier.fillMaxWidth().heightIn(min = 44.dp).padding(horizontal = 16.dp, vertical = 6.dp),
                                verticalAlignment = Alignment.CenterVertically) {
                                Text(stringResource(R.string.calls_at), style = MaterialTheme.typography.bodyLarge,
                                    modifier = Modifier.weight(1f))
                                IosCompactTimePicker(callHour, callMinute, onCallTime)
                            }
                        }
                        GroupedRowDivider()
                        DayChips(days, onToggleDay)
                    }
                    GroupedFooter(stringResource(R.string.routine_days_footer))
                    GroupedSectionHeader(stringResource(R.string.routine_add_more))
                    GroupedCard {
                        ROUTINE_OTHERS.forEachIndexed { i, kind ->
                            if (i > 0) GroupedRowDivider()
                            val on = kind in selected
                            // The call's time — and a ticked block's — is set
                            // right under it.
                            RoutineRow(kind, on, whenLine = if (on) null
                                else whenText(kind, callStart, callMinutes, selected, times, days.size == 7)) {
                                onToggle(kind)
                            }
                            // A ticked block's time, changed right on it.
                            if (on) {
                                val s = slot(kind, callStart, callMinutes, selected, times)
                                GroupedRowDivider(inset = true)
                                Row(Modifier.fillMaxWidth().heightIn(min = 44.dp)
                                    .padding(start = 54.dp, end = 16.dp, top = 6.dp, bottom = 6.dp),
                                    verticalAlignment = Alignment.CenterVertically) {
                                    Text(stringResource(R.string.routine_time), style = MaterialTheme.typography.bodyLarge,
                                        modifier = Modifier.weight(1f))
                                    IosCompactTimePicker(s.hour, s.minute) { h, m -> onTime(kind, h * 60 + m) }
                                }
                            }
                        }
                    }
                    GroupedFooter(stringResource(R.string.routine_add_more_footer))
                    Spacer(Modifier.height(16.dp))
                }
        }
        // Below the list, inside the card — not floating over it.
        Box(Modifier.fillMaxWidth().padding(start = 20.dp, end = 20.dp, top = 8.dp, bottom = 28.dp)) {
            Button(onClick = onButton, enabled = !saving, modifier = Modifier.fillMaxWidth()) {
                if (saving) {
                    CircularProgressIndicator(Modifier.size(18.dp), color = Color.White, strokeWidth = 2.dp)
                    Spacer(Modifier.width(8.dp))
                }
                Text(stringResource(when {
                    !expanded -> R.string.make_my_routine
                    selected.isEmpty() -> R.string.not_now
                    else -> R.string.done
                }))
            }
        }
    }
}

/** The card's top: the intro's words, then the list's. */
@Composable
private fun PickHeader(expanded: Boolean, modifier: Modifier) {
    Column(modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Icon(Icons.Filled.EditCalendar, contentDescription = null, tint = MaterialTheme.colorScheme.primary,
            modifier = Modifier.size(if (expanded) 34.dp else 44.dp))
        Text(stringResource(if (expanded) R.string.routine_what_goes_in else R.string.let_s_make_your_routine),
            style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold,
            textAlign = TextAlign.Center)
        Text(stringResource(if (expanded) R.string.routine_pick_as_many
            else R.string.try_it_just_as_it_is_for_a_week_you_can_change_it_any_time),
            style = MaterialTheme.typography.bodyMedium, textAlign = TextAlign.Center,
            color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

/** The days the routine runs on. Lit = a study day; at least one. */
@Composable
private fun DayChips(days: Set<Int>, onToggle: (Int) -> Unit) {
    val locale = LocalConfiguration.current.locales[0]
    Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp),
        horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        StudyPlan.weekOrder().forEach { wd ->
            val on = wd in days
            // Gregorian 1 = Sunday … 7 = Saturday.
            val dow = java.time.DayOfWeek.of(if (wd == 1) 7 else wd - 1)
            Box(Modifier.weight(1f).heightIn(min = 32.dp)
                .background(if (on) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface.copy(alpha = 0.08f),
                    CircleShape)
                .semantics { selected = on }
                .clickable(role = Role.Checkbox) { onToggle(wd) },
                contentAlignment = Alignment.Center) {
                Text(dow.getDisplayName(TextStyle.NARROW_STANDALONE, locale),
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = if (on) FontWeight.SemiBold else FontWeight.Normal,
                    color = if (on) MaterialTheme.colorScheme.onPrimary else MaterialTheme.colorScheme.onSurface)
            }
        }
    }
}

/** One kind: icon, name, two lines on what it is, when it would go, and a
 *  tick. */
@Composable
private fun RoutineRow(kind: StudyPlan.Kind, on: Boolean, whenLine: String?, onToggle: () -> Unit) {
    val res = LocalContext.current.resources
    Row(Modifier.fillMaxWidth()
        .semantics { selected = on }
        .clickable(role = Role.Checkbox, onClick = onToggle)
        .padding(horizontal = 16.dp, vertical = 14.dp),
        horizontalArrangement = Arrangement.spacedBy(14.dp)) {
        Icon(kind.icon(), contentDescription = null, tint = kind.color(),
            modifier = Modifier.padding(top = 2.dp).size(24.dp))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(RoutineText.label(res, kind), style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold)
            Text(pitch(kind), style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
            // The call's time is set right under it.
            if (whenLine != null) Text(whenLine, style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f))
        }
        Icon(if (on) Icons.Filled.CheckCircle else Icons.Outlined.Circle, contentDescription = null,
            tint = if (on) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface.copy(alpha = 0.3f),
            modifier = Modifier.align(Alignment.CenterVertically).size(28.dp))
    }
}

/** What each block is, for someone who has never done it. */
@Composable
private fun pitch(kind: StudyPlan.Kind): String = when (kind) {
    StudyPlan.Kind.TALK -> stringResource(R.string.routine_pitch_talk)
    StudyPlan.Kind.SAY_IT_AGAIN -> stringResource(R.string.routine_pitch_say_it_again)
    StudyPlan.Kind.LISTEN -> stringResource(R.string.routine_pitch_listen)
    StudyPlan.Kind.SHADOW -> stringResource(R.string.routine_pitch_shadow)
    StudyPlan.Kind.SPEECH -> stringResource(R.string.routine_pitch_speech)
    StudyPlan.Kind.REVIEW -> stringResource(R.string.routine_pitch_review)
    else -> ""
}

/** "Every day · 21:15" (just the time when the routine skips a day) — the
 *  time in the app language's own format, as iOS formats it with the UI
 *  locale. */
@Composable
private fun whenText(kind: StudyPlan.Kind, callStart: Int, callMinutes: Int, selected: Set<StudyPlan.Kind>,
                     times: Map<StudyPlan.Kind, Int>, everyDay: Boolean): String {
    val s = slot(kind, callStart, callMinutes, selected, times)
    val locale = LocalConfiguration.current.locales[0]
    val time = LocalTime.of(s.hour, s.minute)
        .format(DateTimeFormatter.ofLocalizedTime(FormatStyle.SHORT).withLocale(locale))
    return if (everyDay) stringResource(R.string.routine_every_day_at, time) else time
}

/** The review step's card content: a title, how to fix the grid (or why nothing can
 *  ring), and the confirm button. */
@Composable
private fun ConfirmContent(callBlocked: Boolean, working: Boolean, onBack: () -> Unit, onKeep: () -> Unit) {
    Column(Modifier.fillMaxWidth()
        .padding(start = 20.dp, end = 20.dp, top = 22.dp, bottom = 28.dp),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text(stringResource(R.string.routine_how_does_this_look), style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.SemiBold)
        Text(stringResource(if (callBlocked) R.string.notifications_are_off_so_i_can_t_call_you_yet_turn_them_on_i_52c0b7
            else R.string.routine_review_hint),
            style = MaterialTheme.typography.bodyMedium, textAlign = TextAlign.Center,
            color = MaterialTheme.colorScheme.onSurfaceVariant)
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            com.roro.futurevoice.ui.brand.IosTonalButton(onClick = onBack, enabled = !working,
                modifier = Modifier.width(120.dp)) {
                Text(stringResource(R.string.back), maxLines = 1)
            }
            Button(onClick = onKeep, enabled = !working, modifier = Modifier.weight(1f)) {
                Text(stringResource(R.string.routine_keep_it_like_this))
            }
        }
    }
}

/** The routine card's corner, all round: one floating card from the intro
 *  to the done card (iOS `SheetLikeCard`). */
private val SHEET_CARD_SHAPE = RoundedCornerShape(38.dp)

/** SwiftUI's `.easeIn`. */
private val EaseInCurve = CubicBezierEasing(0.42f, 0f, 1f, 1f)

/** The intro and the done step: an icon, a title, a line, one button. */
@Composable
private fun RoutineMessage(icon: androidx.compose.ui.graphics.vector.ImageVector, tint: Color,
                           title: String, body: String, button: String, onClick: () -> Unit) {
    Column(Modifier.fillMaxWidth().padding(start = 24.dp, end = 24.dp, top = 28.dp, bottom = 28.dp),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Icon(icon, contentDescription = null, tint = tint, modifier = Modifier.size(44.dp))
        Text(title, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold,
            textAlign = TextAlign.Center)
        Text(body, style = MaterialTheme.typography.bodyMedium, textAlign = TextAlign.Center,
            color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(bottom = 12.dp))
        Button(onClick = onClick, modifier = Modifier.fillMaxWidth()) { Text(button) }
    }
}
