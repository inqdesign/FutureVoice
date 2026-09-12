package com.roro.futurevoice.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import com.roro.futurevoice.data.AccountStatus
import com.roro.futurevoice.data.BillingGate
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.material3.AssistChip
import androidx.compose.material3.Button
import com.roro.futurevoice.data.CefrLevel
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.RecordVoiceOver
import androidx.compose.material.icons.filled.Palette
import androidx.compose.material.icons.filled.Groups
import com.roro.futurevoice.ui.brand.FutureselfTheme
import com.roro.futurevoice.data.AudioPrefs
import androidx.compose.material3.Slider
import androidx.compose.material.icons.filled.VolumeUp
import androidx.compose.runtime.mutableFloatStateOf
import com.roro.futurevoice.data.BackupService
import com.roro.futurevoice.data.BookExport
import androidx.compose.material.icons.filled.ImportExport
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.material3.OutlinedButton
import androidx.compose.runtime.rememberCoroutineScope
import kotlinx.coroutines.launch
import com.roro.futurevoice.data.AccountEraser
import androidx.compose.material.icons.filled.PrivacyTip
import androidx.compose.material.icons.filled.CardGiftcard
import androidx.compose.material.icons.filled.Translate
import androidx.compose.material.icons.filled.HelpOutline
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.WorkspacePremium
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import com.roro.futurevoice.R
import com.roro.futurevoice.ui.brand.AppSurfaces
import androidx.compose.runtime.LaunchedEffect
import com.roro.futurevoice.data.AuthRepository
import com.roro.futurevoice.data.LanguageCatalog
import com.roro.futurevoice.net.CoreClubClient
import com.roro.futurevoice.ui.brand.CoreSeal
import com.roro.futurevoice.talk.UserPersona

