package com.roro.futurevoice.ui

import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.automirrored.filled.Logout
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Forum
import androidx.compose.material.icons.filled.NotificationsActive
import androidx.compose.material.icons.outlined.AddCircleOutline
import androidx.compose.material.icons.outlined.AutoAwesome
import androidx.compose.material.icons.outlined.Circle
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.Groups
import androidx.compose.material.icons.outlined.Language
import androidx.compose.material.icons.outlined.PanTool
import androidx.compose.material.icons.outlined.Palette
import androidx.compose.material.icons.outlined.PhoneCallback
import androidx.compose.material.icons.outlined.RecordVoiceOver
import androidx.compose.material.icons.outlined.Storage
import androidx.compose.material.icons.outlined.TrackChanges
import androidx.compose.material.icons.outlined.VolumeUp
import androidx.compose.material.icons.outlined.WorkspacePremium
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.roro.futurevoice.R
import com.roro.futurevoice.data.AccountEraser
import com.roro.futurevoice.data.AccountStatus
import com.roro.futurevoice.data.AuthRepository
import com.roro.futurevoice.data.BackupService
import com.roro.futurevoice.data.BillingGate
import com.roro.futurevoice.data.BookExport
import com.roro.futurevoice.data.CefrLevel
import com.roro.futurevoice.data.DailyCallStore
import com.roro.futurevoice.data.LanguageCatalog
import com.roro.futurevoice.data.LanguageScope
import com.roro.futurevoice.data.TalkTime
import com.roro.futurevoice.data.WeeklyReportStore
import com.roro.futurevoice.net.CoreClubClient
import com.roro.futurevoice.talk.UserPersona
import com.roro.futurevoice.ui.brand.AppSurfaces
import com.roro.futurevoice.ui.brand.CoreSeal
import com.roro.futurevoice.ui.brand.FutureselfTheme
import kotlinx.coroutines.launch

