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
import androidx.compose.foundation.layout.heightIn
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
import kotlinx.coroutines.launch
import androidx.compose.material.icons.filled.Sync
import androidx.compose.material.icons.filled.RecordVoiceOver
import androidx.compose.material.icons.filled.TextFields
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
enum class MePage { DAILY_CALL, VOICE, SOUND, APPEARANCE, DATA, GUIDE, CORE, APP_LANGUAGE, SCENE_VOICE }

/**
 * One pushed Settings page: back arrow, a centred inline title (iOS
 * `.navigationBarTitleDisplayMode(.inline)`), and the grouped ground.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MeSubpage(title: String, onBack: () -> Unit, content: @Composable ColumnScope.() -> Unit) {
    Scaffold(
        contentWindowInsets = fieldScaffoldInsets,
        topBar = {
            CenterAlignedTopAppBar(
                colors = AppSurfaces.topBarColors(),
                title = { com.roro.futurevoice.ui.brand.IosNavTitle(title) },
                navigationIcon = { com.roro.futurevoice.ui.brand.IosBackButton(onBack) },
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
                    MeRow(Icons.Filled.PhoneCallback, "%02d:%02d".format(m / 60, m % 60),
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
            if (enabled) R.string.every_talk_in_your_routine_with_a_set_time_is_a_call_your_ph_174441
            else R.string.instead_of_a_reminder_your_fluent_self_phones_you_at_your_ro_b08a01))
    }
}

// ── Voice ──────────────────────────────────────────────────────────────────

/**
 * iOS `voiceSection`, row for row: the clone's name, who plays a scene with
 * no saved person, accent, speaking speed, "Doesn't sound like you?", then
 * the two ways to a NEW clone — re-record, or rebuild from the recording
 * kept on the phone — each behind the same warning (it costs talk time and
 * the old voice is gone for good).
 */
