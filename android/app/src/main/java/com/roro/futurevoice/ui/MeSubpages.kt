package com.roro.futurevoice.ui

import androidx.compose.foundation.background
import com.roro.futurevoice.ui.brand.ContinuousShape
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.filled.GraphicEq
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.NotificationsOff
import androidx.compose.material.icons.filled.PhoneCallback
import androidx.compose.material.icons.filled.RemoveCircle
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.Speed
import androidx.compose.material.icons.filled.Upload
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.Language
import androidx.compose.material.icons.outlined.MicNone
import androidx.compose.material.icons.outlined.VolumeUp
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Slider
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.LaunchedEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.roro.futurevoice.R
import kotlin.math.roundToInt
import com.roro.futurevoice.data.AudioPrefs
import com.roro.futurevoice.data.BackupService
import com.roro.futurevoice.data.DailyCallScheduler
import com.roro.futurevoice.data.DailyCallStore
import com.roro.futurevoice.data.MicPreference
import com.roro.futurevoice.data.SpeechSpeed
import com.roro.futurevoice.data.VoiceAccentCatalog
import com.roro.futurevoice.ui.brand.AppSurfaces
import com.roro.futurevoice.ui.brand.Futureself
import com.roro.futurevoice.ui.brand.FutureselfMode
import com.roro.futurevoice.ui.brand.FutureselfTheme

/** The Settings pages a row pushes (iOS `MeTab`'s NavigationLinks). */
enum class MePage { DAILY_CALL, VOICE, SOUND, APPEARANCE, DATA }

/**
 * One pushed Settings page: back arrow, a centred inline title (iOS
 * `.navigationBarTitleDisplayMode(.inline)`), and the grouped ground.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MeSubpage(title: String, onBack: () -> Unit, content: @Composable ColumnScope.() -> Unit) {
    Scaffold(
        topBar = {
            CenterAlignedTopAppBar(
                colors = AppSurfaces.topBarColors(),
                title = { Text(title, style = MaterialTheme.typography.titleMedium) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = null)
                    }
                },
            )
        }
    ) { padding ->
        Column(
            Modifier.padding(padding).fillMaxSize().background(AppSurfaces.ground)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp).padding(top = 8.dp, bottom = 32.dp),
            content = content,
        )
    }
}

// ── Daily call ─────────────────────────────────────────────────────────────

/**
 * iOS `dailyCallSection`: the switch, one row per call time, "Add a call".
 * Plus the two things only Android has to say: notifications are off (a call
 * that can't ring is the worst failure here), and exact alarms.
 */
@Composable
fun DailyCallPage(
    enabled: Boolean,
    times: List<Int>,
    onEnabledChange: (Boolean) -> Unit,
    onTimesChange: (List<Int>) -> Unit,
    onBack: () -> Unit,
) {
    val context = LocalContext.current
    MeSubpage(stringResource(R.string.daily_call), onBack) {
        // Read on every composition: the learner comes back from system
        // settings to this page, and the row should be gone when it's fixed.
        if (!androidx.core.app.NotificationManagerCompat.from(context).areNotificationsEnabled()) {
            GroupedCard {
                MeRow(Icons.Filled.NotificationsOff, stringResource(R.string.notifications_are_off),
                    stringResource(R.string.reminders_cant_reach_you), kind = MeRowKind.ACTION,
                    onClick = {
                        context.startActivity(
                            android.content.Intent(android.provider.Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                                .putExtra(android.provider.Settings.EXTRA_APP_PACKAGE, context.packageName)
                                .addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK))
                    })
            }
        }
        GroupedSectionHeader(stringResource(R.string.call))
        GroupedCard {
            MeRow(Icons.Filled.PhoneCallback, stringResource(R.string.daily_call),
                stringResource(R.string.your_fluent_self_phones_you), kind = MeRowKind.PLAIN,
                trailing = { com.roro.futurevoice.ui.brand.IosSwitch(checked = enabled, onCheckedChange = onEnabledChange) },
                onClick = { onEnabledChange(!enabled) })
            if (enabled) {
                // The routine's timed talks ARE the calls (iOS 1.1.4): the
                // times are read from it, and changed there.
                val plan by com.roro.futurevoice.data.StudyPlanStore.plan.collectAsStateWithLifecycle()
                LaunchedEffect(Unit) { com.roro.futurevoice.data.StudyPlanStore.current(context) }
                val callTimes = plan.callTimes
                if (callTimes.isEmpty()) {
                    GroupedRowDivider()
                    Text(stringResource(R.string.routine_no_timed_talk),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp))
                }
                callTimes.forEach { m ->
                    GroupedRowDivider()
                    MeRow(Icons.Filled.Schedule, "%02d:%02d".format(m / 60, m % 60),
                        kind = MeRowKind.PLAIN,
                        trailing = {
                            Text(routineWeekdaySummary(plan.callWeekdays(m)),
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant)
                        })
                }
                GroupedRowDivider()
                MeRow(Icons.Filled.CalendarMonth, stringResource(R.string.routine_change_in_routine),
                    kind = MeRowKind.ACTION, onClick = { RoutineNav.editorOpen.value = true })
                // Without the exact-alarm grant the call still rings, just
                // inside a window — say so rather than letting 08:00 become
                // 08:06 unexplained. The route is a system page.
                if (!DailyCallScheduler.canScheduleExact(context = context)) {
                    GroupedRowDivider()
                    MeRow(null, stringResource(R.string.ring_exactly_on_time),
                        stringResource(R.string.without_this_the_call_can_arrive_a_few_minutes_late),
                        onClick = {
                            runCatching {
                                context.startActivity(android.content.Intent(
                                    android.provider.Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM,
                                    android.net.Uri.parse("package:${context.packageName}")))
                            }
                        })
                }
            }
        }
        GroupedFooter(stringResource(
            if (enabled) R.string.your_phone_rings_at_every_time_you_set_here_even_on_silent_c_b210fc
            else R.string.instead_of_a_reminder_your_fluent_self_phones_you_once_a_day_30a288))
    }
}

