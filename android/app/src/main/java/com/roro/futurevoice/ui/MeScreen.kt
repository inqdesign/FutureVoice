package com.roro.futurevoice.ui

import androidx.compose.material.icons.automirrored.filled.ShortText
import androidx.compose.material.icons.filled.LockOpen
import androidx.compose.material.icons.filled.Lock
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Headphones
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.GraphicEq
import androidx.compose.foundation.clickable
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
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
import androidx.compose.material3.Button
import com.roro.futurevoice.data.CefrLevel
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.RecordVoiceOver
import androidx.compose.material.icons.filled.Palette
import androidx.compose.material.icons.filled.Groups
import androidx.compose.material.icons.filled.Forum
import androidx.compose.material.icons.automirrored.filled.Send
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
import androidx.compose.material.icons.filled.NotificationsOff
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
import com.roro.futurevoice.data.LanguageScope
import com.roro.futurevoice.data.TalkTime
import com.roro.futurevoice.data.WeeklyReportStore
import com.roro.futurevoice.net.CoreClubClient
import com.roro.futurevoice.ui.brand.CoreSeal
import com.roro.futurevoice.talk.UserPersona
import androidx.compose.foundation.layout.Box
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material.icons.filled.AddCircleOutline
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.RadioButtonUnchecked
import androidx.compose.material.icons.filled.TrackChanges
import androidx.compose.material.icons.filled.UnfoldMore
import androidx.compose.ui.graphics.vector.ImageVector

