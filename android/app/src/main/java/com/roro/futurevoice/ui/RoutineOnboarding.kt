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
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsBottomHeight
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowLeft
import androidx.compose.material.icons.filled.CheckCircle
import com.roro.futurevoice.data.RoutineText
import com.roro.futurevoice.ui.brand.IosLargeButtonHeight
import androidx.compose.material3.TextButton
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.EditCalendar
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
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.core.content.ContextCompat
import com.roro.futurevoice.R
import com.roro.futurevoice.data.DailyCallStore
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

private sealed interface RoutineStep {
    data object Intro : RoutineStep
    data class Item(val kind: StudyPlan.Kind) : RoutineStep
    data object Done : RoutineStep
}

/** The cards, in order. The call first (it sets the days), say it again
 *  right after it, as it is in the day. */
private val ROUTINE_KINDS = listOf(StudyPlan.Kind.TALK, StudyPlan.Kind.SAY_IT_AGAIN, StudyPlan.Kind.REVIEW,
    StudyPlan.Kind.SHADOW, StudyPlan.Kind.LISTEN, StudyPlan.Kind.SPEECH)

private val CALL_CHOICES = listOf(5, 10, 15, 20)
private val AMOUNT_CHOICES = mapOf(StudyPlan.Kind.REVIEW to listOf(10, 20, 40),
    StudyPlan.Kind.SHADOW to listOf(1, 3, 5))

/**
 * Onboarding's routine (iOS `RoutineOnboardingView`, 2026-10-18, founder:
 * "making the routine is the core"). It replaced three places that each set a
 * piece of it — setup's daily goal and purpose-made week, then a weekly-test
 * screen and a daily-call screen after the clone — with ONE: the My routine
 * grid itself, and a sheet over it.
 *
 * The sheet shows what there IS to do, one card at a time (iOS `4c0d8d7c`,
 * 2026-10-20, founder: not "how much will you study a day" but "here is what
 * you can study — put in what you want"): the daily call, say it again,
 * review, shadowing, listening, speech. Each card says what it is in one line
 * and asks when; "Add to my routine" puts it on the grid on the days chosen
 * on the first card, "Not interested" moves on. The call's card picks the
 * days because it comes first, and passing on it still keeps them. Shown over
 * the Talk tab once; Done shrinks it into the Activity chip, which is where
 * it lives from then on.
 *
 * The sheet is drawn in place, not as a modal: iOS lets the grid behind it
 * scroll (`presentationBackgroundInteraction(.enabled)`) and it cannot be
 * swiped away (`interactiveDismissDisabled`).
 */
