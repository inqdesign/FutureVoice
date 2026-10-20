package com.roro.futurevoice.ui

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.animateDpAsState
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
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsBottomHeight
import androidx.compose.foundation.rememberScrollState
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

private enum class RoutineStep { INTRO, PICK, DONE }

/** The rows, in the order of a day. */
private val ROUTINE_KINDS = listOf(StudyPlan.Kind.TALK, StudyPlan.Kind.SAY_IT_AGAIN, StudyPlan.Kind.LISTEN,
    StudyPlan.Kind.SHADOW, StudyPlan.Kind.SPEECH, StudyPlan.Kind.REVIEW)

private const val CALL_MINUTES = 5

/** Where each block goes and how much it asks for (iOS
 *  `RoutineOnboardingView.slot`). Say it again sits right after the call, as
 *  it is in the day. */
private data class RoutineSlot(val hour: Int, val minute: Int, val amount: Int)

private fun slot(kind: StudyPlan.Kind): RoutineSlot = when (kind) {
    StudyPlan.Kind.TALK -> RoutineSlot(8, 0, CALL_MINUTES)
    StudyPlan.Kind.SAY_IT_AGAIN -> RoutineSlot(8, CALL_MINUTES, 1)
    StudyPlan.Kind.LISTEN -> RoutineSlot(8, 30, 1)
    StudyPlan.Kind.SHADOW -> RoutineSlot(12, 30, 1)
    StudyPlan.Kind.SPEECH -> RoutineSlot(20, 0, 1)
    StudyPlan.Kind.REVIEW -> RoutineSlot(21, 0, 10)
    else -> RoutineSlot(20, 0, kind.defaultAmount)
}

/**
 * Onboarding's routine (iOS `RoutineOnboardingView`, 2026-10-18, founder:
 * "making the routine is the core"). It replaced three places that each set a
 * piece of it — setup's daily goal and purpose-made week, then a weekly-test
 * screen and a daily-call screen after the clone — with ONE: the My routine
 * grid itself, and a sheet over it.
 *
 * The sheet asks what goes IN the routine (iOS `72e4610f`, 2026-10-20,
 * founder): every kind of block as a row of a list — what it is, in two
 * lines, and when it would go — and the learner ticks as many as they like.
 * Times and amounts are the defaults in [slot] and the footer says they can
 * be changed later; a card per kind asking for a time was tried the same day
 * and cut, because the times were the app's guess anyway and six cards of
 * different heights read as a form. Every picked block runs every day. Shown
 * over the Talk tab once; Done shrinks it into the Activity chip, which is
 * where it lives from then on.
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
            "call_minutes" to (if (StudyPlan.Kind.TALK in saved) CALL_MINUTES else 0),
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

    LaunchedEffect(Unit) {
        // A beat for the grid to be seen on its own first.
        delay(500)
        sheetUp = true
        // Capture build: `routine-onboarding-<step>` lands on a step
        // (pick | done | finish); `finish` runs Done by itself after a moment.
        when (debugStep) {
            "pick" -> step = RoutineStep.PICK
            "done" -> step = RoutineStep.DONE
            "finish" -> {
                step = RoutineStep.DONE
                delay(2_500)
                finish()
            }
        }
    }

    /** The ticked blocks on the grid, then the permission they need — the
     *  call's when the call is in, otherwise notifications for the
     *  reminders. */
    suspend fun save() {
        val blocks = ROUTINE_KINDS.filter { it in selected }.map { kind ->
            val s = slot(kind)
            StudyPlan.Block(kind = kind, weekdays = (1..7).toSet(), hour = s.hour, minute = s.minute,
                minutes = s.amount)
        }
        saved = selected
        val plan = StudyPlanStore.current(context).withOnboardingRoutine(blocks, (1..7).toSet())
        StudyPlanStore.update(context, plan, byLearner = true)
        step = RoutineStep.DONE
        val first = blocks.firstOrNull() ?: return
        spotlight = PlanSpotlight(first.kind, first.startMinute, (spotlight?.token ?: 0) + 1)
        delay(700)
        if (StudyPlan.Kind.TALK in saved) {
            context.getSharedPreferences("futurevoice", 0).edit()
                .putInt("futurevoice.dailyGoalMinutes", CALL_MINUTES).apply()
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
            WeeklyPlanEditor(onClose = {}, onboarding = true, spotlight = spotlight)
        }

        // iOS's `.large` detent: the whole screen but the status bar and a
        // sliver of the page behind.
        val insets = WindowInsets.statusBars.asPaddingValues().calculateTopPadding() +
            WindowInsets.navigationBars.asPaddingValues().calculateBottomPadding()
        val large = maxHeight - insets - 10.dp
        val height by animateDpAsState(if (step == RoutineStep.PICK) large else 300.dp, tween(250),
            label = "routineSheet")
        AnimatedVisibility(visible = sheetUp, modifier = Modifier.align(Alignment.BottomCenter),
            enter = slideInVertically(tween(300)) { it }, exit = slideOutVertically(tween(300)) { it }) {
            Column(Modifier.fillMaxWidth()
                .shadow(16.dp, RoundedCornerShape(topStart = 38.dp, topEnd = 38.dp))
                .background(AppSurfaces.ground, RoundedCornerShape(topStart = 38.dp, topEnd = 38.dp))
                // The panel swallows touches — the grid behind still scrolls.
                .clickable(interactionSource = null, indication = null) {}) {
                Box(Modifier.fillMaxWidth().height(height)) {
                    when (step) {
                        RoutineStep.INTRO -> RoutineMessage(Icons.Filled.EditCalendar, MaterialTheme.colorScheme.primary,
                            stringResource(R.string.let_s_make_your_routine),
                            stringResource(R.string.try_it_just_as_it_is_for_a_week_you_can_change_it_any_time),
                            stringResource(R.string.make_my_routine)) { step = RoutineStep.PICK }
                        RoutineStep.DONE -> {
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
                        RoutineStep.PICK -> RoutinePick(
                            selected = selected,
                            onToggle = { k -> selected = if (k in selected) selected - k else selected + k },
                            onBack = { step = RoutineStep.INTRO },
                            saving = working,
                            onSave = { working = true; scope.launch { save(); working = false } },
                        )
                    }
                }
                Spacer(Modifier.windowInsetsBottomHeight(WindowInsets.navigationBars))
            }
        }
    }
}