/**
 * Me — the settings surface, reduced to what exists on Android today:
 * profile (name/home + what the future self has learned, each note
 * removable — a memory that can't be corrected is a liability), the daily
 * goal, the learning language row, and sign out. Buying/metering rows arrive
 * with Play Billing.
 */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun MeScreen(
    email: String?,
    persona: UserPersona?,
    targetLanguage: String,
    nativeLanguage: String,
    onSavePersona: (UserPersona) -> Unit,
    enrolledLanguages: List<String>,
    onSwitchLanguage: (String) -> Unit,
    onAddLanguage: (String, CefrLevel) -> Unit,
    /** Whether this account has a clone — the Voice row's whole subject. */
    hasVoice: Boolean,
    /** Browsing the pool — the Talk header's own entry leads here too. */
    onOpenPeople: () -> Unit,
    /** Writing and publishing YOUR row. The row below says "publish your
     *  intro", and until now it opened the browser instead. */
    onOpenPublicIntro: () -> Unit,
    /** Me → Talk time: the month, the plan, then help. */
    onOpenPlanPage: () -> Unit,
    /** The live clone, and the accent it was remixed with. */
    voiceId: String? = null,
    voiceAccentId: String? = null,
    onAccentApplied: (voiceId: String, accentId: String) -> Unit = { _, _ -> },
    onEditProfile: () -> Unit,
    onOpenPaywall: () -> Unit,
    onSignOut: () -> Unit,
    /** Opens the consent read-back and withdrawal page. */
    onOpenPrivacy: () -> Unit,
    /** Re-reads state a restore just overwrote. */
    onRestored: () -> Unit,
    onBack: () -> Unit,
) {
    androidx.activity.compose.BackHandler(onBack = onBack)
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var confirmingSignOut by remember { mutableStateOf(false) }
    var confirmingDelete by remember { mutableStateOf(false) }
    var deleting by remember { mutableStateOf(false) }
    var deleteError by remember { mutableStateOf<String?>(null) }
    var coreProgress by remember { mutableStateOf<CoreClubClient.Progress?>(null) }
    LaunchedEffect(targetLanguage) {
        coreProgress = CoreClubClient(AuthRepository()).progress(targetLanguage)
    }
    var callEnabled by remember {
        mutableStateOf(com.roro.futurevoice.data.DailyCallStore.isEnabled(context))
    }
    var callHour by remember {
        mutableStateOf(com.roro.futurevoice.data.DailyCallStore.hour(context))
    }
    val notifPermission = androidx.activity.compose.rememberLauncherForActivityResult(
        androidx.activity.result.contract.ActivityResultContracts.RequestPermission()) { }
    var account by remember { mutableStateOf<AccountStatus?>(null) }
    var addingLanguage by remember { mutableStateOf(false) }
    var pickingTheme by remember { mutableStateOf(false) }
    var managingBackup by remember { mutableStateOf(false) }
    var pickingAccent by remember { mutableStateOf(false) }
    // Non-null while a pack or a restore is running — both are slow enough to
    // look hung, so the row says where it has got to.
    var backupStep by remember { mutableStateOf<BackupService.Step?>(null) }
    var backupResult by remember { mutableStateOf<String?>(null) }
    val importPicker = rememberLauncherForActivityResult(
        ActivityResultContracts.OpenDocument()
    ) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        scope.launch {
            runCatching { BackupService.import(context, uri) { backupStep = it } }
                .onSuccess { r ->
                    // The state flow was built from preferences the restore
                    // has since replaced, so it has to be re-read or the
                    // install keeps pointing at the old language.
                    onRestored()
                    backupResult = if (r.files == 0)
                        context.getString(R.string.that_file_held_no_practice_data)
                    else context.getString(R.string.restored_lld_files_and_lld_settings, r.files, r.defaults)
                }
                .onFailure { backupResult = it.message ?: "" }
            backupStep = null
        }
    }
    var callVolume by remember { mutableFloatStateOf(AudioPrefs.talkVoiceVolume(context)) }
    var theme by remember { mutableStateOf(FutureselfTheme.stored(context)) }
    LaunchedEffect(Unit) {
        account = AccountStatus.load(AuthRepository()).also { BillingGate.remember(it) }
    }
    var goal by remember {
        mutableStateOf(context.getSharedPreferences("futurevoice", 0)
            .getInt("futurevoice.dailyGoalMinutes", 10))
    }

    Scaffold(
        topBar = {
            TopAppBar(
                colors = AppSurfaces.topBarColors(),
                title = { Text(stringResource(R.string.me)) },
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
                .padding(horizontal = 16.dp).padding(bottom = 32.dp),
        ) {
            // ── Profile ──
            GroupedCard {
                MeRow(Icons.Filled.Person, stringResource(R.string.profile),
                    listOfNotNull(persona?.displayName?.takeIf { it.isNotBlank() },
                        persona?.city?.takeIf { it.isNotBlank() }).joinToString(" · ")
                        .ifEmpty { email.orEmpty() },
                    onClick = onEditProfile)
                // What the future self has learned — the other half of the
                // profile. Each note removable; the learner can always
                // correct the memory.
                persona?.learnedNotes?.takeIf { it.isNotEmpty() }?.forEach { note ->
                    GroupedRowDivider()
                    Row(Modifier.fillMaxWidth().padding(start = 14.dp, end = 4.dp),
                        verticalAlignment = Alignment.CenterVertically) {
                        Text(note.text, style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.weight(1f).padding(vertical = 10.dp))
                        TextButton(onClick = {
                            onSavePersona(persona.copy(
                                learnedNotes = persona.learnedNotes.filterNot { it.id == note.id }))
                        }) { Text("×") }
                    }
                }
            }

            // ── Subscribe / Subscription ──
            // On its own and first: this is the one control that decides
            // whether the app works at all.
            GroupedSectionSpacer()
            GroupedCard {
                val acct = account
                MeRow(Icons.Filled.AutoAwesome,
                    stringResource(
                        if (acct?.isEntitled == true) R.string.subscription
                        else R.string.subscribe),
                    when {
                        acct == null -> stringResource(R.string.checking)
                        acct.isEntitled -> {
                            val tier = if (acct.isPlusPlan) stringResource(R.string.plus)
                            else stringResource(R.string.light)
                            "$tier · " + stringResource(
                                R.string.lld_min_talked_this_month, acct.secondsUsedPeriod / 60)
                        }
                        else -> stringResource(R.string.talking_needs_a_plan)
                    },
                    onClick = onOpenPaywall)
            }

            // ── Talk time, and the club ──
            GroupedSectionSpacer()
            GroupedCard {
                // What was SPENT, never what is left: a remainder is a
                // monthly receipt for time NOT used.
                MeRow(Icons.Filled.Bolt, stringResource(R.string.talk_time),
                    account?.let {
                        stringResource(R.string.lld_min_talked_this_month,
                            it.secondsUsedPeriod / 60)
                    } ?: stringResource(R.string.checking),
                    onClick = onOpenPlanPage)
                GroupedRowDivider()
                MeRow(Icons.Filled.WorkspacePremium, stringResource(R.string.the_core),
                    coreSubtitle(coreProgress), onClick = null)
            }
            coreProgress?.let { GroupedFooter(coreFooter(it)) }

            // ── Practice ──
            GroupedSectionHeader(stringResource(R.string.practice))
            GroupedCard {
                Column(Modifier.padding(horizontal = 14.dp, vertical = 12.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(stringResource(R.string.daily_goal))
                    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        listOf(5, 10, 15, 20, 30).forEach { m ->
                            FilterChip(selected = goal == m, onClick = {
                                goal = m
                                context.getSharedPreferences("futurevoice", 0).edit()
                                    .putInt("futurevoice.dailyGoalMinutes", m).apply()
                            }, label = { Text(stringResource(R.string.lld_min_a_day, m)) })
                        }
                    }
                }
                GroupedRowDivider(inset = false)
                // Switching is a chip, not a page: every store already takes
                // the language as a parameter, so a switch is only a change
                // of which one they are handed.
                Column(Modifier.padding(horizontal = 14.dp, vertical = 12.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(stringResource(R.string.learn_which_language))
                    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        enrolledLanguages.forEach { code ->
                            FilterChip(
                                selected = code == targetLanguage,
                                onClick = { if (code != targetLanguage) onSwitchLanguage(code) },
                                label = { Text(LanguageCatalog.endonym(code)) },
                            )
                        }
                        // Never gated on a plan: every server pool is keyed
                        // per ACCOUNT with no language in it, so a second
                        // language adds no cost.
                        AssistChip(
                            onClick = { addingLanguage = true },
                            label = { Text(stringResource(R.string.add_a_language)) },
                        )
                    }
                    Text(
                        LanguageCatalog.ownName(targetLanguage, nativeLanguage),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }

            // ── Call — the habit anchor. Answering opens the talk. ──
            GroupedSectionHeader(stringResource(R.string.call))
            GroupedCard {
                Row(Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 8.dp),
                    verticalAlignment = Alignment.CenterVertically) {
                    Text(stringResource(R.string.daily_call), Modifier.weight(1f))
                    androidx.compose.material3.Switch(checked = callEnabled, onCheckedChange = { on ->
                        callEnabled = on
                        com.roro.futurevoice.data.DailyCallStore.set(context, on, callHour, 0)
                        if (on) notifPermission.launch(android.Manifest.permission.POST_NOTIFICATIONS)
                    })
                }
                if (callEnabled) {
                    // Without the exact-alarm grant the call still rings, just
                    // inside a window — say so rather than letting a learner
                    // wonder why 08:00 became 08:06. The route is a system
                    // settings page; there is no in-app prompt for it.
                    if (!com.roro.futurevoice.data.DailyCallScheduler
                            .canScheduleExact(context = context)) {
                        GroupedRowDivider(inset = false)
                        Row(
                            Modifier.fillMaxWidth()
                                .clickable {
                                    runCatching {
                                        context.startActivity(android.content.Intent(
                                            android.provider.Settings
                                                .ACTION_REQUEST_SCHEDULE_EXACT_ALARM,
                                            android.net.Uri.parse("package:${context.packageName}")))
                                    }
                                }
                                .padding(horizontal = 14.dp, vertical = 12.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(12.dp),
                        ) {
                            Column(Modifier.weight(1f)) {
                                Text(stringResource(R.string.ring_exactly_on_time))
                                Text(stringResource(R.string.without_this_the_call_can_arrive_a_few_minutes_late),
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                            Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight,
                                contentDescription = null, modifier = Modifier.size(18.dp),
                                tint = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                    GroupedRowDivider(inset = false)
                    FlowRow(
                        Modifier.padding(horizontal = 14.dp, vertical = 12.dp),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        listOf(7, 8, 9, 12, 19, 21).forEach { h ->
                            FilterChip(selected = callHour == h, onClick = {
                                callHour = h
                                com.roro.futurevoice.data.DailyCallStore.set(context, true, h, 0)
                            }, label = { Text("%02d:00".format(h)) })
                        }
                    }
                }
            }

            // ── The voice, and how it reaches the learner's ears ──
            GroupedSectionSpacer()
            GroupedCard {
                MeRow(Icons.Filled.RecordVoiceOver, stringResource(R.string.voice),
                    if (hasVoice) stringResource(R.string.your_cloned_voice)
                    else stringResource(R.string.not_set_up_yet),
                    onClick = null)
                // A clone recorded in the learner's own language carries no
                // target-language accent, so the model borrows a default.
                // Only offered where the catalog has options — an empty
                // picker is worse than no row.
                if (hasVoice && com.roro.futurevoice.data.VoiceAccentCatalog
                        .options(targetLanguage).isNotEmpty()) {
                    GroupedRowDivider()
                    MeRow(Icons.Filled.Translate, stringResource(R.string.accent),
                        com.roro.futurevoice.data.VoiceAccentCatalog
                            .options(targetLanguage).firstOrNull { it.id == voiceAccentId }?.label
                            ?: stringResource(R.string.as_recorded),
                        onClick = { pickingAccent = true })
                }
                GroupedRowDivider()
                // How loud the fluent self speaks. On Bluetooth a call plays
                // through the earphone's CALL chain, which the system's
                // headphone-safety cap does NOT limit — so with that cap on
                // the call can tower over everything else the app plays. We
                // cannot detect the cap and will not tell anyone to switch
                // off a hearing-safety setting; this brings the voice DOWN
                // to meet it.
                Column(Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 10.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        Icon(Icons.Filled.VolumeUp, contentDescription = null,
                            modifier = Modifier.size(20.dp),
                            tint = MaterialTheme.colorScheme.primary)
                        Text(stringResource(R.string.call_voice_volume), Modifier.weight(1f))
                        Text("${(callVolume * 100).toInt()}%",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    Slider(
                        value = callVolume,
                        onValueChange = { callVolume = it },
                        onValueChangeFinished = { AudioPrefs.setTalkVoiceVolume(context, callVolume) },
                        // Never to zero: a slider that can silence the fluent
                        // self is a way to make the app look broken.
                        valueRange = 0.25f..1f,
                        steps = 14,
                    )
                }
                GroupedRowDivider()
                MeRow(Icons.Filled.Groups, stringResource(R.string.find_people),
                    stringResource(R.string.publish_your_intro),
                    onClick = onOpenPublicIntro)
            }

            GroupedSectionSpacer()
            GroupedCard {
                MeRow(Icons.Filled.Palette, stringResource(R.string.appearance),
                    theme.label, onClick = { pickingTheme = true })
                GroupedRowDivider()
                // Moving progress between INSTALLS — the dev build and the
                // release build are separate sandboxes. The envelope is
                // iOS's, so a backup written on an iPhone opens here.
                MeRow(Icons.Filled.ImportExport, stringResource(R.string.practice_data),
                    backupStep?.let { stepLabel(it) }
                        ?: stringResource(R.string.export_or_import_this_devices_practice),
                    onClick = if (backupStep == null) ({ managingBackup = true }) else null)
                GroupedRowDivider()
                MeRow(Icons.Filled.PrivacyTip, stringResource(R.string.privacy),
                    if (com.roro.futurevoice.data.ConsentStore.hasVoiceConsent(context))
                        stringResource(R.string.voice_consent_policy)
                    else stringResource(R.string.policy),
                    onClick = onOpenPrivacy)
            }

            // ── Account ──
            GroupedSectionSpacer()
            GroupedCard {
                Row(Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 12.dp)) {
                    Text(email.orEmpty(), style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                if (com.roro.futurevoice.BuildConfig.DEBUG) {
                    GroupedRowDivider(inset = false)
                    PlainActionRow("Ring now (debug)",
                        MaterialTheme.colorScheme.primary) {
                        com.roro.futurevoice.data.DailyCallScheduler.ring(context)
                    }
                }
                GroupedRowDivider(inset = false)
                PlainActionRow(stringResource(R.string.sign_out_dc1649),
                    MaterialTheme.colorScheme.error) { confirmingSignOut = true }
                GroupedRowDivider(inset = false)
                // Play requires an in-app path to account deletion for any
                // app that creates accounts, and it has to be reachable —
                // not behind a support email.
                PlainActionRow(stringResource(R.string.delete_account),
                    MaterialTheme.colorScheme.error) { if (!deleting) confirmingDelete = true }
            }
        }
    }

    if (confirmingSignOut) {
        AlertDialog(
            onDismissRequest = { confirmingSignOut = false },
            title = { Text(stringResource(R.string.sign_out_b11555)) },
            confirmButton = {
                TextButton(onClick = { confirmingSignOut = false; onSignOut() }) {
                    Text(stringResource(R.string.sign_out_dc1649))
                }
            },
            dismissButton = {
                TextButton(onClick = { confirmingSignOut = false }) {
                    Text(stringResource(R.string.back_b52b36))
                }
            },
        )
    }

    if (confirmingDelete) {
        AlertDialog(
            onDismissRequest = { confirmingDelete = false },
            title = { Text(stringResource(R.string.delete_your_account)) },
            text = { Text(stringResource(R.string.this_permanently_deletes_your_voice_clone_talk_time_and_account)) },
            confirmButton = {
                TextButton(onClick = {
                    confirmingDelete = false
                    deleting = true
                    scope.launch {
                        // The server goes FIRST and the device is only erased
                        // once it succeeded — a local wipe on a failed request
                        // leaves a learner with a billable account they can no
                        // longer reach.
                        runCatching { AccountEraser.deleteAccount(context) }
                            .onSuccess { onSignOut() }
                            .onFailure { deleteError = it.message ?: "" }
                        deleting = false
                    }
                }) {
                    Text(stringResource(R.string.delete_forever),
                        color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = {
                TextButton(onClick = { confirmingDelete = false }) {
                    Text(stringResource(R.string.cancel))
                }
            },
        )
    }

    deleteError?.let { msg ->
        AlertDialog(
            onDismissRequest = { deleteError = null },
            title = { Text(stringResource(R.string.couldnt_delete_account)) },
            text = { Text(msg) },
            confirmButton = {
                TextButton(onClick = { deleteError = null }) { Text("OK") }
            },
        )
    }

    backupResult?.let { msg ->
        AlertDialog(
            onDismissRequest = { backupResult = null },
            title = { Text(stringResource(R.string.practice_data)) },
            text = { Text(msg) },
            confirmButton = {
                TextButton(onClick = { backupResult = null }) { Text("OK") }
            },
        )
    }

    if (managingBackup) {
        ModalBottomSheet(onDismissRequest = { managingBackup = false }) {
            Column(
                Modifier.fillMaxWidth().navigationBarsPadding()
                    .padding(horizontal = 20.dp).padding(bottom = 32.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                Text(stringResource(R.string.practice_data),
                    style = MaterialTheme.typography.titleLarge)
                Text(stringResource(R.string.a_backup_moves_your_practice_between_installs),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                Button(
                    onClick = {
                        managingBackup = false
                        scope.launch {
                            val file = runCatching {
                                BackupService.export(context) { backupStep = it }
                            }.getOrNull()
                            backupStep = null
                            // Build it with a visible bar, THEN share the
                            // finished file. Packing inside a share sheet is
                            // a minutes-long wait behind a screen that shows
                            // nothing.
                            file?.let { BookExport.share(context, it, "application/json") }
                        }
                    },
                    modifier = Modifier.fillMaxWidth(),
                ) { Text(stringResource(R.string.export_practice_data)) }
                OutlinedButton(
                    onClick = {
                        managingBackup = false
                        importPicker.launch(arrayOf("application/json"))
                    },
                    modifier = Modifier.fillMaxWidth(),
                ) { Text(stringResource(R.string.import_practice_data)) }
            }
        }
    }

    if (pickingAccent && voiceId != null) {
        VoiceAccentSheet(
            voiceId = voiceId,
            targetLanguage = targetLanguage,
            appliedAccentId = voiceAccentId,
            onApplied = onAccentApplied,
            onDismiss = { pickingAccent = false },
        )
    }

    if (pickingTheme) {
        AppearanceSheet(
            onPicked = { theme = it },
            onDismiss = { pickingTheme = false },
        )
    }

    if (addingLanguage) {
        AddLanguageSheet(
            nativeLanguage = nativeLanguage,
            enrolled = enrolledLanguages,
            onAdd = { code, level -> addingLanguage = false; onAddLanguage(code, level) },
            onDismiss = { addingLanguage = false },
        )
    }
}

/**
 * Pick a target and say roughly where you are IN IT.
 *
 * The level is asked here rather than inherited, because it cannot be
 * inherited: someone at C1 in English starting German is not a C1 German
 * speaker, and carrying the level across would pitch every reply and every
 * scene at the wrong band from the first turn.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun AddLanguageSheet(
    nativeLanguage: String,
    enrolled: List<String>,
    onAdd: (String, CefrLevel) -> Unit,
    onDismiss: () -> Unit,
) {
    // Shippable targets, minus their own native language and anything they
    // are already learning.
    val choices = remember(nativeLanguage, enrolled) {
        LanguageCatalog.selectableTargets.map { it.code }
            .filter { it != nativeLanguage && it !in enrolled }
    }
    var code by remember { mutableStateOf<String?>(null) }
    var level by remember { mutableStateOf(CefrLevel.A2) }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
    ) {
        Column(
            Modifier.fillMaxWidth().navigationBarsPadding().padding(horizontal = 20.dp).padding(bottom = 32.dp)
                .verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(stringResource(R.string.add_a_language),
                style = MaterialTheme.typography.titleLarge)
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                choices.forEach { c ->
                    FilterChip(
                        selected = code == c,
                        onClick = { code = c },
                        label = { Text(LanguageCatalog.endonym(c)) },
                    )
                }
            }
            if (choices.isEmpty()) {
                Text(stringResource(R.string.youre_learning_everything_we_offer),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }

            code?.let { picked ->
                Text(stringResource(R.string.where_are_you_in_lls,
                    LanguageCatalog.endonym(picked)),
                    style = MaterialTheme.typography.titleMedium,
                    modifier = Modifier.padding(top = 8.dp))
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    CefrLevel.entries.forEach { l ->
                        FilterChip(
                            selected = level == l,
                            onClick = { level = l },
                            label = { Text(l.code.uppercase()) },
                        )
                    }
                }
            }

            Button(
                onClick = { code?.let { onAdd(it, level) } },
                enabled = code != null,
                modifier = Modifier.fillMaxWidth().padding(top = 8.dp),
            ) { Text(stringResource(R.string.start_learning)) }
        }
    }
}

/**
 * Where a pack or a restore has got to.
 *
 * Both directions are slow enough to look hung — a full library is hundreds
 * of megabytes — so the per-file loops are counted, and the two opaque ends
 * (encoding the envelope, decoding it back) get named steps of their own
 * rather than a frozen row.
 */
@Composable
private fun stepLabel(step: BackupService.Step): String = when (step) {
    BackupService.Step.Scanning -> stringResource(R.string.scanning)
    is BackupService.Step.Packing ->
        stringResource(R.string.packing_lld_of_lld, step.done, step.total)
    BackupService.Step.Encoding -> stringResource(R.string.encoding)
    BackupService.Step.Decoding -> stringResource(R.string.decoding)
    is BackupService.Step.Writing ->
        stringResource(R.string.restoring_lld_of_lld, step.done, step.total)
}

/**
 * One settings row inside a grouped card.
 *
 * The subtitle is the SETTING'S CURRENT VALUE, not a description of the
 * screen behind it — that is what lets the page be read without opening
 * anything.
 */
@Composable
private fun MeRow(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    title: String,
    subtitle: String?,
    onClick: (() -> Unit)?,
) {
    Row(
        Modifier.fillMaxWidth()
            .then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier)
            .padding(horizontal = 14.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Icon(icon, contentDescription = null, modifier = Modifier.size(20.dp),
            tint = MaterialTheme.colorScheme.primary)
        Column(Modifier.weight(1f)) {
            Text(title)
            subtitle?.takeIf { it.isNotBlank() }?.let {
                Text(it, style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        if (onClick != null) {
            Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null,
                modifier = Modifier.size(18.dp),
                tint = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

/** A destructive or plain action, drawn as a list row rather than a button —
 *  the same shape iOS gives a `Button` inside a `Form`. */
@Composable
private fun PlainActionRow(
    title: String,
    color: androidx.compose.ui.graphics.Color,
    onClick: () -> Unit,
) {
    Row(
        Modifier.fillMaxWidth().clickable(onClick = onClick)
            .padding(horizontal = 14.dp, vertical = 14.dp),
    ) { Text(title, color = color) }
}

/** A BAR, never a rank: how many days in a row, against the entry streak. */
@Composable
private fun coreSubtitle(core: CoreClubClient.Progress?): String = when {
    core == null -> ""
    core.seated -> stringResource(R.string.you_re_in)
    else -> "${core.streak} / ${core.entry_streak}"
}

@Composable
private fun coreFooter(core: CoreClubClient.Progress): String =
    stringResource(R.string.s_100_seats_30_days_in_a_row_to_enter)