@Composable
fun RoutineOnboardingOverlay(onFinished: () -> Unit, debugStep: String? = null) {
    val context = LocalContext.current
    val res = context.resources
    val scope = rememberCoroutineScope()

    var step by remember { mutableStateOf<RoutineStep>(RoutineStep.Intro) }
    var sheetUp by remember { mutableStateOf(false) }
    var spotlight by remember { mutableStateOf<PlanSpotlight?>(null) }
    var working by remember { mutableStateOf(false) }
    /** Notifications weren't allowed: the routine stands, but nothing can ring. */
    var callBlocked by remember { mutableStateOf(false) }

    var callMinutes by remember { mutableIntStateOf(5) }
    var callHour by remember { mutableIntStateOf(8) }
    var callMinute by remember { mutableIntStateOf(0) }
    var days by remember { mutableStateOf((1..7).toSet()) }
    /** Times chosen on the other cards (minutes past midnight); a card not
     *  visited yet reads its default ([defaultTime]). */
    var times by remember { mutableStateOf<Map<StudyPlan.Kind, Int>>(emptyMap()) }
    var amounts by remember { mutableStateOf(mapOf(StudyPlan.Kind.REVIEW to 10, StudyPlan.Kind.SHADOW to 1)) }
    /** What went in, by kind. */
    var picked by remember { mutableStateOf<Map<StudyPlan.Kind, StudyPlan.Block>>(emptyMap()) }
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
            "call_minutes" to (if (picked[StudyPlan.Kind.TALK] == null) 0 else callMinutes),
            "call_hour" to callHour,
            "days" to days.size,
            "picked" to ROUTINE_KINDS.filter { picked[it] != null }.joinToString(",") { it.raw },
            "call_on" to (picked[StudyPlan.Kind.TALK] != null && !callBlocked),
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
        // (call | sayItAgain | review | shadow | listen | speech | done).
        when (debugStep) {
            null -> {}
            "call" -> step = RoutineStep.Item(StudyPlan.Kind.TALK)
            "done" -> step = RoutineStep.Done
            else -> StudyPlan.Kind.entries.firstOrNull { it.raw == debugStep && it in ROUTINE_KINDS }
                ?.let { step = RoutineStep.Item(it) }
        }
    }

    fun previous(kind: StudyPlan.Kind): RoutineStep {
        val i = ROUTINE_KINDS.indexOf(kind)
        return if (i <= 0) RoutineStep.Intro else RoutineStep.Item(ROUTINE_KINDS[i - 1])
    }

    fun next(after: StudyPlan.Kind): RoutineStep {
        val i = ROUTINE_KINDS.indexOf(after)
        return if (i < 0 || i + 1 >= ROUTINE_KINDS.size) RoutineStep.Done else RoutineStep.Item(ROUTINE_KINDS[i + 1])
    }

    /** Where each card's block goes if the learner doesn't move it. Say it
     *  again sits right after the call, as it is in the day. */
    fun defaultTime(kind: StudyPlan.Kind): Int {
        val callEnd = callHour * 60 + callMinute + callMinutes
        val afterCall = if (callEnd + StudyPlan.SAY_IT_AGAIN_MINUTES <= 24 * 60) callEnd else 8 * 60 + 15
        return when (kind) {
            StudyPlan.Kind.SAY_IT_AGAIN -> if (picked[StudyPlan.Kind.TALK] != null) afterCall else 8 * 60 + 15
            StudyPlan.Kind.REVIEW -> 21 * 60
            StudyPlan.Kind.SHADOW -> 12 * 60 + 30
            StudyPlan.Kind.LISTEN -> 8 * 60 + 30
            StudyPlan.Kind.SPEECH -> 20 * 60
            else -> 8 * 60
        }
    }
    fun timeOf(kind: StudyPlan.Kind) = times[kind] ?: defaultTime(kind)
    fun amountOf(kind: StudyPlan.Kind) = amounts[kind] ?: kind.defaultAmount

    fun apply() {
        val blocks = ROUTINE_KINDS.mapNotNull { picked[it] }
        val plan = StudyPlanStore.current(context).withOnboardingRoutine(blocks, days)
        StudyPlanStore.update(context, plan, byLearner = true)
    }

    /** The call lands on the grid first, then the permission it needs is
     *  asked — with the block it is for in view behind the prompt. */
    suspend fun saveCall() {
        picked = picked + (StudyPlan.Kind.TALK to StudyPlan.Block(kind = StudyPlan.Kind.TALK, weekdays = days,
            hour = callHour, minute = callMinute, minutes = callMinutes))
        apply()
        context.getSharedPreferences("futurevoice", 0).edit()
            .putInt("futurevoice.dailyGoalMinutes", callMinutes).apply()
        StoreEvents.bump()
        spotlight = PlanSpotlight(StudyPlan.Kind.TALK, callHour * 60 + callMinute, (spotlight?.token ?: 0) + 1)
        delay(700)
        // The weekly test's "it's ready" notice rides on the same answer.
        WeeklyTestSettings.setReminderOn(context, true)
        val granted = requestPermission()
        WeeklyTestReminder.settleAfterPermission(context)
        DailyCallStore.setTimes(context, granted, StudyPlanStore.current(context).callTimes)
        callBlocked = !granted
        step = next(StudyPlan.Kind.TALK)
    }

    /** Any other card: on the grid, then — the first time a block that
     *  reminds goes in — the notification permission its reminder needs. */
    suspend fun save(kind: StudyPlan.Kind) {
        val at = timeOf(kind)
        val block = StudyPlan.Block(kind = kind, weekdays = days, hour = at / 60, minute = at % 60,
            minutes = amountOf(kind))
        picked = picked + (kind to block)
        apply()
        spotlight = PlanSpotlight(kind, block.startMinute, (spotlight?.token ?: 0) + 1)
        delay(500)
        requestReminderPermissionIfNeeded()
        step = next(kind)
    }

    /** Pass on it. Passing takes back one added before (Back, then a change
     *  of mind). */
    fun notInterested(kind: StudyPlan.Kind) {
        if (picked.containsKey(kind)) {
            picked = picked - kind
            apply()
            // No call in the routine: nothing rings.
            if (kind == StudyPlan.Kind.TALK) {
                DailyCallStore.setTimes(context, false, DailyCallStore.times(context))
            }
        }
        step = next(kind)
    }

    Box(Modifier.fillMaxSize().onGloballyPositioned { ownBounds = it.boundsInRoot() }) {
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

        val height by animateDpAsState(when (val s = step) {
            RoutineStep.Intro -> 300.dp
            is RoutineStep.Item -> when {
                s.kind == StudyPlan.Kind.TALK -> 520.dp
                AMOUNT_CHOICES[s.kind] == null -> 400.dp
                else -> 470.dp
            }
            RoutineStep.Done -> 300.dp
        }, tween(250), label = "routineSheet")
        AnimatedVisibility(visible = sheetUp, modifier = Modifier.align(Alignment.BottomCenter),
            enter = slideInVertically(tween(300)) { it }, exit = slideOutVertically(tween(300)) { it }) {
            Column(Modifier.fillMaxWidth()
                .shadow(16.dp, RoundedCornerShape(topStart = 38.dp, topEnd = 38.dp))
                .background(AppSurfaces.ground, RoundedCornerShape(topStart = 38.dp, topEnd = 38.dp))
                // The panel swallows touches — the grid behind still scrolls.
                .clickable(interactionSource = null, indication = null) {}) {
                Box(Modifier.fillMaxWidth().height(height)) {
                    when (val s = step) {
                        RoutineStep.Intro -> RoutineMessage(Icons.Filled.EditCalendar, MaterialTheme.colorScheme.primary,
                            stringResource(R.string.let_s_make_your_routine),
                            stringResource(R.string.try_it_just_as_it_is_for_a_week_you_can_change_it_any_time),
                            stringResource(R.string.make_my_routine)) { step = RoutineStep.Item(StudyPlan.Kind.TALK) }
                        RoutineStep.Done -> {
                            val empty = picked.isEmpty()
                            RoutineMessage(if (empty) Icons.Filled.CalendarMonth else Icons.Filled.CheckCircle,
                                if (empty) MaterialTheme.colorScheme.onSurfaceVariant else Color(0xFF34C759),
                                stringResource(if (empty) R.string.routine_make_it_later else R.string.your_routine_is_ready),
                                stringResource(when {
                                    empty -> R.string.routine_under_activity_whenever
                                    picked[StudyPlan.Kind.TALK] != null && callBlocked ->
                                        R.string.notifications_are_off_so_i_can_t_call_you_yet_turn_them_on_i_52c0b7
                                    else -> R.string.try_it_like_this_for_a_week_it_s_under_activity_on_the_talk_f71c6f
                                }),
                                stringResource(R.string.done)) { finish() }
                        }
                        is RoutineStep.Item -> if (s.kind == StudyPlan.Kind.TALK) RoutineForm(
                            title = stringResource(R.string.your_daily_call), onBack = null,
                            saving = working, canSave = days.isNotEmpty(),
                            onSave = { working = true; scope.launch { saveCall(); working = false } },
                            onSkip = { notInterested(StudyPlan.Kind.TALK) },
                        ) {
                            GroupedSectionHeader(stringResource(R.string.how_long_a_call))
                            GroupedCard { Box(Modifier.padding(horizontal = 16.dp, vertical = 8.dp)) {
                                IosSegmented(CALL_CHOICES.map { res.getString(R.string.lld_min_b61908, it) },
                                    selected = CALL_CHOICES.indexOf(callMinutes).coerceAtLeast(0),
                                    onSelect = { callMinutes = CALL_CHOICES[it] },
                                    modifier = Modifier.fillMaxWidth())
                            } }
                            GroupedSectionHeader(stringResource(R.string.when_))
                            GroupedCard {
                                Row(Modifier.fillMaxWidth().heightIn(min = 44.dp).padding(horizontal = 16.dp, vertical = 6.dp),
                                    verticalAlignment = Alignment.CenterVertically) {
                                    Text(stringResource(R.string.calls_at), style = MaterialTheme.typography.bodyLarge,
                                        modifier = Modifier.weight(1f))
                                    IosCompactTimePicker(callHour, callMinute) { h, m -> callHour = h; callMinute = m }
                                }
                                GroupedRowDivider(inset = false)
                                DayChips(days, onToggle = { wd ->
                                    days = if (wd in days) { if (days.size > 1) days - wd else days } else days + wd
                                })
                            }
                            GroupedFooter(stringResource(R.string.your_fluent_self_calls_you_at_this_time))
                        } else {
                            val kind = s.kind
                            RoutineForm(
                                title = RoutineText.label(res, kind), onBack = { step = previous(kind) },
                                saving = working, canSave = days.isNotEmpty(),
                                onSave = { working = true; scope.launch { save(kind); working = false } },
                                onSkip = { notInterested(kind) },
                            ) {
                                // What it is, in one line.
                                Spacer(Modifier.height(16.dp))
                                GroupedCard {
                                    Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp),
                                        verticalAlignment = Alignment.CenterVertically,
                                        horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                                        Icon(kind.icon(), contentDescription = null, tint = kind.color(),
                                            modifier = Modifier.size(22.dp))
                                        Text(pitch(kind), style = MaterialTheme.typography.bodyMedium)
                                    }
                                }
                                GroupedSectionHeader(stringResource(R.string.when_))
                                GroupedCard {
                                    Row(Modifier.fillMaxWidth().heightIn(min = 44.dp).padding(horizontal = 16.dp, vertical = 6.dp),
                                        verticalAlignment = Alignment.CenterVertically) {
                                        Text(stringResource(R.string.routine_time), style = MaterialTheme.typography.bodyLarge,
                                            modifier = Modifier.weight(1f))
                                        val at = timeOf(kind)
                                        IosCompactTimePicker(at / 60, at % 60) { h, m -> times = times + (kind to h * 60 + m) }
                                    }
                                    AMOUNT_CHOICES[kind]?.let { choices ->
                                        GroupedRowDivider(inset = false)
                                        Box(Modifier.padding(horizontal = 16.dp, vertical = 8.dp)) {
                                            IosSegmented(choices.map { RoutineText.amount(res, kind, it) },
                                                selected = choices.indexOf(amountOf(kind)).coerceAtLeast(0),
                                                onSelect = { amounts = amounts + (kind to choices[it]) },
                                                modifier = Modifier.fillMaxWidth())
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                Spacer(Modifier.windowInsetsBottomHeight(WindowInsets.navigationBars))
            }
        }
    }
}

/** What each card is, in one line. */
@Composable
private fun pitch(kind: StudyPlan.Kind): String = when (kind) {
    StudyPlan.Kind.SAY_IT_AGAIN -> stringResource(R.string.routine_pitch_say_it_again)
    StudyPlan.Kind.REVIEW -> stringResource(R.string.routine_pitch_review)
    StudyPlan.Kind.SHADOW -> stringResource(R.string.routine_pitch_shadow)
    StudyPlan.Kind.LISTEN -> stringResource(R.string.routine_pitch_listen)
    StudyPlan.Kind.SPEECH -> stringResource(R.string.routine_pitch_speech)
    else -> ""
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

/** A card: an inline title (with a back chevron after the first), a grouped
 *  form, and "Add to my routine" / "Not interested" pinned at the foot. */
@Composable
private fun RoutineForm(title: String, onBack: (() -> Unit)?, saving: Boolean, canSave: Boolean,
                        onSave: () -> Unit, onSkip: () -> Unit, content: @Composable () -> Unit) {
    Column(Modifier.fillMaxSize()) {
        Box(Modifier.fillMaxWidth().height(52.dp).padding(horizontal = 8.dp)) {
            if (onBack != null) {
                IconButton(onClick = onBack, modifier = Modifier.align(Alignment.CenterStart)) {
                    Icon(Icons.AutoMirrored.Filled.KeyboardArrowLeft, contentDescription = stringResource(R.string.back))
                }
            }
            Text(title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold,
                modifier = Modifier.align(Alignment.Center))
        }
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 16.dp)) {
            content()
        }
        Column(Modifier.fillMaxWidth().padding(start = 20.dp, end = 20.dp, bottom = 8.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Button(onClick = onSave, enabled = !saving && canSave, modifier = Modifier.fillMaxWidth()) {
                if (saving) {
                    CircularProgressIndicator(Modifier.size(18.dp), color = Color.White, strokeWidth = 2.dp)
                    Spacer(Modifier.width(8.dp))
                }
                Text(stringResource(R.string.routine_add_to_my_routine))
            }
            TextButton(onClick = onSkip, enabled = !saving,
                modifier = Modifier.fillMaxWidth().heightIn(min = IosLargeButtonHeight)) {
                Text(stringResource(R.string.routine_not_interested), style = MaterialTheme.typography.bodyLarge)
            }
        }
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
                    color = if (on) Color.White else MaterialTheme.colorScheme.onSurface)
            }
        }
    }
}