/**
 * Settings — everything about "you the account", in iOS's order
 * (`MeTab.swift`): profile, the subscription on its own, usage + the Core,
 * Learning (the languages and their levels, the goal, the app's language),
 * the call, the voice, appearance/data/privacy, then the account itself.
 *
 * The profile card also carries what the future self has LEARNED, each note
 * removable — a memory that can't be corrected is a liability.
 *
 * Rows, not grids of chips. A level belongs to a language and cannot ride on
 * a chip, and a settings list that inlines every picker becomes a wall where
 * nothing can be scanned.
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
    /**
     * A level changed by hand, for one language.
     *
     * The level belongs to the LANGUAGE, not to the app, so it is written
     * per code — and it is written to `LanguageScope` here whether or not a
     * host wires this up, because that is the file every store and prompt
     * reads. What the callback buys is the ACTIVE language's in-memory copy:
     * without it the new band reaches the next conversation only after a
     * language switch or a relaunch.
     */
    onSetLevel: ((String, CefrLevel) -> Unit)? = null,
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
    onRerecordVoice: () -> Unit = {},
    onPickAppLanguage: (String) -> Unit = {},
    onEditProfile: () -> Unit,
    /** The remembered lines' own page — the profile editor on its home step. */
    onEditNotes: () -> Unit = onEditProfile,
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
    var comparingVoice by remember { mutableStateOf(false) }
    var pickingAppLanguage by remember { mutableStateOf(false) }
    var pickingMic by remember { mutableStateOf(false) }
    var confirmingRerecord by remember { mutableStateOf(false) }
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
    var showingCore by remember { mutableStateOf(false) }
    // Every enrolled language's level, read once. A `body` that hit the
    // store per row per recomposition would read preferences on every
    // keystroke elsewhere on this screen.
    var levels by remember { mutableStateOf(mapOf<String, CefrLevel>()) }
    LaunchedEffect(enrolledLanguages) {
        levels = enrolledLanguages.associateWith { storedLevel(context, it) }
    }
    /** Persist, show it immediately, and tell the host if it asked. */
    val setLevel: (String, CefrLevel) -> Unit = { code, level ->
        LanguageScope.setLevel(context, code, level.code)
        levels = levels + (code to level)
        onSetLevel?.invoke(code, level)
    }
    // The AI's own read of the active language — the weekly report's pooled
    // estimate, the same source Progress publishes. A single talk is too
    // noisy to suggest from, so no report means no row, never a guess.
    var aiLevel by remember { mutableStateOf<CefrLevel?>(null) }
    LaunchedEffect(targetLanguage) {
        aiLevel = WeeklyReportStore.shared(context).latest(targetLanguage)
            ?.cefrLevel?.let { CefrLevel.from(it) }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                colors = AppSurfaces.topBarColors(),
                // The page is Settings, and says so — "Me" named the tab it
                // used to live in, not the page.
                title = { Text(stringResource(R.string.settings)) },
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
                Row(
                    Modifier.fillMaxWidth().clickable(onClick = onEditProfile)
                        .padding(horizontal = 14.dp, vertical = 12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(14.dp),
                ) {
                    ProfileAvatar(initials = persona?.displayName.orEmpty(), size = 52.dp)
                    Column(Modifier.weight(1f)) {
                        Text(
                            persona?.displayName?.takeIf { it.isNotBlank() }
                                ?: stringResource(R.string.profile),
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.SemiBold,
                            color = MaterialTheme.colorScheme.primary)
                        // An INVITATION, not an account label. The city and
                        // the email told the learner nothing they could act
                        // on; what this row can do is make the fluent self
                        // know them better, so it asks for the missing parts
                        // until there are none (iOS `0ea96e7`).
                        val complete = persona != null &&
                            persona.displayName.isNotBlank() && persona.city.isNotBlank() &&
                            persona.occupation.isNotBlank() &&
                            persona.interests.isNotEmpty() && persona.situations.isNotEmpty()
                        Text(
                            stringResource(if (complete) R.string.what_your_fluent_self_knows_about_you
                            else R.string.tap_to_complete_your_profile),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            maxLines = 1)
                    }
                    Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null,
                        tint = MaterialTheme.colorScheme.outline)
                }
                // What the future self has learned — the other half of the
                // profile. Each note removable; the learner can always
                // correct the memory. A tap opens the lines with their
                // evidence and what strangers hear; the lock says it here.
                persona?.learnedNotes?.takeIf { it.isNotEmpty() }?.forEach { note ->
                    GroupedRowDivider()
                    Row(Modifier.fillMaxWidth().clickable(onClick = onEditNotes)
                        .padding(start = 14.dp, end = 4.dp),
                        verticalAlignment = Alignment.CenterVertically) {
                        Icon(
                            when (note.share) {
                                com.roro.futurevoice.talk.PersonaNote.Share.NOTHING -> Icons.Filled.Lock
                                com.roro.futurevoice.talk.PersonaNote.Share.GIST ->
                                    Icons.AutoMirrored.Filled.ShortText
                                com.roro.futurevoice.talk.PersonaNote.Share.ALL -> Icons.Filled.LockOpen
                            },
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.outline,
                            modifier = Modifier.padding(end = 10.dp).size(14.dp))
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
                // The plan's NAME is the row's value, the way iOS states a
                // standing fact that goes nowhere. What the month cost is
                // the Usage row's job, one card down — saying it twice made
                // the two rows argue about which one you were meant to read.
                MeRow(Icons.Filled.AutoAwesome,
                    stringResource(
                        if (acct?.isEntitled == true) R.string.subscription
                        else R.string.subscribe),
                    // Nothing is claimed about the account until it answers:
                    // "Talking needs a plan" under a spinner is the app
                    // telling a subscriber they have no plan.
                    if (acct == null || acct.isEntitled) null
                    else stringResource(R.string.talking_needs_a_plan),
                    value = when {
                        acct == null -> stringResource(R.string.checking)
                        acct.isPlusPlan -> stringResource(R.string.plan_tier_plus)
                        acct.isEntitled -> stringResource(R.string.plan_tier_light)
                        else -> null
                    },
                    onClick = onOpenPaywall)
            }

            // ── Usage, and the club ──
            // Not "Talk time": the page behind it reports Watch scenes and
            // the subscription too, and a row that names only one of the
            // three sends the other two questions somewhere else.
            GroupedSectionSpacer()
            GroupedCard {
                // What was SPENT, never what is left: a remainder is a
                // monthly receipt for time NOT used.
                MeRow(Icons.Filled.Bolt, stringResource(R.string.usage),
                    talkTimeLabel(account), onClick = onOpenPlanPage)
                GroupedRowDivider()
                // The bar belongs in the row, not in a footer under the
                // card: someone who has never heard of the Core reads the
                // subtitle as what this is, and a footer floating outside
                // the card reads as a note about both rows above it.
                MeRow(Icons.Filled.WorkspacePremium, stringResource(R.string.the_core),
                    coreSubtitle(coreProgress),
                    leading = if (coreProgress?.seated == true) ({ CoreSeal(size = 20.dp) })
                    else null,
                    onClick = { showingCore = true })
            }

            // ── Learning ──
            // There are exactly two kinds of language here: the ones you are
            // learning, and the one the app talks to you in. They are ROWS,
            // not grids of chips — each language wears its own level, and a
            // level cannot ride on a chip. The goal and the app language sit
            // with them because they are the other two answers to "how do I
            // learn here", not app chrome.
            GroupedSectionHeader(stringResource(R.string.learning))
            GroupedCard {
                enrolledLanguages.forEachIndexed { index, code ->
                    if (index > 0) GroupedRowDivider()
                    LanguageRow(
                        code = code,
                        active = code == targetLanguage,
                        level = levels[code] ?: CefrLevel.B1,
                        // Switching is not a page: every store already takes
                        // the language as a parameter, so a switch is only a
                        // change of which one they are handed.
                        onSelect = { if (code != targetLanguage) onSwitchLanguage(code) },
                        onLevel = { setLevel(code, it) },
                    )
                }
                // The AI's read is a SUGGESTION, never an assignment: the
                // level is the learner's setting and only a tap moves it.
                // Only once the current level is actually known — comparing
                // against a map that hasn't loaded suggests a level the
                // learner may already be on.
                aiLevel?.takeIf { levels[targetLanguage] != null && it != levels[targetLanguage] }
                    ?.let { ai ->
                    GroupedRowDivider()
                    MeRow(Icons.Filled.AutoAwesome,
                        stringResource(R.string.ai_read_tap_to_apply, ai.code.uppercase()),
                        stringResource(R.string.from_your_recent_conversations,
                            LanguageCatalog.endonym(targetLanguage)),
                        chevron = false,
                        onClick = { setLevel(targetLanguage, ai) })
                }
                GroupedRowDivider()
                // Never gated on a plan: every server pool is keyed per
                // ACCOUNT with no language in it, so a second language adds
                // no cost.
                MeRow(Icons.Filled.AddCircleOutline, stringResource(R.string.add_a_language),
                    stringResource(R.string.same_voice_new_language),
                    chevron = false,
                    onClick = { addingLanguage = true })
                GroupedRowDivider()
                PickerRow(
                    icon = Icons.Filled.TrackChanges,
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
                // The app's own screens, and the language corrections come
                // back in — one choice, because a learner has one language
                // they think in.
                MeRow(Icons.Filled.Translate, stringResource(R.string.app_language),
                    AppLanguageNames.of(nativeLanguage),
                    onClick = { pickingAppLanguage = true })
            }
            GroupedFooter(stringResource(
                R.string.tap_a_language_to_practice_it_its_level_calibrates_every_con_1ff279))

            // A schedule the app can't ring is the worst failure here: the
            // learner thinks they'll be reminded and they won't. Shown only
            // when it's actually off.
            if (!androidx.core.app.NotificationManagerCompat.from(context).areNotificationsEnabled()) {
                GroupedSectionSpacer()
                GroupedCard {
                    MeRow(Icons.Filled.NotificationsOff, stringResource(R.string.notifications_are_off),
                        stringResource(R.string.reminders_cant_reach_you), onClick = {
                            context.startActivity(
                                android.content.Intent(android.provider.Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                                    .putExtra(android.provider.Settings.EXTRA_APP_PACKAGE, context.packageName)
                                    .addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK))
                        })
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
                // "It doesn't sound like me" gets an answer, not a shrug: the
                // recording and the clone on the same sentence.
                if (hasVoice && voiceId != null && VoiceComparison.exists(context.filesDir)) {
                    GroupedRowDivider()
                    MeRow(Icons.Filled.GraphicEq, stringResource(R.string.doesn_t_sound_like_you),
                        stringResource(R.string.hear_your_recording_and_your_clone_side_by_side), onClick = { comparingVoice = true })
                }
                // Which mic records the learner. Shown only where the answer
                // changes something — with nothing but the phone's own mic
                // there is nothing to choose.
                if (com.roro.futurevoice.data.MicPreference.headsetConnected(context)
                    || com.roro.futurevoice.data.MicPreference.hasChosen(context)) {
                    GroupedRowDivider()
                    MeRow(Icons.Filled.Headphones, stringResource(R.string.which_mic),
                        stringResource(
                            if (com.roro.futurevoice.data.MicPreference.current(context)
                                == com.roro.futurevoice.data.MicPreference.PHONE) R.string.phone_mic
                            else R.string.earphone_mic),
                        onClick = { pickingMic = true })
                }
                if (hasVoice) {
                    GroupedRowDivider()
                    MeRow(Icons.Filled.Mic, stringResource(R.string.re_record_voice),
                        stringResource(R.string.replace_your_current_clone_with_a_new_one), onClick = { confirmingRerecord = true })
                }
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

            // Writing to the person who builds this — one tap, no compose
            // window. It sits in the main list rather than inside Privacy,
            // where the only contact row used to live and where it reads as a
            // data-request address. The footer names who is on the other end:
            // a learner will not write to a support desk about a feature they
            // wish existed, and they will write to a person.
            val channels = com.roro.futurevoice.data.SupportChannel.available
            if (channels.isNotEmpty()) {
                GroupedSectionSpacer()
                GroupedSectionHeader(stringResource(R.string.say_hello))
                GroupedCard {
                    channels.forEachIndexed { i, channel ->
                        if (i > 0) GroupedRowDivider()
                        MeRow(
                            if (channel == com.roro.futurevoice.data.SupportChannel.INSTAGRAM)
                                Icons.Filled.Forum else Icons.AutoMirrored.Filled.Send,
                            stringResource(channel.titleRes), channel.subtitle,
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
                Row(Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 12.dp)) {
                    Text(email.orEmpty(), style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                // Never in a capture build — a dev button is gallery noise.
                if (com.roro.futurevoice.BuildConfig.DEBUG &&
                    com.roro.futurevoice.BuildConfig.BUILD_TYPE != "capture") {
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
            // What deleting actually takes with it, said before the tap and
            // not only inside the confirmation.
            GroupedFooter(stringResource(
                R.string.deleting_your_account_permanently_removes_your_voice_clone_t_43bafb))
        }
    }

    if (showingCore) {
        CoreClubSheet(coreProgress) { showingCore = false }
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
                    Text(stringResource(R.string.back))
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
                Modifier.fillMaxWidth().bottomBarInsets()
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

    if (pickingMic) {
        MicChoiceSheet(onChoose = { choice ->
            com.roro.futurevoice.data.MicPreference.set(context, choice)
            pickingMic = false
        })
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
    // Outside onboarding a re-record is the full destructive path, so it
    // goes through a confirmation.
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
    icon: ImageVector,
    title: String,
    subtitle: String?,
    onClick: (() -> Unit)?,
    /** A standing fact stated on the right — a plan's name, a level. Never a
     *  destination, which is what the chevron is for. */
    value: String? = null,
    /** Off for a row that ACTS rather than opens: a chevron there promises a
     *  page that isn't coming. */
    chevron: Boolean = true,
    /** Drawn instead of [icon] where the mark is not a glyph — the Core's
     *  seal is a drawing, and it is the one badge in the app. */
    leading: (@Composable () -> Unit)? = null,
) {
    Row(
        Modifier.fillMaxWidth()
            .then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier)
            .padding(horizontal = 14.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        if (leading != null) {
            Box(Modifier.size(20.dp), contentAlignment = Alignment.Center) { leading() }
        } else {
            Icon(icon, contentDescription = null, modifier = Modifier.size(20.dp),
                tint = MaterialTheme.colorScheme.primary)
        }
        Column(Modifier.weight(1f)) {
            Text(title)
            subtitle?.takeIf { it.isNotBlank() }?.let {
                Text(it, style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        value?.takeIf { it.isNotBlank() }?.let {
            Text(it, style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        if (onClick != null && chevron) {
            Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null,
                modifier = Modifier.size(18.dp),
                tint = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

/**
 * One enrolled language, wearing its own level.
 *
 * Two targets in one row, on purpose: the NAME switches to that language,
 * the LEVEL opens its menu. The level belongs to the language, not to the
 * app — someone at C1 in English starting German is not a C1 German speaker
 * — so it can be fixed without switching to that language first.
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
        Modifier.fillMaxWidth().padding(start = 14.dp, end = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Row(
            Modifier.weight(1f).clickable(onClick = onSelect).padding(vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Icon(
                if (active) Icons.Filled.CheckCircle else Icons.Filled.RadioButtonUnchecked,
                contentDescription = null, modifier = Modifier.size(20.dp),
                tint = if (active) MaterialTheme.colorScheme.primary
                else MaterialTheme.colorScheme.outline,
            )
            Column {
                Text(LanguageCatalog.endonym(code))
                Text(LanguageCatalog.englishName(code),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        Box {
            Row(
                Modifier.clickable { expanded = true }
                    .padding(horizontal = 6.dp, vertical = 12.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(2.dp),
            ) {
                Text(LanguageCatalog.levelLabel(level, code),
                    color = MaterialTheme.colorScheme.primary)
                Icon(Icons.Filled.UnfoldMore, contentDescription = null,
                    modifier = Modifier.size(16.dp),
                    tint = MaterialTheme.colorScheme.primary)
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

/**
 * A settings row whose value is chosen from a short list — iOS's menu-style
 * `Picker`. The value stands where a chevron would; the list opens on it.
 */
@Composable
private fun <T> PickerRow(
    icon: ImageVector,
    title: String,
    subtitle: String?,
    value: String,
    options: List<Pair<T, String>>,
    onPick: (T) -> Unit,
) {
    var expanded by remember { mutableStateOf(false) }
    Box {
        Row(
            Modifier.fillMaxWidth().clickable { expanded = true }
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
            Text(value, color = MaterialTheme.colorScheme.primary)
            Icon(Icons.Filled.UnfoldMore, contentDescription = null,
                modifier = Modifier.size(16.dp),
                tint = MaterialTheme.colorScheme.primary)
        }
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            options.forEach { (item, label) ->
                DropdownMenuItem(
                    text = { Text(label) },
                    onClick = { expanded = false; onPick(item) },
                )
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
