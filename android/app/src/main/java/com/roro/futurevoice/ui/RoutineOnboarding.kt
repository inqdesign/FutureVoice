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

private enum class RoutineStep { INTRO, CALL, STUDY, DONE }

private val CALL_CHOICES = listOf(5, 10, 15, 20)
private val STUDY_CHOICES = listOf(15, 30, 60)
/** "Around 9 in the evening" — the review slot study time goes into. */
private const val REVIEW_MINUTE = 21 * 60

/**
 * Onboarding's routine (iOS `RoutineOnboardingView`, 2026-10-18, founder:
 * "making the routine is the core"). It replaced three places that each set a
 * piece of it — setup's daily goal and purpose-made week, then a weekly-test
 * screen and a daily-call screen after the clone — with ONE: the My routine
 * grid itself, and a sheet over it that asks two things. How long the daily
 * call is, when and on which days; then how much study time there is, which
 * goes in as review at 21:00 on the same days. Each answer is written to the
 * plan on Save, so the learner watches it land on the grid. Shown over the
 * Talk tab once; Done shrinks it into the Activity chip, which is where it
 * lives from then on.
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

    var step by remember { mutableStateOf(RoutineStep.INTRO) }
    var sheetUp by remember { mutableStateOf(false) }
    var spotlight by remember { mutableStateOf<PlanSpotlight?>(null) }
    var working by remember { mutableStateOf(false) }
    /** Notifications weren't allowed: the routine stands, but nothing can ring. */
    var callBlocked by remember { mutableStateOf(false) }

    var callMinutes by remember { mutableIntStateOf(10) }
    var callHour by remember { mutableIntStateOf(8) }
    var callMinute by remember { mutableIntStateOf(0) }
    var days by remember { mutableStateOf((1..7).toSet()) }
    var studyMinutes by remember { mutableIntStateOf(30) }

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
        if (Build.VERSION.SDK_INT >= 33 && ContextCompat.checkSelfPermission(context,
                Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            val answer = CompletableDeferred<Boolean>()
            permissionAnswer = answer
            permission.launch(Manifest.permission.POST_NOTIFICATIONS)
            return answer.await()
        }
        return NotificationManagerCompat.from(context).areNotificationsEnabled()
    }

    fun finish() {
        com.roro.futurevoice.core.Analytics.capture("routine_onboarding", mapOf(
            "call_minutes" to callMinutes,
            "call_hour" to callHour,
            "days" to days.size,
            "study_minutes" to studyMinutes,
            "call_on" to !callBlocked,
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
        // Capture build: `routine-onboarding-<step>` lands on a step.
        when (debugStep) {
            "call" -> step = RoutineStep.CALL
            "study" -> step = RoutineStep.STUDY
            "done" -> step = RoutineStep.DONE
        }
    }

    fun apply(study: Int?) {
        val plan = StudyPlanStore.current(context).withOnboardingRoutine(
            callMinutes = callMinutes, callMinute = callHour * 60 + callMinute, days = days,
            studyMinutes = study, reviewMinute = REVIEW_MINUTE)
        StudyPlanStore.update(context, plan, byLearner = true)
    }

    /** The call lands on the grid first, then the permission it needs is
     *  asked — with the block it is for in view behind the prompt. */
    suspend fun saveCall() {
        apply(study = null)
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
        step = RoutineStep.STUDY
    }

    fun saveStudy() {
        apply(study = studyMinutes)
        spotlight = PlanSpotlight(StudyPlan.Kind.REVIEW, REVIEW_MINUTE, (spotlight?.token ?: 0) + 1)
        step = RoutineStep.DONE
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

        val height by animateDpAsState(when (step) {
            RoutineStep.INTRO -> 300.dp
            RoutineStep.CALL -> 470.dp
            RoutineStep.STUDY -> 330.dp
            RoutineStep.DONE -> 300.dp
        }, tween(250), label = "routineSheet")
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
                            stringResource(R.string.make_my_routine)) { step = RoutineStep.CALL }
                        RoutineStep.DONE -> RoutineMessage(Icons.Filled.CheckCircle, Color(0xFF34C759),
                            stringResource(R.string.your_routine_is_ready),
                            stringResource(if (callBlocked) R.string.notifications_are_off_so_i_can_t_call_you_yet_turn_them_on_i_52c0b7
                                else R.string.try_it_like_this_for_a_week_it_s_under_activity_on_the_talk_f71c6f),
                            stringResource(R.string.done)) { finish() }
                        RoutineStep.CALL -> RoutineForm(
                            title = stringResource(R.string.your_daily_call), onBack = null,
                            saving = working, canSave = days.isNotEmpty(),
                            onSave = { working = true; scope.launch { saveCall(); working = false } },
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
                        }
                        RoutineStep.STUDY -> RoutineForm(
                            title = stringResource(R.string.study_time), onBack = { step = RoutineStep.CALL },
                            saving = working, canSave = days.isNotEmpty(),
                            onSave = { saveStudy() },
                        ) {
                            GroupedSectionHeader(stringResource(R.string.how_much_can_you_study_a_day))
                            GroupedCard { Box(Modifier.padding(horizontal = 16.dp, vertical = 8.dp)) {
                                IosSegmented(STUDY_CHOICES.map {
                                    if (it == 60) res.getString(R.string.s_1_hour) else res.getString(R.string.lld_min_b61908, it)
                                }, selected = STUDY_CHOICES.indexOf(studyMinutes).coerceAtLeast(0),
                                    onSelect = { studyMinutes = STUDY_CHOICES[it] }, modifier = Modifier.fillMaxWidth())
                            } }
                            GroupedFooter(stringResource(R.string.i_ll_put_review_in_at_about_lld_cards_drag_it_on_the_grid_to_f20228,
                                reviewTimeText(), studyMinutes * StudyPlan.Kind.REVIEW_CARDS_PER_QUARTER / 15))
                        }
                    }
                }
                Spacer(Modifier.windowInsetsBottomHeight(WindowInsets.navigationBars))
            }
        }
    }
}

/** SwiftUI's `.easeIn`. */
private val EaseInCurve = CubicBezierEasing(0.42f, 0f, 1f, 1f)

/** 21:00 in the app language's own clock, as the call's picker draws it. */
@Composable
private fun reviewTimeText(): String {
    val locale = LocalConfiguration.current.locales[0]
    return LocalTime.of(REVIEW_MINUTE / 60, REVIEW_MINUTE % 60)
        .format(DateTimeFormatter.ofLocalizedTime(FormatStyle.SHORT).withLocale(locale))
}

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

/** The call and study steps: an inline title (with a back chevron on the
 *  second), a grouped form, and Save pinned at the foot. */
@Composable
private fun RoutineForm(title: String, onBack: (() -> Unit)?, saving: Boolean, canSave: Boolean,
                        onSave: () -> Unit, content: @Composable () -> Unit) {
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
        Button(onClick = onSave, enabled = !saving && canSave,
            modifier = Modifier.fillMaxWidth().padding(start = 20.dp, end = 20.dp, bottom = 8.dp)) {
            if (saving) {
                CircularProgressIndicator(Modifier.size(18.dp), color = Color.White, strokeWidth = 2.dp)
                Spacer(Modifier.width(8.dp))
            }
            Text(stringResource(R.string.save))
        }
    }
}

/** The days the call (and review) run on. Lit = a study day; at least one. */
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