@Composable
fun VoicePage(
    hasVoice: Boolean,
    voiceId: String?,
    targetLanguage: String,
    voiceAccentId: String?,
    personaName: String?,
    onPickAccent: () -> Unit,
    onCompare: () -> Unit,
    onRerecord: () -> Unit,
    onPickSceneVoice: () -> Unit,
    /** A clone rebuilt from the saved recording replaces the live one. */
    onRebuilt: (String) -> Unit,
    /** Then into the default accent (iOS `AppState.applyDefaultAccent`),
     *  awaited under the same spinner. */
    onApplyDefaultAccent: suspend () -> Unit = {},
    onBack: () -> Unit,
) {
    val context = LocalContext.current
    val scope = androidx.compose.runtime.rememberCoroutineScope()
    var nameTick by remember { mutableStateOf(0) }
    val displayName = remember(nameTick, personaName) {
        com.roro.futurevoice.data.VoiceName.display(context, personaName)
    }
    var renaming by remember { mutableStateOf(false) }
    var renameWarning by remember { mutableStateOf<String?>(null) }
    var confirmingRebuild by remember { mutableStateOf(false) }
    var rebuilding by remember { mutableStateOf(false) }
    var rebuildError by remember { mutableStateOf<String?>(null) }
    val hasSample = VoiceComparison.exists(context.filesDir)
    val changeStatus by com.roro.futurevoice.data.VoiceChanges.status
        .collectAsStateWithLifecycle()
    val canChange = changeStatus?.canChange ?: true
    val againLine = com.roro.futurevoice.data.VoiceChangeStatus.againLine(context, changeStatus?.nextAt)
    androidx.compose.runtime.LaunchedEffect(Unit) { com.roro.futurevoice.data.VoiceChanges.refresh() }
    MeSubpage(stringResource(R.string.voice), onBack) {
        GroupedSectionHeader(stringResource(R.string.voice))
        GroupedCard {
            MeRow(Icons.Filled.TextFields, stringResource(R.string.voice_name_f1c3a3, displayName),
                stringResource(R.string.what_your_clone_is_called_here_and_on_elevenlabs),
                kind = MeRowKind.ACTION, onClick = { renaming = true })
            GroupedRowDivider()
            val sceneId = com.roro.futurevoice.talk.VoicePreset.sceneDefaultId()
            MeRow(Icons.Filled.RecordVoiceOver,
                stringResource(R.string.scene_partner_voice,
                    com.roro.futurevoice.talk.StockPerson.by(sceneId).let {
                        com.roro.futurevoice.talk.VoicePreset.name(it.voiceId, it.name, targetLanguage)
                    }),
                stringResource(R.string.for_watch_scenes_without_a_saved_person),
                onClick = onPickSceneVoice)
            val accents = VoiceAccentCatalog.options(targetLanguage)
            if (hasVoice && accents.isNotEmpty()) {
                GroupedRowDivider()
                val applied = accents.firstOrNull { it.id == voiceAccentId }
                MeRow(Icons.Outlined.Language,
                    applied?.let { stringResource(R.string.accent_746770, accentLabel(it)) }
                        ?: stringResource(R.string.accent_233064),
                    stringResource(R.string.same_voice_the_accent_you_choose),
                    kind = MeRowKind.ACTION, onClick = onPickAccent)
            }
            // Under Accent because it is the same kind of question: the voice
            // stays theirs, only how it speaks changes. SYNTHESIS, not
            // playback — the pitch is untouched.
            GroupedRowDivider()
            var speed by remember { mutableStateOf(SpeechSpeed.current(context)) }
            MePickerRow(
                icon = Icons.Filled.Speed,
                title = stringResource(R.string.speaking_speed),
                value = stringResource(speed.label),
                options = SpeechSpeed.entries.map { it to stringResource(it.label) },
                selected = speed,
                onPick = { s ->
                    speed = s
                    SpeechSpeed.set(context, s)
                    com.roro.futurevoice.core.Analytics.capture("speech_speed_changed",
                        mapOf("speed" to s.raw, "where" to "me"))
                })
            // Above the re-record: it is the question people arrive with, and
            // most of the time what sounds foreign is the language.
            if (hasVoice && voiceId != null && hasSample) {
                GroupedRowDivider()
                MeRow(Icons.Filled.GraphicEq, stringResource(R.string.doesn_t_sound_like_you),
                    stringResource(R.string.hear_your_recording_and_your_clone_side_by_side),
                    kind = MeRowKind.ACTION, onClick = onCompare)
            }
            // Both make a new voice — the learner's one change per 30 days
            // (iOS 2026-10-09). With none left they say when, instead of
            // leading to a minute of reading and a refusal.
            GroupedRowDivider()
            MeRow(Icons.Filled.Mic, stringResource(R.string.re_record_voice),
                if (canChange) stringResource(R.string.replace_your_current_clone_with_a_new_one)
                else againLine,
                kind = MeRowKind.DESTRUCTIVE, enabled = canChange, onClick = onRerecord)
            if (hasSample) {
                GroupedRowDivider()
                MeRow(Icons.Filled.Sync, stringResource(R.string.regenerate_from_saved_recording),
                    if (canChange) stringResource(R.string.rebuild_the_clone_from_your_last_recording)
                    else againLine,
                    kind = MeRowKind.ACTION, enabled = !rebuilding && canChange,
                    trailing = if (rebuilding) ({
                        androidx.compose.material3.CircularProgressIndicator(
                            Modifier.size(18.dp), strokeWidth = 2.dp)
                    }) else null,
                    onClick = { confirmingRebuild = true })
            }
        }
    }

    if (renaming) {
        var draft by remember { mutableStateOf(displayName) }
        androidx.compose.material3.AlertDialog(
            onDismissRequest = { renaming = false },
            title = { Text(stringResource(R.string.voice_name_0e3b82)) },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text(stringResource(
                        R.string.names_your_clone_here_and_on_elevenlabs_leave_it_empty_to_go_d44a48))
                    androidx.compose.material3.OutlinedTextField(draft, { draft = it },
                        singleLine = true, placeholder = { Text("Future Self") })
                }
            },
            confirmButton = {
                androidx.compose.material3.TextButton(onClick = {
                    renaming = false
                    scope.launch {
                        runCatching {
                            com.roro.futurevoice.data.VoiceName.rename(context, draft, personaName, voiceId)
                        }.onFailure {
                            renameWarning = context.getString(
                                R.string.saved_here_but_elevenlabs_didn_t_accept_the_new_name_it_ll_b_76dd24,
                                it.message ?: "")
                        }
                        nameTick++
                    }
                }) { Text(stringResource(R.string.save)) }
            },
            dismissButton = {
                androidx.compose.material3.TextButton(onClick = { renaming = false }) {
                    Text(stringResource(R.string.cancel))
                }
            },
        )
    }
    renameWarning?.let { msg ->
        androidx.compose.material3.AlertDialog(
            onDismissRequest = { renameWarning = null },
            title = { Text(stringResource(R.string.renamed_on_this_device_only)) },
            text = { Text(msg) },
            confirmButton = {
                androidx.compose.material3.TextButton(onClick = { renameWarning = null }) {
                    Text(stringResource(R.string.ok))
                }
            },
        )
    }
    if (confirmingRebuild) {
        androidx.compose.material3.AlertDialog(
            onDismissRequest = { confirmingRebuild = false },
            title = { Text(stringResource(R.string.rebuild_your_voice)) },
            text = { Text(stringResource(
                R.string.cloning_again_uses_a_few_minutes_of_talk_time_your_current_v_551704) +
                "\n\n" + com.roro.futurevoice.data.VoiceChangeStatus.usesItLine(context)) },
            confirmButton = {
                androidx.compose.material3.TextButton(onClick = {
                    confirmingRebuild = false
                    rebuilding = true
                    scope.launch {
                        // iOS shows the failure's own words
                        // (`error.localizedDescription`), never a generic line.
                        runCatching {
                            com.roro.futurevoice.net.VoiceCloneClient(com.roro.futurevoice.data.AuthRepository())
                                .cloneVoice(
                                    name = com.roro.futurevoice.data.VoiceName.display(context, personaName),
                                    sample = VoiceComparison.sampleFile(context.filesDir),
                                    removeBackgroundNoise = false,
                                )
                        }.onSuccess { onRebuilt(it); onApplyDefaultAccent() }
                            .onFailure {
                                rebuildError = (it as? com.roro.futurevoice.data.VoiceChangeLimit)?.line(context)
                                    ?: it.localizedMessage ?: it.toString()
                            }
                        rebuilding = false
                    }
                }) {
                    Text(stringResource(R.string.rebuild), color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = {
                androidx.compose.material3.TextButton(onClick = { confirmingRebuild = false }) {
                    Text(stringResource(R.string.cancel))
                }
            },
        )
    }
    rebuildError?.let { msg ->
        androidx.compose.material3.AlertDialog(
            onDismissRequest = { rebuildError = null },
            title = { Text(stringResource(R.string.couldn_t_rebuild_your_voice)) },
            text = { Text(msg) },
            confirmButton = {
                androidx.compose.material3.TextButton(onClick = { rebuildError = null }) {
                    Text(stringResource(R.string.ok))
                }
            },
        )
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
                com.roro.futurevoice.ui.brand.IosSlider(
                    value = volume,
                    // 5% steps, snapped by hand (iOS `step: 0.05`, no dots).
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
                selected = mic,
                // Choosing here answers the one-time question for good.
                onPick = { mic = it; MicPreference.set(context, it) },
            )
        }
    }
}

// ── Appearance ─────────────────────────────────────────────────────────────

/**
 * iOS `appearancePage`: the Futureself palette as iOS's 3×2 grid of live
 * surfaces (`FutureselfThemePicker`), under iOS's System / Light / Dark segment.
 */
@Composable
fun AppearancePage(onPicked: (FutureselfTheme) -> Unit, onBack: () -> Unit) {
    MeSubpage(stringResource(R.string.appearance), onBack) {
        val context = LocalContext.current
        val mode by com.roro.futurevoice.data.AppAppearance.live(context).collectAsStateWithLifecycle()
        Spacer(Modifier.padding(top = 12.dp))
        GroupedCard {
            // iOS: `Picker("Theme")` segmented — System · Light · Dark — in
            // the same card as the palettes, above them.
            val modes = com.roro.futurevoice.data.AppAppearance.entries
            com.roro.futurevoice.ui.brand.IosSegmented(
                options = modes.map { stringResource(it.labelRes) },
                selected = modes.indexOf(mode ?: com.roro.futurevoice.data.AppAppearance.SYSTEM),
                onSelect = { com.roro.futurevoice.data.AppAppearance.set(context, modes[it]) },
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp),
            )
            androidx.compose.material3.HorizontalDivider(Modifier.padding(horizontal = 16.dp),
                thickness = 0.5.dp, color = MaterialTheme.colorScheme.outlineVariant)
            Column(Modifier.padding(horizontal = 16.dp, vertical = 12.dp)) {
                FutureselfThemePicker(onPicked)
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

// ── App language ───────────────────────────────────────────────────────────

/**
 * iOS `AppLanguagePage`: a PUSHED list, not a sheet — two sections because
 * the app can only half-keep the promise its name makes. A handful of
 * languages are translated end to end; the other sixty get coaching text in
 * their language while the app's own screens stay English, and the footers
 * say so BEFORE the tap. Each row is the language's own name and nothing
 * else (a tinted Button row, the tick trailing). Picking pops back, the way
 * a pushed Settings list does.
 */
@Composable
fun AppLanguagePage(current: String, onPick: (String) -> Unit, onBack: () -> Unit) {
    val groups = remember { com.roro.futurevoice.data.LanguageCatalog.nativeGroups() }
    fun isCurrent(code: String): Boolean {
        val now = com.roro.futurevoice.core.UILanguage.normalize(current)
        return current == code || now == code || (now == null && current.isBlank() && code == "en")
    }
    MeSubpage(stringResource(R.string.app_language), onBack) {
        @Composable fun section(codes: List<String>) {
            GroupedCard {
                codes.forEachIndexed { i, code ->
                    if (i > 0) androidx.compose.material3.HorizontalDivider(
                        Modifier.padding(horizontal = 16.dp), thickness = 0.5.dp,
                        color = MaterialTheme.colorScheme.outlineVariant)
                    Row(
                        Modifier.fillMaxWidth().clickable { onPick(code) }
                            .heightIn(min = 52.dp).padding(horizontal = 16.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(com.roro.futurevoice.data.LanguageCatalog.endonym(code),
                            Modifier.weight(1f), style = MaterialTheme.typography.bodyLarge,
                            color = MaterialTheme.colorScheme.primary)
                        if (isCurrent(code)) {
                            Icon(Icons.Filled.Check, contentDescription = null,
                                modifier = Modifier.size(20.dp),
                                tint = MaterialTheme.colorScheme.primary)
                        }
                    }
                }
            }
        }
        GroupedSectionHeader(stringResource(R.string.fully_translated))
        section(groups.translated)
        GroupedFooter(stringResource(
            R.string.everything_you_read_in_the_app_menus_buttons_corrections_not_493dbb))
        GroupedSectionHeader(stringResource(R.string.corrections_and_notes_only))
        section(groups.coachingOnly)
        GroupedFooter(stringResource(
            R.string.your_corrections_notes_and_word_meanings_come_back_in_this_l_95bb21))
    }
}