// ── Voice ──────────────────────────────────────────────────────────────────

/** iOS `voiceSection`, as far as Android has its parts. */
@Composable
fun VoicePage(
    hasVoice: Boolean,
    voiceId: String?,
    targetLanguage: String,
    voiceAccentId: String?,
    onPickAccent: () -> Unit,
    onCompare: () -> Unit,
    onRerecord: () -> Unit,
    onBack: () -> Unit,
) {
    val context = LocalContext.current
    MeSubpage(stringResource(R.string.voice), onBack) {
        GroupedSectionHeader(stringResource(R.string.voice))
        GroupedCard {
            var first = true
            @Composable fun divider() { if (!first) GroupedRowDivider(); first = false }
            val accents = VoiceAccentCatalog.options(targetLanguage)
            if (hasVoice && accents.isNotEmpty()) {
                divider()
                val applied = accents.firstOrNull { it.id == voiceAccentId }
                MeRow(Icons.Outlined.Language,
                    applied?.let { stringResource(R.string.accent_746770, it.label) }
                        ?: stringResource(R.string.accent),
                    stringResource(R.string.same_voice_the_accent_you_choose),
                    kind = MeRowKind.ACTION, onClick = onPickAccent)
            }
            // Under Accent because it is the same kind of question: the voice
            // stays theirs, only how it speaks changes. SYNTHESIS, not
            // playback — the pitch is untouched.
            divider()
            var speed by remember { mutableStateOf(SpeechSpeed.current(context)) }
            MePickerRow(
                icon = Icons.Filled.Speed,
                title = stringResource(R.string.speaking_speed),
                value = stringResource(speed.label),
                options = SpeechSpeed.entries.map { it to stringResource(it.label) },
                onPick = { s ->
                    speed = s
                    SpeechSpeed.set(context, s)
                    com.roro.futurevoice.core.Analytics.capture("speech_speed_changed",
                        mapOf("speed" to s.raw, "where" to "me"))
                })
            // Above the re-record: it is the question people arrive with, and
            // most of the time what sounds foreign is the language.
            if (hasVoice && voiceId != null && VoiceComparison.exists(context.filesDir)) {
                divider()
                MeRow(Icons.Filled.GraphicEq, stringResource(R.string.doesn_t_sound_like_you),
                    stringResource(R.string.hear_your_recording_and_your_clone_side_by_side),
                    kind = MeRowKind.ACTION, onClick = onCompare)
            }
            if (hasVoice) {
                divider()
                MeRow(Icons.Filled.Mic, stringResource(R.string.re_record_voice),
                    stringResource(R.string.replace_your_current_clone_with_a_new_one),
                    kind = MeRowKind.DESTRUCTIVE, onClick = onRerecord)
            }
        }
    }
}