/** What goes in: an inline title with a back chevron, the list, and the
 *  button pinned at the foot on an opaque ground — the list scrolls under
 *  it and must not show through. */
@Composable
private fun RoutinePick(selected: Set<StudyPlan.Kind>, onToggle: (StudyPlan.Kind) -> Unit, onBack: () -> Unit,
                        saving: Boolean, onSave: () -> Unit) {
    Column(Modifier.fillMaxSize()) {
        Box(Modifier.fillMaxWidth().height(52.dp).padding(horizontal = 8.dp)) {
            IconButton(onClick = onBack, modifier = Modifier.align(Alignment.CenterStart)) {
                Icon(Icons.AutoMirrored.Filled.KeyboardArrowLeft, contentDescription = stringResource(R.string.back))
            }
            Text(stringResource(R.string.routine_what_goes_in), style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold, maxLines = 1,
                modifier = Modifier.align(Alignment.Center).padding(horizontal = 48.dp))
        }
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 16.dp)) {
            Spacer(Modifier.height(16.dp))
            GroupedCard {
                ROUTINE_KINDS.forEachIndexed { i, kind ->
                    if (i > 0) GroupedRowDivider()
                    RoutineRow(kind, kind in selected) { onToggle(kind) }
                }
            }
            GroupedFooter(stringResource(R.string.routine_pick_footer))
            Spacer(Modifier.height(16.dp))
        }
        Box(Modifier.fillMaxWidth().background(AppSurfaces.ground)
            .padding(horizontal = 20.dp, vertical = 8.dp)) {
            Button(onClick = onSave, enabled = !saving, modifier = Modifier.fillMaxWidth()) {
                if (saving) {
                    CircularProgressIndicator(Modifier.size(18.dp), color = Color.White, strokeWidth = 2.dp)
                    Spacer(Modifier.width(8.dp))
                }
                Text(stringResource(if (selected.isEmpty()) R.string.not_now else R.string.make_my_routine))
            }
        }
    }
}

/** One kind: icon, name, two lines on what it is, when it would go, and a
 *  tick. */
@Composable
private fun RoutineRow(kind: StudyPlan.Kind, on: Boolean, onToggle: () -> Unit) {
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
            Text(whenText(kind), style = MaterialTheme.typography.bodySmall,
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

/** "Every day · 8:00 AM", or "Right after the call" — the time in the app
 *  language's own format, as iOS formats it with the UI locale. */
@Composable
private fun whenText(kind: StudyPlan.Kind): String {
    if (kind == StudyPlan.Kind.SAY_IT_AGAIN) return stringResource(R.string.routine_right_after_call)
    val s = slot(kind)
    val locale = LocalConfiguration.current.locales[0]
    val time = LocalTime.of(s.hour, s.minute)
        .format(DateTimeFormatter.ofLocalizedTime(FormatStyle.SHORT).withLocale(locale))
    return stringResource(R.string.routine_every_day_at, time)
}

/** SwiftUI's `.easeIn`. */
private val EaseInCurve = CubicBezierEasing(0.42f, 0f, 1f, 1f)

/** The intro and the done step: an icon, a title, a line, one button. */
@Composable
private fun RoutineMessage(icon: androidx.compose.ui.graphics.vector.ImageVector, tint: Color,
                           title: String, body: String, button: String, onClick: () -> Unit) {
    Column(Modifier.fillMaxSize().padding(start = 24.dp, end = 24.dp, top = 28.dp, bottom = 12.dp),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Icon(icon, contentDescription = null, tint = tint, modifier = Modifier.size(44.dp))
        Text(title, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold,
            textAlign = TextAlign.Center)
        Text(body, style = MaterialTheme.typography.bodyMedium, textAlign = TextAlign.Center,
            color = MaterialTheme.colorScheme.onSurfaceVariant)
        Spacer(Modifier.weight(1f))
        Button(onClick = onClick, modifier = Modifier.fillMaxWidth()) { Text(button) }
    }
}