/**
 * Settings — iOS `MeTab`, row for row.
 *
 * The main list is a page of SUMMARIES: one row per topic, its current state
 * in the subtitle, and the controls behind a push ([MePage]). The flat list
 * that inlined every switch, slider and chip is what made this page look
 * nothing like iOS; the controls themselves are unchanged, only moved.
 *
 * Order (iOS `body`): profile · Subscribe · Usage + the Core · Learning ·
 * Daily call / Voice / Sound & mic / Find people · Appearance / Practice
 * data / Privacy · Say hello · Sign out + Delete account · Developer.
 */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun MeScreen(
    email: String?,
    persona: UserPersona?,
    targetLanguage: String,
    nativeLanguage: String,
    @Suppress("UNUSED_PARAMETER") onSavePersona: (UserPersona) -> Unit,
    enrolledLanguages: List<String>,
    onSwitchLanguage: (String) -> Unit,
    onAddLanguage: (String, CefrLevel) -> Unit,
    /**
     * A level changed by hand, for one language. Written to `LanguageScope`
     * here whether or not a host wires this up; the callback buys the
     * ACTIVE language's in-memory copy.
     */
    onSetLevel: ((String, CefrLevel) -> Unit)? = null,
    /** Whether this account has a clone — the Voice page's whole subject. */
    hasVoice: Boolean,
    @Suppress("UNUSED_PARAMETER") onOpenPeople: () -> Unit,
    /** Writing and publishing YOUR row (iOS pushes `PublicIntroView`). */
    onOpenPublicIntro: () -> Unit,
    /** Me → Usage: the month, the plan, then help. */
    onOpenPlanPage: () -> Unit,
    /** The live clone, and the accent it was remixed with. */
    voiceId: String? = null,
    voiceAccentId: String? = null,
    onAccentApplied: (voiceId: String, accentId: String) -> Unit = { _, _ -> },
    onRerecordVoice: () -> Unit = {},
    onPickAppLanguage: (String) -> Unit = {},
    onEditProfile: () -> Unit,
    /** The remembered lines live in the profile editor (iOS keeps them out
     *  of this list); kept so the host's wiring still compiles. */
    @Suppress("UNUSED_PARAMETER") onEditNotes: () -> Unit = onEditProfile,
    onOpenPaywall: () -> Unit,
    onSignOut: () -> Unit,
    /** Opens the consent read-back and withdrawal page. */
    onOpenPrivacy: () -> Unit,
    /** Re-reads state a restore just overwrote. */
    onRestored: () -> Unit,
    onBack: () -> Unit,
) {
    var page by rememberSaveable { mutableStateOf<MePage?>(null) }
    // Registered first, so the subpage's handler below wins while one is open.
    BackHandler(onBack = onBack)
    BackHandler(enabled = page != null) { page = null }

    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val mainScroll = rememberScrollState()
    var confirmingSignOut by remember { mutableStateOf(false) }
    var confirmingDelete by remember { mutableStateOf(false) }
    var deleting by remember { mutableStateOf(false) }
    var deleteError by remember { mutableStateOf<String?>(null) }
    var coreProgress by remember { mutableStateOf<CoreClubClient.Progress?>(null) }
    LaunchedEffect(targetLanguage) {
        coreProgress = CoreClubClient(AuthRepository()).progress(targetLanguage)
    }
    var callEnabled by remember { mutableStateOf(DailyCallStore.isEnabled(context)) }
    // Several calls a day: the chosen times, minutes after midnight. Kept in
    // edit order here; the store sorts and dedupes what it is handed.
    var callTimes by remember { mutableStateOf(DailyCallStore.times(context)) }
    val notifPermission = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()) { }
    var account by remember { mutableStateOf<AccountStatus?>(null) }
    var addingLanguage by remember { mutableStateOf(false) }
    var pickingAccent by remember { mutableStateOf(false) }
    var comparingVoice by remember { mutableStateOf(false) }
    var pickingAppLanguage by remember { mutableStateOf(false) }
    var confirmingRerecord by remember { mutableStateOf(false) }
    // Non-null while a pack or a restore is running — both are slow enough to
    // look hung, so the page says where it has got to.
    var backupStep by remember { mutableStateOf<BackupService.Step?>(null) }
    var backupResult by remember { mutableStateOf<String?>(null) }
    var exportedBackup by remember { mutableStateOf<java.io.File?>(null) }
    val importPicker = rememberLauncherForActivityResult(
        ActivityResultContracts.OpenDocument()
    ) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        scope.launch {
            backupStep = BackupService.Step.Decoding
            runCatching { BackupService.import(context, uri) { backupStep = it } }
                .onSuccess { r ->
                    // The state flow was built from preferences the restore
                    // has since replaced, so it has to be re-read.
                    onRestored()
                    backupResult = if (r.files == 0)
                        context.getString(R.string.that_file_held_no_practice_data)
                    else context.getString(R.string.restored_lld_files_and_lld_settings, r.files, r.defaults)
                }
                .onFailure { backupResult = it.message ?: "" }
            backupStep = null
        }
    }
    var theme by remember { mutableStateOf(FutureselfTheme.stored(context)) }
    LaunchedEffect(Unit) {
        account = AccountStatus.load(AuthRepository()).also { BillingGate.remember(it) }
    }
    var goal by remember {
        mutableStateOf(context.getSharedPreferences("futurevoice", 0)
            .getInt("futurevoice.dailyGoalMinutes", 10))
    }
    var showingCore by remember { mutableStateOf(false) }
    // Every enrolled language's level, read once.
    var levels by remember { mutableStateOf(mapOf<String, CefrLevel>()) }
    LaunchedEffect(enrolledLanguages) {
        levels = enrolledLanguages.associateWith { storedLevel(context, it) }
    }
    val setLevel: (String, CefrLevel) -> Unit = { code, level ->
        LanguageScope.setLevel(context, code, level.code)
        levels = levels + (code to level)
        onSetLevel?.invoke(code, level)
    }
    // The weekly report's pooled estimate — the same source Progress
    // publishes. No report means no row, never a guess.
    var aiLevel by remember { mutableStateOf<CefrLevel?>(null) }
    LaunchedEffect(targetLanguage) {
        aiLevel = WeeklyReportStore.shared(context).latest(targetLanguage)
            ?.cefrLevel?.let { CefrLevel.from(it) }
    }

    val setCallEnabled: (Boolean) -> Unit = { on ->
        callEnabled = on
        DailyCallStore.setTimes(context, on, callTimes)
        if (on) notifPermission.launch(android.Manifest.permission.POST_NOTIFICATIONS)
    }

    when (page) {
        MePage.DAILY_CALL -> DailyCallPage(
            enabled = callEnabled,
            times = callTimes,
            onEnabledChange = setCallEnabled,
            onTimesChange = { next ->
                callTimes = next
                DailyCallStore.setTimes(context, true, next)
            },
            onBack = { page = null; callTimes = DailyCallStore.times(context) },
        )
        MePage.VOICE -> VoicePage(
            hasVoice = hasVoice, voiceId = voiceId, targetLanguage = targetLanguage,
            voiceAccentId = voiceAccentId,
            onPickAccent = { pickingAccent = true },
            onCompare = { comparingVoice = true },
            onRerecord = { confirmingRerecord = true },
            onBack = { page = null },
        )
        MePage.SOUND -> SoundPage(onBack = { page = null })
        MePage.APPEARANCE -> AppearancePage(onPicked = { theme = it }, onBack = { page = null })
        MePage.DATA -> DataPage(
            step = backupStep,
            exported = exportedBackup,
            onExport = {
                exportedBackup = null
                backupStep = BackupService.Step.Scanning
                scope.launch {
                    runCatching { BackupService.export(context) { backupStep = it } }
                        .onSuccess { exportedBackup = it }
                        .onFailure { backupResult = it.message ?: "" }
                    backupStep = null
                }
            },
            onShare = { BookExport.share(context, it, "application/json") },
            onImport = { importPicker.launch(arrayOf("application/json")) },
            onBack = { page = null },
        )
        null -> Scaffold(
            topBar = {
                CenterAlignedTopAppBar(
                    colors = AppSurfaces.topBarColors(),
                    title = { Text(stringResource(R.string.settings),
                        style = MaterialTheme.typography.titleMedium) },
                    // A sheet that closes with Done, as on iOS — no back arrow.
                    // The system back gesture still closes it.
                    actions = {
                        TextButton(onClick = onBack) {
                            Text(stringResource(R.string.done),
                                style = MaterialTheme.typography.bodyLarge,
                                fontWeight = FontWeight.SemiBold)
                        }
                    },
                )
            }
        ) { padding ->
            Column(
                Modifier.padding(padding).fillMaxSize().background(AppSurfaces.ground)
                    .verticalScroll(mainScroll)
                    .padding(horizontal = 16.dp).padding(top = 12.dp, bottom = 32.dp),
            ) {
                // ── Profile ──
                GroupedCard { ProfileHeader(persona, onEditProfile) }

                // ── Subscribe / Subscription ── on its own and first: the one
                // control that decides whether the app works at all.
                GroupedSectionSpacer()
                GroupedCard {
                    val acct = account
                    // Nothing is claimed until the account answers: "Talking
                    // needs a plan" under a spinner tells a subscriber they
                    // have no plan.
                    val hasPlan = acct == null || acct.isEntitled || acct.unlimited
                    MeRow(Icons.Outlined.AutoAwesome,
                        stringResource(if (hasPlan) R.string.subscription else R.string.subscribe),
                        if (hasPlan) null else stringResource(R.string.talking_needs_a_plan),
                        kind = MeRowKind.ACTION,
                        value = when {
                            acct == null -> stringResource(R.string.checking)
                            acct.unlimited -> "Admin"
                            acct.isPlusPlan -> stringResource(R.string.plan_tier_plus)
                            acct.isEntitled -> stringResource(R.string.plan_tier_light)
                            else -> null
                        },
                        onClick = onOpenPaywall)
                }

                // ── Usage, and the club ──
                GroupedSectionSpacer()
                GroupedCard {
                    MeRow(Icons.Filled.Bolt, stringResource(R.string.usage),
                        talkTimeLabel(account), onClick = onOpenPlanPage)
                    GroupedRowDivider()
                    // Filled seal only while seated — the seal is current
                    // membership, never a past one.
                    MeRow(Icons.Outlined.WorkspacePremium, stringResource(R.string.the_core),
                        coreSubtitle(coreProgress),
                        leading = if (coreProgress?.seated == true) ({ CoreSeal(size = 18.dp) })
                        else null,
                        onClick = { showingCore = true })
                }

                // ── Learning ──
                GroupedSectionHeader(stringResource(R.string.learning))
                GroupedCard {
                    enrolledLanguages.forEachIndexed { index, code ->
                        if (index > 0) GroupedRowDivider()
                        LanguageRow(
                            code = code,
                            active = code == targetLanguage,
                            level = levels[code] ?: CefrLevel.B1,
                            onSelect = { if (code != targetLanguage) onSwitchLanguage(code) },
                            onLevel = { setLevel(code, it) },
                        )
                    }
                    // A SUGGESTION, never an assignment: only a tap moves it.
                    aiLevel?.takeIf { levels[targetLanguage] != null && it != levels[targetLanguage] }
                        ?.let { ai ->
                            GroupedRowDivider()
                            MeRow(Icons.Outlined.AutoAwesome,
                                stringResource(R.string.ai_read_tap_to_apply, ai.code.uppercase()),
                                stringResource(R.string.from_your_recent_conversations,
                                    LanguageCatalog.endonym(targetLanguage)),
                                kind = MeRowKind.ACTION,
                                onClick = { setLevel(targetLanguage, ai) })
                        }
                    GroupedRowDivider()
                    // Never gated on a plan: every pool is keyed per ACCOUNT.
                    MeRow(Icons.Outlined.AddCircleOutline, stringResource(R.string.add_a_language),
                        stringResource(R.string.same_voice_new_language),
                        kind = MeRowKind.ACTION,
                        onClick = { addingLanguage = true })
                    GroupedRowDivider()
                    MePickerRow(
                        icon = Icons.Outlined.TrackChanges,
                        title = stringResource(R.string.daily_goal),
                        subtitle = stringResource(R.string.minutes_of_speaking_per_day),
                        value = stringResource(R.string.lld_min_b61908, goal),
                        options = listOf(5, 10, 15, 20, 30, 45, 60)
                            .map { it to stringResource(R.string.lld_min_b61908, it) },
                        onPick = { m ->
                            goal = m
                            context.getSharedPreferences("futurevoice", 0).edit()
                                .putInt("futurevoice.dailyGoalMinutes", m).apply()
                        },
                    )
                    GroupedRowDivider()
                    MeRow(Icons.Outlined.Language, stringResource(R.string.app_language),
                        AppLanguageNames.of(nativeLanguage),
                        onClick = { pickingAppLanguage = true })
                }
                GroupedFooter(stringResource(
                    R.string.tap_a_language_to_practice_it_its_level_calibrates_every_con_1ff279))

                // ── Call, voice, sound, people ──
                GroupedSectionSpacer()
                GroupedCard {
                    MeRow(Icons.Outlined.PhoneCallback, stringResource(R.string.daily_call),
                        if (callEnabled) callTimes.sorted().joinToString(" · ") {
                            "%02d:%02d".format(it / 60, it % 60)
                        } else stringResource(R.string.off),
                        onClick = { page = MePage.DAILY_CALL })
                    GroupedRowDivider()
                    MeRow(Icons.Outlined.RecordVoiceOver, stringResource(R.string.voice),
                        stringResource(if (hasVoice) R.string.your_cloned_voice
                            else R.string.not_set_up_yet),
                        onClick = { page = MePage.VOICE })
                    GroupedRowDivider()
                    MeRow(Icons.Outlined.VolumeUp, stringResource(R.string.sound_mic),
                        soundSummary(), onClick = { page = MePage.SOUND })
                    GroupedRowDivider()
                    MeRow(Icons.Outlined.Groups, stringResource(R.string.find_people),
                        stringResource(R.string.publish_your_intro),
                        onClick = onOpenPublicIntro)
                }

                // ── Appearance, data, privacy ──
                GroupedSectionSpacer()
                GroupedCard {
                    MeRow(Icons.Outlined.Palette, stringResource(R.string.appearance),
                        theme.label, onClick = { page = MePage.APPEARANCE })
                    GroupedRowDivider()
                    MeRow(Icons.Outlined.Storage, stringResource(R.string.practice_data),
                        backupStep?.let { backupStepLabel(it) }
                            ?: stringResource(R.string.export_or_import_this_devices_practice),
                        onClick = { page = MePage.DATA })
                    GroupedRowDivider()
                    MeRow(Icons.Outlined.PanTool, stringResource(R.string.privacy),
                        if (com.roro.futurevoice.data.ConsentStore.hasVoiceConsent(context))
                            stringResource(R.string.voice_consent_policy)
                        else stringResource(R.string.policy),
                        onClick = onOpenPrivacy)
                }

                // ── Say hello ── one tap to the person who builds this.
                val channels = com.roro.futurevoice.data.SupportChannel.available
                if (channels.isNotEmpty()) {
                    GroupedSectionHeader(stringResource(R.string.say_hello))
                    GroupedCard {
                        channels.forEachIndexed { i, channel ->
                            if (i > 0) GroupedRowDivider()
                            MeRow(
                                if (channel == com.roro.futurevoice.data.SupportChannel.INSTAGRAM)
                                    Icons.Filled.Forum else Icons.AutoMirrored.Filled.Send,
                                stringResource(channel.titleRes), channel.subtitle,
                                kind = MeRowKind.ACTION,
                                onClick = channel.url?.let { url -> {
                                    runCatching {
                                        context.startActivity(android.content.Intent(
                                            android.content.Intent.ACTION_VIEW,
                                            android.net.Uri.parse(url)).apply {
                                            addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
                                        })
                                    }
                                } })
                        }
                    }
                    GroupedFooter(stringResource(
                        R.string.one_person_builds_this_app_and_reads_every_message_tell_me_w_bd3eae))
                }

                // ── Account ──
                GroupedSectionSpacer()
                GroupedCard {
                    MeRow(Icons.AutoMirrored.Filled.Logout, stringResource(R.string.sign_out_dc1649),
                        kind = MeRowKind.DESTRUCTIVE, onClick = { confirmingSignOut = true })
                    GroupedRowDivider()
                    // Play requires an in-app, reachable path to deletion.
                    MeRow(Icons.Outlined.Delete, stringResource(R.string.delete_account),
                        kind = MeRowKind.DESTRUCTIVE, enabled = !deleting,
                        trailing = if (deleting) ({
                            CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
                        }) else null,
                        onClick = { confirmingDelete = true })
                }
                // Which account this is — iOS has no row for it; on Android the
                // email was on this card, so it rides in the footer instead.
                GroupedFooter(listOfNotNull(
                    stringResource(
                        R.string.deleting_your_account_permanently_removes_your_voice_clone_t_43bafb),
                    email?.takeIf { it.isNotBlank() },
                ).joinToString("\n\n"))

                // Never in a capture build — a dev button is gallery noise.
                if (com.roro.futurevoice.BuildConfig.DEBUG &&
                    com.roro.futurevoice.BuildConfig.BUILD_TYPE != "capture") {
                    GroupedSectionHeader(stringResource(R.string.developer))
                    GroupedCard {
                        MeRow(Icons.Filled.NotificationsActive, "Ring now (debug)",
                            kind = MeRowKind.ACTION,
                            onClick = { com.roro.futurevoice.data.DailyCallScheduler.ring(context) })
                    }
                }
            }
        }
    }

    if (showingCore) {
        CoreClubSheet(coreProgress) { showingCore = false }
    }

    if (confirmingSignOut) {
        AlertDialog(
            onDismissRequest = { confirmingSignOut = false },
            title = { Text(stringResource(R.string.sign_out_b11555)) },
            text = { Text(stringResource(
                R.string.your_practice_data_stays_on_this_device_your_voice_clone_and_2c4c4e)) },
            confirmButton = {
                TextButton(onClick = { confirmingSignOut = false; onSignOut() }) {
                    Text(stringResource(R.string.sign_out_dc1649),
                        color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = {
                TextButton(onClick = { confirmingSignOut = false }) {
                    Text(stringResource(R.string.cancel))
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
                        // Server FIRST; the device is erased only once it
                        // succeeded.
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

    if (pickingAppLanguage) {
        AppLanguageSheet(current = nativeLanguage, onPick = { code ->
            pickingAppLanguage = false
            onPickAppLanguage(code)
        }, onDismiss = { pickingAppLanguage = false })
    }
    if (comparingVoice && voiceId != null) {
        VoiceComparisonSheet(voiceId = voiceId, targetLanguage = targetLanguage,
            onRerecord = { confirmingRerecord = true }, onDismiss = { comparingVoice = false })
    }
    // Outside onboarding a re-record is the full destructive path.
    if (confirmingRerecord) {
        AlertDialog(onDismissRequest = { confirmingRerecord = false },
            title = { Text(stringResource(R.string.re_record_voice)) },
            text = { Text(stringResource(R.string.replace_your_current_clone_with_a_new_one)) },
            confirmButton = { TextButton(onClick = { confirmingRerecord = false; onRerecordVoice() }) { Text(stringResource(R.string.re_record_voice)) } },
            dismissButton = { TextButton(onClick = { confirmingRerecord = false }) { Text(stringResource(R.string.cancel)) } })
    }
    if (pickingAccent && voiceId != null) {
        VoiceAccentSheet(
            voiceId = voiceId,
            targetLanguage = targetLanguage,
            appliedAccentId = voiceAccentId,
            onApplied = onAccentApplied,
            // Leaving without applying leaves the learner on the rebuilt,
            // un-accented clone — the app has to know which voice it holds.
            onCloneRebuilt = { onAccentApplied(it, "") },
            onDismiss = { pickingAccent = false },
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
 * iOS `profileHeader`: avatar, name, ONE line that invites rather than
 * labels. It is a Button in iOS's list, so the whole label wears the tint.
 * The remembered lines are NOT here — they live in the profile editor.
 */
@Composable
private fun ProfileHeader(persona: UserPersona?, onClick: () -> Unit) {
    val accent = MaterialTheme.colorScheme.primary
    Row(
        Modifier.fillMaxWidth().clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        ProfileAvatar(initials = persona?.displayName.orEmpty(), size = 56.dp)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(
                persona?.displayName?.takeIf { it.isNotBlank() }
                    ?: stringResource(R.string.set_up_your_profile),
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.SemiBold,
                color = accent)
            val complete = persona != null &&
                persona.displayName.isNotBlank() && persona.city.isNotBlank() &&
                persona.occupation.isNotBlank() &&
                persona.interests.isNotEmpty() && persona.situations.isNotEmpty()
            Text(
                stringResource(if (complete) R.string.what_your_fluent_self_knows_about_you
                else R.string.tap_to_complete_your_profile),
                style = MaterialTheme.typography.bodyMedium,
                color = accent.copy(alpha = 0.6f),
                maxLines = 1)
        }
        MeChevron(tint = accent.copy(alpha = 0.4f))
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
    // Shippable targets not already enrolled. The app language is NOT
    // excluded — it is the same value as the native language, and Me → App
    // language already lets the two coincide (immersion). Excluding it meant
    // a Japanese-UI learner could never add Japanese (iOS `ae2a0c5`).
    val choices = remember(enrolled) {
        LanguageCatalog.selectableTargets.map { it.code }
            .filter { it !in enrolled }
    }
    var code by remember { mutableStateOf<String?>(null) }
    var level by remember { mutableStateOf(CefrLevel.A2) }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
    ) {
        Column(
            Modifier.fillMaxWidth().bottomBarInsets().padding(horizontal = 20.dp).padding(bottom = 32.dp)
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
 * One enrolled language, wearing its own level (iOS: a plain-style Button
 * row plus an inline menu Picker). The NAME switches to that language; the
 * LEVEL opens its menu, so a level is fixed without switching first.
 */
@Composable
private fun LanguageRow(
    code: String,
    active: Boolean,
    level: CefrLevel,
    onSelect: () -> Unit,
    onLevel: (CefrLevel) -> Unit,
) {
    var expanded by remember { mutableStateOf(false) }
    Row(
        Modifier.fillMaxWidth().heightIn(min = 48.dp).padding(end = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Row(
            Modifier.weight(1f).clickable(onClick = onSelect)
                .padding(start = 16.dp, top = 10.dp, bottom = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(Modifier.width(22.dp), contentAlignment = Alignment.Center) {
                Icon(
                    if (active) Icons.Filled.CheckCircle else Icons.Outlined.Circle,
                    contentDescription = null, modifier = Modifier.size(18.dp),
                    tint = MaterialTheme.colorScheme.primary,
                )
            }
            Spacer(Modifier.width(12.dp))
            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(LanguageCatalog.endonym(code), style = MaterialTheme.typography.bodyLarge)
                Text(LanguageCatalog.englishName(code),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        Box {
            Box(Modifier.clickable { expanded = true }
                .padding(horizontal = 8.dp, vertical = 12.dp)) {
                MePickerValue(LanguageCatalog.levelLabel(level, code))
            }
            DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
                CefrLevel.entries.forEach { l ->
                    DropdownMenuItem(
                        text = { Text(LanguageCatalog.levelLabel(l, code)) },
                        onClick = { expanded = false; onLevel(l) },
                    )
                }
            }
        }
    }
}

/** The learner's level IN one language, with the setup answer as the only
 *  fallback — never a hardcoded band. */
private fun storedLevel(context: android.content.Context, code: String): CefrLevel {
    val prefs = context.getSharedPreferences("futurevoice", 0)
    val fallback = prefs.getString("futurevoice.proficiency", "b1") ?: "b1"
    return CefrLevel.from(LanguageScope.level(context, code, fallback))
}

/**
 * What this account's month cost, told FORWARD.
 *
 * Plus never counts anything down — a remainder is a monthly receipt for
 * time NOT used — and Light reads the same direction over its pool, so
 * switching tier never hands the learner a reversed number.
 */
@Composable
private fun talkTimeLabel(a: AccountStatus?): String = when {
    a == null -> stringResource(R.string.checking)
    a.isUncappedTalk -> stringResource(R.string.talked_this_month, talkSpan(a.secondsUsedPeriod))
    a.isEntitled && a.monthlyCapSeconds != null ->
        stringResource(R.string.of_lld_min_talked_this_month,
            talkSpan(a.secondsUsedPeriod), a.monthlyCapSeconds / 60)
    a.unlimited -> stringResource(R.string.lld_min_left, a.secondsBalance / 60)
    // A one-time pool with nothing to refill toward, so no denominator.
    a.secondsBalance > 0 -> stringResource(R.string.lld_min_of_talk_left, a.secondsBalance / 60)
    // Hard paywall — there is no free tier to count down from.
    else -> stringResource(R.string.no_talk_time_yet)
}

/** A span is minutes; under a minute it names the seconds, so a new
 *  account's first 40 seconds never reads as nothing used. */
@Composable
private fun talkSpan(seconds: Int): String =
    if (TalkTime.spanIsSeconds(seconds)) stringResource(R.string.lld_sec, seconds)
    else stringResource(R.string.lld_min_b61908, seconds / 60)

/**
 * The row's one line.
 *
 * Someone who has never heard of the Core sees the BAR — the door has to be
 * visible from outside or nobody walks toward it — and "3 / 30" is not that:
 * it is a score in a game whose rules the row never stated.
 */
@Composable
private fun coreSubtitle(core: CoreClubClient.Progress?): String = when {
    // No MEMBERSHIP, not "no progress loaded": someone who has never been in
    // the club has to see the bar, and "no seat right now" says nothing to
    // them about how a seat is got.
    core?.member == null -> stringResource(R.string.s_100_seats_30_days_in_a_row_to_enter)
    core.seated -> stringResource(R.string.in_the_core_lld_days, core.member?.days_total ?: 0)
    else -> stringResource(R.string.no_seat_right_now)
}

/**
 * The Core, from wherever the learner stands: their own standing first,
 * then the rules, then what a seat is actually worth.
 *
 * NUMBERS, NOT A PICTURE. A grid of thirty days was tried on iOS and
 * retired: it scored a month already spent, and nothing in a field of dots
 * can say which absence was forgiven. A streak is a rule people already hold
 * in their heads, and a streak is one number.
 *
 * Never add a perk row, and never add a line explaining why there isn't one.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun CoreClubSheet(p: CoreClubClient.Progress?, onDismiss: () -> Unit) {
    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(
            Modifier.fillMaxWidth().bottomBarInsets()
                .padding(horizontal = 20.dp).padding(bottom = 32.dp)
                .verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Text(stringResource(R.string.the_core), style = MaterialTheme.typography.titleLarge)
            if (p == null) {
                Text(stringResource(R.string.the_core_is_unavailable_right_now),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                return@Column
            }
            // Where you stand. The streak is shown in every state — it is the
            // one number that answers "what do I do today".
            CoreStat(stringResource(R.string.current_streak), "${p.streak}")
            if (p.seated) {
                CoreStat(stringResource(R.string.days_in_the_core),
                    "${p.member?.days_total ?: 0}")
            } else {
                p.days_to_entry?.let { CoreStat(stringResource(R.string.days_to_go), "$it") }
            }
            GroupedSectionHeader(stringResource(R.string.how_it_works))
            // Every rule, once each — as points, because a point can't hedge.
            listOf(
                stringResource(R.string.talk_lld_minutes_a_day_lld_days_in_a_row,
                    p.bar_seconds / 60, p.entry_streak),
                stringResource(R.string.miss_a_day_and_the_count_starts_again_at_zero),
                stringResource(R.string.finishing_puts_you_in_line_it_doesn_t_seat_you),
                stringResource(
                    R.string.lld_seats_one_opens_only_when_the_person_in_it_stops_never_b_60a60d,
                    p.seats),
                stringResource(R.string.whoever_qualified_first_takes_it),
                stringResource(R.string.once_you_re_in_one_missed_day_a_month_is_forgiven),
            ).forEach {
                Text(it, style = MaterialTheme.typography.bodyMedium)
            }
            GroupedSectionHeader(stringResource(R.string.what_you_get))
            Row(verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                CoreSeal(size = 16.dp)
                Text(stringResource(R.string.a_badge_next_to_your_name_where_you_meet_people),
                    style = MaterialTheme.typography.bodyMedium)
            }
            GroupedFooter(stringResource(
                R.string.it_s_there_while_you_re_in_the_core_and_it_s_a_promise_to_yo_970f83))
        }
    }
}

/** One number with a name. */
@Composable
private fun CoreStat(title: String, value: String) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Text(title, Modifier.weight(1f), style = MaterialTheme.typography.bodyMedium)
        Text(value, style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}


/**
 * The app's language, named in itself. Foundation drops the SCRIPT from a
 * display name, so both Chinese scripts come back as plain 中文 — the one
 * that ships is Traditional, and it says so.
 */
object AppLanguageNames {
    fun of(code: String?): String = when (com.roro.futurevoice.core.UILanguage.normalize(code)) {
        "ko" -> "한국어"
        "ja" -> "日本語"
        "zh-Hant" -> "繁體中文"
        "zh-Hans" -> "简体中文"
        "es" -> "Español"
        "fr" -> "Français"
        "de" -> "Deutsch"
        else -> "English"
    }
}

/** Picking pops the sheet, the way a pushed settings list does. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun AppLanguageSheet(current: String, onPick: (String) -> Unit, onDismiss: () -> Unit) {
    // Full height and scrolling: the second group is sixty languages long,
    // and a half sheet with no scroll simply cut them off.
    androidx.compose.material3.ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = androidx.compose.material3.rememberModalBottomSheetState(
            skipPartiallyExpanded = true),
    ) {
        Column(Modifier.fillMaxWidth().bottomBarInsets()
            .verticalScroll(androidx.compose.foundation.rememberScrollState())
            .padding(horizontal = 20.dp).padding(bottom = 28.dp)) {
            Text(stringResource(R.string.app_language), style = MaterialTheme.typography.titleLarge,
                modifier = Modifier.padding(bottom = 8.dp))
            // The same two groups the setup step shows, for the same reason:
            // a name under "Corrections and notes only" buys the coaching
            // text and leaves the app's own screens in English, and that has
            // to be readable BEFORE the tap. The footer used to sit here with
            // no list under it, so those sixty languages had no way in at all.
            val groups = remember { LanguageCatalog.nativeGroups() }
            fun isCurrent(code: String): Boolean {
                val now = com.roro.futurevoice.core.UILanguage.normalize(current)
                return current == code || now == code || (now == null && code == "en")
            }
            groups.translated.forEach { code ->
                Row(Modifier.fillMaxWidth().clickable { onPick(code) }.padding(vertical = 14.dp),
                    verticalAlignment = Alignment.CenterVertically) {
                    Text(LanguageCatalog.endonym(code), Modifier.weight(1f),
                        style = MaterialTheme.typography.bodyLarge)
                    if (isCurrent(code)) {
                        Icon(Icons.Filled.Check, contentDescription = null,
                            tint = MaterialTheme.colorScheme.primary)
                    }
                }
            }
            GroupedFooter(stringResource(R.string.everything_you_read_in_the_app))
            GroupedSectionHeader(stringResource(R.string.corrections_and_notes_only))
            groups.coachingOnly.forEach { code ->
                Row(Modifier.fillMaxWidth().clickable { onPick(code) }.padding(vertical = 14.dp),
                    verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text(LanguageCatalog.endonym(code),
                            style = MaterialTheme.typography.bodyLarge)
                        Text(LanguageCatalog.ownName(code, current),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    if (isCurrent(code)) {
                        Icon(Icons.Filled.Check, contentDescription = null,
                            tint = MaterialTheme.colorScheme.primary)
                    }
                }
            }
            GroupedFooter(stringResource(
                R.string.your_corrections_notes_and_word_meanings_come_back_in_this_l_95bb21))
        }
    }
}