// ── Sound & mic ────────────────────────────────────────────────────────────

/** "Earphone mic · 80%" — both values, so the row answers without opening. */
@Composable
fun soundSummary(): String {
    val context = LocalContext.current
    val mic = stringResource(
        if (MicPreference.current(context) == MicPreference.PHONE) R.string.phone_mic
        else R.string.earphone_mic)
    return "$mic · ${(AudioPrefs.talkVoiceVolume(context) * 100).toInt()}%"
}

/**
 * iOS `soundSection`: hardware in the learner's hand, kept off the Voice
 * page. The mic row shows even with nothing connected — a setting that comes
 * and goes with a connection is one nobody can find when they want it.
 */
@Composable
fun SoundPage(onBack: () -> Unit) {
    val context = LocalContext.current
    var volume by remember { mutableFloatStateOf(AudioPrefs.talkVoiceVolume(context)) }
    var mic by remember { mutableStateOf(MicPreference.current(context)) }
    MeSubpage(stringResource(R.string.sound_mic), onBack) {
        Spacer(Modifier.padding(top = 12.dp))
        GroupedCard {
            // On Bluetooth a call plays through the CALL chain, which the
            // headphone-safety cap does not limit; this brings the voice DOWN
            // to meet it rather than asking anyone to switch a safety off.
            Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Row(Modifier.width(22.dp)) {
                        Icon(Icons.Outlined.VolumeUp, contentDescription = null,
                            modifier = Modifier.size(18.dp),
                            tint = MaterialTheme.colorScheme.primary)
                    }
                    Spacer(Modifier.width(12.dp))
                    Text(stringResource(R.string.call_voice_volume), Modifier.weight(1f),
                        style = MaterialTheme.typography.bodyLarge)
                    Text("${(volume * 100).toInt()}%",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                Slider(
                    value = volume,
                    // 5% steps, snapped by hand: Material's `steps` draws a
                    // dot per stop, which iOS's slider never shows.
                    onValueChange = { volume = (it * 20).roundToInt() / 20f },
                    onValueChangeFinished = { AudioPrefs.setTalkVoiceVolume(context, volume) },
                    // Never to zero: a slider that can silence the fluent self
                    // is a way to make the app look broken.
                    valueRange = 0.25f..1f,
                )
            }
            GroupedRowDivider()
            MePickerRow(
                icon = Icons.Outlined.MicNone,
                title = stringResource(R.string.mic_on_bluetooth),
                value = stringResource(
                    if (mic == MicPreference.PHONE) R.string.phone_mic else R.string.earphone_mic),
                options = listOf(
                    MicPreference.EARPHONE to stringResource(R.string.earphone_mic),
                    MicPreference.PHONE to stringResource(R.string.phone_mic)),
                // Choosing here answers the one-time question for good.
                onPick = { mic = it; MicPreference.set(context, it) },
            )
        }
    }
}

// ── Appearance ─────────────────────────────────────────────────────────────

/**
 * iOS `appearancePage`: the Futureself palette, each option drawn as the
 * real surface. (iOS also has a Light/Dark/System segment; Android follows
 * the system and has no such setting.)
 */
@Composable
fun AppearancePage(onPicked: (FutureselfTheme) -> Unit, onBack: () -> Unit) {
    val context = LocalContext.current
    var picked by remember { mutableStateOf(FutureselfTheme.stored(context)) }
    MeSubpage(stringResource(R.string.appearance), onBack) {
        Spacer(Modifier.padding(top = 12.dp))
        GroupedCard {
            FutureselfTheme.entries.forEachIndexed { i, theme ->
                if (i > 0) GroupedRowDivider(inset = false)
                Row(
                    Modifier.fillMaxWidth()
                        .clickable {
                            picked = theme
                            FutureselfTheme.pick(context, theme)
                            onPicked(theme)
                        }
                        .padding(horizontal = 16.dp, vertical = 10.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(14.dp),
                ) {
                    Futureself(
                        mode = FutureselfMode.IDLE, level = 0f, theme = theme,
                        virtualHeight = 64f,
                        modifier = Modifier.size(width = 64.dp, height = 34.dp)
                            .clip(CircleShape)
                            .border(if (theme == picked) 2.dp else 0.dp,
                                if (theme == picked) theme.tint()
                                else androidx.compose.ui.graphics.Color.Transparent,
                                CircleShape),
                    )
                    Text(theme.label, Modifier.weight(1f),
                        style = MaterialTheme.typography.bodyLarge)
                    if (theme == picked) {
                        Icon(Icons.Filled.Check, contentDescription = null,
                            tint = MaterialTheme.colorScheme.primary,
                            modifier = Modifier.size(20.dp))
                    }
                }
            }
        }
        GroupedFooter(stringResource(
            R.string.future_self_is_the_pixel_surface_behind_every_call_button_ta_f0338e))
    }
}

// ── Practice data ──────────────────────────────────────────────────────────

/**
 * iOS `backupSection`: build with a visible bar, THEN share the finished
 * file — packing inside a share sheet is a minutes-long wait behind a screen
 * that shows nothing.
 */
@Composable
fun DataPage(
    step: BackupService.Step?,
    exported: java.io.File?,
    onExport: () -> Unit,
    onShare: (java.io.File) -> Unit,
    onImport: () -> Unit,
    onBack: () -> Unit,
) {
    val context = LocalContext.current
    MeSubpage(stringResource(R.string.practice_data), onBack) {
        GroupedSectionHeader(stringResource(R.string.practice_data))
        GroupedCard {
            MeRow(Icons.Filled.Upload, stringResource(R.string.export_practice_data),
                kind = MeRowKind.ACTION, enabled = step == null, onClick = onExport)
            exported?.let { file ->
                GroupedRowDivider()
                MeRow(Icons.Outlined.CheckCircle, stringResource(R.string.share_backup),
                    android.text.format.Formatter.formatShortFileSize(context, file.length()),
                    kind = MeRowKind.ACTION, onClick = { onShare(file) })
            }
            GroupedRowDivider()
            MeRow(Icons.Filled.Download, stringResource(R.string.import_practice_data),
                kind = MeRowKind.ACTION, enabled = step == null, onClick = onImport)
            step?.let { s ->
                GroupedRowDivider()
                Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp),
                    verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    val fraction = when (s) {
                        is BackupService.Step.Packing -> s.done.toFloat() / s.total.coerceAtLeast(1)
                        is BackupService.Step.Writing -> s.done.toFloat() / s.total.coerceAtLeast(1)
                        else -> null
                    }
                    if (fraction != null) LinearProgressIndicator(
                        progress = { fraction }, modifier = Modifier.fillMaxWidth())
                    else LinearProgressIndicator(Modifier.fillMaxWidth())
                    Text(backupStepLabel(s), style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
        GroupedFooter(stringResource(
            R.string.everything_you_ve_practiced_on_this_device_talks_drills_word_498dd4))
    }
}

/** Where a pack or a restore has got to — both are slow enough to look hung. */
@Composable
fun backupStepLabel(step: BackupService.Step): String = when (step) {
    BackupService.Step.Scanning -> stringResource(R.string.scanning)
    is BackupService.Step.Packing ->
        stringResource(R.string.packing_lld_of_lld, step.done, step.total)
    BackupService.Step.Encoding -> stringResource(R.string.encoding)
    BackupService.Step.Decoding -> stringResource(R.string.decoding)
    is BackupService.Step.Writing ->
        stringResource(R.string.restoring_lld_of_lld, step.done, step.total)
}

/** "Every day", "Weekdays", "Weekends", or the days by name, Monday first —
 *  the way the routine draws its week (iOS `weekdaySummary`). */
@Composable
private fun routineWeekdaySummary(days: Set<Int>): String = when (days) {
    (1..7).toSet() -> stringResource(R.string.routine_every_day)
    (2..6).toSet() -> stringResource(R.string.routine_weekdays)
    setOf(1, 7) -> stringResource(R.string.routine_weekends)
    else -> {
        val fmt = java.text.SimpleDateFormat("EEE", java.util.Locale.getDefault())
        listOf(2, 3, 4, 5, 6, 7, 1).filter { it in days }.joinToString(" ") { wd ->
            fmt.format(java.util.Calendar.getInstance().apply { set(java.util.Calendar.DAY_OF_WEEK, wd) }.time)
        }
    }
}
