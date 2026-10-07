package com.roro.futurevoice.ui

import androidx.compose.ui.geometry.Size
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.ui.layout.boundsInWindow
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.material.icons.filled.Tune
import androidx.compose.material3.Icon
import androidx.compose.runtime.produceState
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.Icons
import androidx.compose.material3.IconButton
import androidx.compose.material3.TextButton
import androidx.compose.material3.AlertDialog
import kotlinx.coroutines.launch
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.platform.LocalView
import androidx.compose.material3.CircularProgressIndicator
import com.roro.futurevoice.data.MicPreference
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import com.roro.futurevoice.ui.brand.IosButton as Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import com.roro.futurevoice.ui.brand.IosOutlinedButton as OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.animation.animateContentSize
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import com.roro.futurevoice.data.AccountStatus
import com.roro.futurevoice.data.AuthRepository
import com.roro.futurevoice.data.BillingGate
import com.roro.futurevoice.data.DeepLinkInbox
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Spacer
import androidx.compose.material3.HorizontalDivider
import androidx.compose.ui.draw.alpha
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import com.roro.futurevoice.R
import com.roro.futurevoice.data.SessionStore
import com.roro.futurevoice.data.StoreEvents
import com.roro.futurevoice.talk.SessionSummarizer
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.roro.futurevoice.data.CefrLevel
import com.roro.futurevoice.talk.TalkConfig
import com.roro.futurevoice.talk.TalkPhase
import com.roro.futurevoice.talk.TalkViewModel
import com.roro.futurevoice.talk.TalkWall
import com.roro.futurevoice.talk.Turn
import com.roro.futurevoice.talk.TurnRole
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.draw.clip
import com.roro.futurevoice.ui.brand.AppSurfaces
import com.roro.futurevoice.ui.brand.DialogueLine
import com.roro.futurevoice.ui.brand.Futureself
import com.roro.futurevoice.ui.brand.FutureselfMode
import com.roro.futurevoice.ui.brand.FutureselfTheme
import com.roro.futurevoice.ui.brand.DialogueScale
import com.roro.futurevoice.ui.brand.DialogueSpeaker

/**
 * Phone-call mode, not a chat app: one dialogue surface, a status line, and an
 * End button. Speaker separation lives in [DialogueLine] alone — restyling the
 * conversation must stay a single-composable change.
 *
 * Every string here is `R.string.<slug of the iOS key>` from the generated
 * catalog (`scripts/android/gen-strings.py`); nothing is authored twice.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TalkScreen(
    voiceId: String,
    targetLanguage: String,
    nativeLanguage: String,
    level: CefrLevel,
    persona: com.roro.futurevoice.talk.UserPersona? = null,
    topic: String = "",
    newsFacts: List<String> = emptyList(),
    scenarioId: String? = null,
    initialOpener: String = "",
    cast: com.roro.futurevoice.talk.ConversationEngine.Cast? = null,
    castVoiceId: String? = null,
    /** The stranger's local row, so the talk lands on their card. */
    counterpartId: String? = null,
    onExit: () -> Unit,
) {
    // "Go to Review" on the spent sheet (iOS `routeToPracticeOnClose`):
    // whichever way the call then leaves — the summary's Done, the plans, a
    // back swipe — it lands on Review.
    var routeToPractice by remember { mutableStateOf(false) }
    val exitParam = onExit
    @Suppress("NAME_SHADOWING")
    val onExit: () -> Unit = {
        exitParam()
        if (routeToPractice) DeepLinkInbox.pending.value = DeepLinkInbox.Destination.PRACTICE
    }
    val context = LocalContext.current
    // Capture build only: a prepared call, drawn without starting one.
    val preview = remember { com.roro.futurevoice.capture.flags.TalkCaptureFlags.callPreview }
    // The live call's notification is the only control a locked phone has,
    // and Android 13+ shows none of it without this permission. Ask once,
    // here, where the reason is on screen — the daily call toggle also asks,
    // but a learner who never turns that on would never be asked at all.
    val notifPermission = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()) { }
    LaunchedEffect(Unit) {
        if (preview == null && android.os.Build.VERSION.SDK_INT >= 33 &&
            context.checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) !=
            android.content.pm.PackageManager.PERMISSION_GRANTED) {
            notifPermission.launch(android.Manifest.permission.POST_NOTIFICATIONS)
        }
    }
    val vm: TalkViewModel = viewModel(
        factory = viewModelFactory {
            initializer { TalkViewModel(context) }
        }
    )
    val liveState by vm.state.collectAsStateWithLifecycle()
    val state = preview?.state ?: liveState
    // System back = hang up and leave, same as End — never kill the activity
    // with a call still holding the mic.
    // Leaving after the wrap-up: the first time, the feedback ask comes
    // first and its dismissal completes the exit.
    var feedback by remember { mutableStateOf<FeedbackContext?>(null) }
    val appContext = LocalContext.current
    val feedbackScope = rememberCoroutineScope()
    // Asked after a RETURNING talk, not the first one: someone who has just
    // met the app has nothing to compare it to, and the first call is the
    // worst moment to interrupt. The gate wants the length of the call that
    // just ended — a minute of talking is the bar for having an opinion.
    val activity = LocalContext.current as? android.app.Activity
    fun leave() {
        val seconds = vm.elapsedSeconds()
        feedbackScope.launch {
            if (FeedbackPrompt.shouldShowReturningTalk(appContext, seconds)) {
                FeedbackPrompt.markShown(appContext, FeedbackContext.RETURNING_TALK)
                feedback = FeedbackContext.RETURNING_TALK
                return@launch
            }
            // Play's own rating sheet, of someone who has actually lived with
            // the app. Never in the same call as the feedback ask — and never
            // gated on what they answered there, which would be review
            // gating. Asked after the call screen has gone: over a screen
            // mid-dismissal the system can drop it.
            val ask = activity != null &&
                com.roro.futurevoice.data.ReviewRequest.shouldAsk(appContext, seconds)
            onExit()
            if (ask) {
                kotlinx.coroutines.delay(1_200)
                com.roro.futurevoice.data.ReviewRequest.ask(activity!!)
            }
        }
    }

    /**
     * The plans are offered when the free minutes are SPENT, never while any
     * are left — the welcome sheet promised the decision comes after them
     * (iOS `ef9af00`). "Spent" is the pool ending this call, or too little
     * left to open another one.
     *
     * The snapshot is FORCED: they just spent minutes, so a cached one from
     * before the call would answer about a different account. A lookup that
     * fails never holds the exit — the learner leaves.
     */
    fun pitchCore() {
        val spentThisCall = state.wall == TalkWall.OUT_OF_MINUTES
        feedbackScope.launch {
            fun log(decision: String) {
                val props = mapOf("decision" to decision,
                    "free_call_spent" to if (spentThisCall) "1" else "0")
                com.roro.futurevoice.core.Telemetry.log("post_call_pitch", props)
                com.roro.futurevoice.core.Analytics.capture("post_call_pitch", props)
            }
            val account = runCatching {
                com.roro.futurevoice.data.AccountStatus.load(AuthRepository())
                    .also { com.roro.futurevoice.data.BillingGate.remember(it) }
            }.getOrNull()
            when {
                account == null -> log("skipped_lookup_failed")
                account.isEntitled || account.unlimited -> log("skipped_entitled")
                spentThisCall || account.needsSubscription -> {
                    log("shown")
                    // The plans hold the exit, and their dismissal IS the
                    // exit — no feedback ask, no rating sheet behind them
                    // (iOS `closeAfterPaywall` → `close()`). Leaving through
                    // `leave()` here parked the feedback sheet on a call
                    // screen the paywall had replaced, and the book reopened
                    // under it once the plans were closed.
                    com.roro.futurevoice.data.BillingGate.showPaywall.value = true
                    onExit()
                    return@launch
                }
                else -> log("skipped_minutes_left")
            }
            leave()
        }
    }
    /**
     * "How was your first call?" (iOS `FirstCallCheckSheet`, `eaaf3af`) —
     * once, after the first talk the learner spoke in, and BEFORE the plans
     * pitch: its dismissal (Save or Later) continues the exit.
     */
    var firstCallCheck by remember { mutableStateOf<(() -> Unit)?>(null) }
    fun pitchThenLeave() {
        if (firstCallCheck != null) return
        feedbackScope.launch {
            val spoke = state.turns.any { it.role == TurnRole.USER }
            if (preview == null && FirstCallCheck.shouldShow(appContext, spoke)) {
                FirstCallCheck.markShown(appContext)
                firstCallCheck = { pitchCore() }
                return@launch
            }
            pitchCore()
        }
    }
    /**
     * Every OTHER way out — closed without saving, a call nobody wrapped up —
     * still asks about the first call when the learner spoke in it (iOS
     * `close()`: "the first call is asked about however it ended"). Its
     * dismissal is the exit; no plans pitch, which belongs to the summary.
     */
    fun exitAskingFirstCall() {
        if (firstCallCheck != null) return
        val spoke = vm.state.value.turns.any { it.role == TurnRole.USER }
        // Torn down first, like iOS `close()`: nothing listens or bills
        // behind the sheet, and nothing is kept.
        vm.discard()
        feedbackScope.launch {
            if (preview == null && FirstCallCheck.shouldShow(appContext, spoke)) {
                FirstCallCheck.markShown(appContext)
                kotlinx.coroutines.delay(350)
                firstCallCheck = { onExit() }
                return@launch
            }
            onExit()
        }
    }
    firstCallCheck?.let { next ->
        FirstCallCheckSheet(targetLanguage = targetLanguage, currentLevel = level,
            onDismiss = { firstCallCheck = null; next() })
    }
    feedback?.let { FeedbackSheet(it, onDismiss = { feedback = null; onExit() }) }
    androidx.activity.compose.BackHandler {
        // A swipe out is the same exit as Done: it used to leave the learner
        // on a finished call screen and skip the plans a spent pool is owed.
        if (state.phase == TalkPhase.ENDED) pitchThenLeave()
        else { vm.end(); if (vm.state.value.endedSessionId == null) onExit() }
    }
    /** A spent allowance: a sheet, never an error and never a bare paywall. */
    var spent by remember { mutableStateOf<SpentPool?>(null) }
    /** Fair use: an alert, not a sheet and not an upsell (iOS `fairUseHalted`). */
    var fairUseHalted by remember { mutableStateOf(false) }
    // Which wall it was decides the ANSWER, raised once (iOS ConversationView
    // `.onChange(of: realtime.state)` / `meter.onWallHit`). Nothing is drawn
    // in the transcript — the sheet, the alert or the wrap-up says it.
    // The view model outlives one call (it is the activity's), so the first
    // frame of a NEW call can still carry the last call's wall — which raised
    // the last call's sheet over this one. Walls count only once this call
    // has started.
    var callStarted by remember { mutableStateOf(preview != null) }
    LaunchedEffect(state.phase) {
        if (state.phase != TalkPhase.IDLE && state.phase != TalkPhase.ENDED) callStarted = true
    }
    LaunchedEffect(state.wall, state.wallBeforeSpeaking, callStarted) {
        if (!callStarted) return@LaunchedEffect
        when (state.wall) {
            // The free pool ran out with something said: the call is wrapping
            // ITSELF up and the plans come after the summary
            // (`pitchThenLeave`) — a paywall here would land on the board and
            // take the book with it (iOS `600d406`). Nothing said: nothing to
            // wrap up, so the plans ARE the answer and the call leaves with
            // them (iOS `closeAfterPaywall`, `talk_wall_before_speaking`).
            TalkWall.OUT_OF_MINUTES -> {
                BillingGate.invalidate()
                if (state.wallBeforeSpeaking && preview == null) {
                    BillingGate.showPaywall.value = true
                    onExit()
                }
            }
            TalkWall.ALLOWANCE_SPENT -> spent = SpentPool.TALK
            TalkWall.SCENES_SPENT -> spent = SpentPool.SCENES
            TalkWall.FAIR_USE -> fairUseHalted = true
            null -> Unit
        }
    }
    if (fairUseHalted) {
        androidx.compose.material3.AlertDialog(
            onDismissRequest = { fairUseHalted = false },
            title = { Text(stringResource(R.string.we_ve_paused_talking_on_this_account)) },
            text = { Text(stringResource(R.string.some_unusual_usage_needs_checking_write_to_us_and_we_ll_sort_989cca)) },
            confirmButton = { TextButton(onClick = { fairUseHalted = false }) { Text(stringResource(R.string.ok)) } },
        )
    }
    /**
     * "Go to Review" on the spent sheet (iOS `leaveForPractice`): a talk with
     * something said and not yet saved is wrapped up first — the summary,
     * the book — and the exit then lands on Review; otherwise straight there.
     */
    fun leaveForPractice() {
        routeToPractice = true
        if (state.turns.any { it.role == TurnRole.USER } && state.phase != TalkPhase.ENDED) {
            vm.end()
            // Nothing saved (set synchronously) → no board to wait on.
            if (vm.state.value.endedSessionId == null) onExit()
        } else { vm.discard(); onExit() }
    }
    val listState = rememberLazyListState()
    // Call settings (iOS `CallSettingsSheet`): screen state the learner can
    // change mid-call, plus the speed, which reaches the voice.
    var showsTranscript by remember { mutableStateOf(CallSettings.flag(context, CallSettings.SHOWS_TRANSCRIPT)) }
    var showsCorrections by remember { mutableStateOf(CallSettings.flag(context, CallSettings.SHOWS_CORRECTIONS)) }
    var showsGoalChips by remember { mutableStateOf(CallSettings.flag(context, CallSettings.SHOWS_GOAL_CHIPS)) }
    var showingCallSettings by remember { mutableStateOf(false) }
    // Coach mode: the learner's flip, else on for A1/A2 (`CoachMode.resolve`).
    var coachMode by remember {
        mutableStateOf(com.roro.futurevoice.talk.CoachMode.resolve(
            com.roro.futurevoice.talk.CoachMode.choice(context), level.code))
    }
    if (showingCallSettings) {
        CallSettingsSheet(
            showsTranscript = showsTranscript, showsCorrections = showsCorrections,
            showsGoalChips = showsGoalChips,
            coachMode = coachMode,
            onCoachMode = {
                com.roro.futurevoice.talk.CoachMode.setChoice(context, it)
                coachMode = it
                vm.setCoachMode(it)
            },
            onFlag = { key, value ->
                CallSettings.set(context, key, value)
                when (key) {
                    CallSettings.SHOWS_TRANSCRIPT -> showsTranscript = value
                    CallSettings.SHOWS_CORRECTIONS -> showsCorrections = value
                    CallSettings.SHOWS_GOAL_CHIPS -> showsGoalChips = value
                }
            },
            onSpeedChange = { vm.setSpeed(it.multiplier(context)) },
            onDismiss = { showingCallSettings = false },
        )
    }
    // A long silent turn must not lock the phone: a call is on screen, and
    // the learner's hands are usually nowhere near it.
    val view = LocalView.current
    DisposableEffect(Unit) {
        view.keepScreenOn = true
        onDispose { view.keepScreenOn = false }
    }

    // One-time "which mic?", asked here because the call is the first mic
    // surface most learners reach. The call waits for the answer; both
    // buttons are answers.
    var askingMic by remember { mutableStateOf(preview == null && MicPreference.shouldAsk(appContext)) }
    if (askingMic) {
        MicChoiceSheet(onChoose = { choice ->
            MicPreference.set(appContext, choice)
            askingMic = false
        })
    }
    LaunchedEffect(voiceId, askingMic) {
        if (askingMic || preview != null) return@LaunchedEffect
        vm.start(
            TalkConfig(
                voiceId = voiceId,
                targetLanguage = targetLanguage,
                nativeLanguage = nativeLanguage,
                level = level,
                persona = persona,
                topic = topic,
                newsFacts = newsFacts,
                scenarioId = scenarioId,
                initialOpener = initialOpener,
                cast = cast,
                castVoiceId = castVoiceId,
                counterpartId = counterpartId,
            )
        )
    }
    // Leaving the screen hangs up — but a recreation (rotation, dark mode,
    // app language) disposes it too, and the call must carry on through that.
    DisposableEffect(Unit) {
        onDispose {
            var c: android.content.Context? = context
            while (c is android.content.ContextWrapper && c !is android.app.Activity) c = c.baseContext
            if ((c as? android.app.Activity)?.isChangingConfigurations != true) vm.end()
        }
    }

    // Today's notebook, dealt once when the call opens. It never re-deals
    // mid-call: a row that changed under the learner would be asking for a
    // different word than the one they were about to say.
    var goals by remember { mutableStateOf(preview?.goals ?: emptyList()) }
    var goalsUsed by remember { mutableStateOf(preview?.goalsUsed ?: emptySet()) }
    var openGoal by remember { mutableStateOf(preview?.openGoal) }
    LaunchedEffect(targetLanguage) {
        if (preview != null) return@LaunchedEffect
        // A talk on a scenario book spends THAT book (iOS `cb4252b`).
        val scenario = scenarioId?.let { id ->
            com.roro.futurevoice.data.ScenarioStore.shared(context).load(targetLanguage).firstOrNull { it.id == id }
        }
        goals = if (scenario != null) {
            // Previous runs: by id, and by title for talks saved before the
            // book's Talk button passed the id.
            val previous = com.roro.futurevoice.data.SessionStore.shared(context).load(targetLanguage)
                .filter { it.originScenarioId == scenario.id || (it.originScenarioId == null && it.topic == scenario.environment) }
            TalkGoalPicker.pickForScenario(context, targetLanguage, scenario, previous, level)
        } else TalkGoalPicker.pick(context, targetLanguage)
        // Coach mode steers toward the row, then toward the words a talk
        // kept on its own, which the row leaves out.
        vm.setCoachPool(goals + TalkGoalPicker.coachExtras(context, targetLanguage,
            goals.map { it.key }.toSet()))
    }
    // ADDITIVE: every version of a user turn's text is checked, from the
    // recognizer's first line to the audio-grounded rewrite, and a tick is
    // never taken back. A check that disappears mid-call reads as the app
    // changing its mind about the learner.
    // A coach hint on a word outside the chip row is judged the same way;
    // its key joins the ticks so the hint can say "Used it".
    LaunchedEffect(state.turns, state.coachHint, state.coachStale) {
        // A hidden (stale) hint is out of the judging (iOS 30e49b07).
        val items = goals + listOfNotNull(state.coachHint.takeIf { !state.coachStale })
            .filter { h -> goals.none { it.key == h.key } }
        if (items.isEmpty()) return@LaunchedEffect
        var next = goalsUsed
        for (turn in state.turns) next = next + TalkGoalPicker.hits(turn, items)
        if (next != goalsUsed) goalsUsed = next
    }
    LaunchedEffect(goalsUsed) { if (preview == null) vm.noteUsedGoals(goalsUsed) }
    var showingFocus by remember { mutableStateOf(false) }

    // The newest line is always in view, as on iOS (bottom-anchored) — and
    // not only when a line is ADDED: a correction lands under the learner's
    // bubble and the reply grows as it streams, and scrolling to the new
    // item's top left the fluent self's answer below the fold. Following
    // stops while the learner has scrolled up to read, and resumes once
    // they are back at the bottom.
    // A fluent-self bubble is appended the moment its reply begins, before
    // the first word. Drawn then, it appeared EMPTY and grew twice — each a
    // step the scroll had to catch up with (iOS 8b3b45f2). Held back until
    // it has words; the thinking line keeps the place meanwhile.
    val replyHasNoWordsYet = state.turns.lastOrNull()
        ?.let { it.role == TurnRole.FLUENT_SELF && it.transcript.isEmpty() } == true
    val visibleTurns = if (replyHasNoWordsYet) state.turns.dropLast(1) else state.turns
    var followBottom by remember { mutableStateOf(true) }
    LaunchedEffect(listState) {
        androidx.compose.runtime.snapshotFlow { listState.isScrollInProgress }
            .collect { scrolling -> if (!scrolling) followBottom = !listState.canScrollForward }
    }
    val contentSize = Triple(state.turns.size, state.partial.length + state.phase.ordinal * 100_000, 0) to state.turns.sumOf {
        it.transcript.length + (it.suggestion?.alternative?.length ?: 0) + (it.suggestion?.reason?.length ?: 0)
    }
    LaunchedEffect(contentSize) {
        if (state.turns.isNotEmpty() && followBottom) {
            val last = (listState.layoutInfo.totalItemsCount - 1).coerceAtLeast(0)
            listState.animateScrollToItem(last, Int.MAX_VALUE)
        }
    }

    var confirmingDiscard by remember { mutableStateOf(false) }
    if (confirmingDiscard) {
        AlertDialog(
            onDismissRequest = { confirmingDiscard = false },
            title = { Text(stringResource(R.string.this_conversation_isn_t_saved_yet)) },
            text = { Text(stringResource(R.string.saving_wraps_up_the_talk_and_keeps_the_transcript_feedback_a_96e079)) },
            confirmButton = {
                TextButton(onClick = { confirmingDiscard = false; vm.end() }) {
                    Text(stringResource(R.string.save_conversation))
                }
            },
            dismissButton = {
                TextButton(onClick = { confirmingDiscard = false; exitAskingFirstCall() }) {
                    Text(stringResource(R.string.close_without_saving),
                        color = MaterialTheme.colorScheme.error)
                }
            })
    }
    // The transport went away mid-call. Two honest choices, and the
    // transcript stays on screen behind them. A call that drops silently is
    // a screen that listens to nothing (iOS `b147b53`).
    state.dropped?.let {
        AlertDialog(
            onDismissRequest = { },
            title = { Text(stringResource(R.string.the_call_dropped)) },
            text = { Text(stringResource(
                R.string.everything_said_so_far_is_saved_reconnect_to_carry_on_from_w_c4f94f)) },
            confirmButton = {
                TextButton(onClick = {
                    com.roro.futurevoice.core.Telemetry.log("talk_rt_reconnect",
                        mapOf("turns" to state.turns.size.toString()))
                    vm.reconnect()
                }) { Text(stringResource(R.string.reconnect)) }
            },
            dismissButton = {
                TextButton(onClick = { vm.end() }) { Text(stringResource(R.string.end_the_call)) }
            })
    }

    val paused = state.phase == TalkPhase.PAUSED
    val onCall = state.phase == TalkPhase.LISTENING ||
        state.phase == TalkPhase.THINKING || state.phase == TalkPhase.SPEAKING

    // The board runs, then the page it built opens by itself (iOS: the
    // summary sheet IS `ConversationDetailView` in post-talk mode). Done on
    // that page is the call's exit — the plans pitch and the way home. The
    // board is held a beat after its last row so it can be read.
    val summaryProgress by SessionSummarizer.progressBySession.collectAsStateWithLifecycle()
    val endedId = state.endedSessionId
    val summaryDone = endedId != null && summaryProgress[endedId]?.finished == true
    var showBook by remember { mutableStateOf(false) }
    LaunchedEffect(state.phase, summaryDone) {
        if (state.phase == TalkPhase.ENDED && summaryDone && preview == null) {
            kotlinx.coroutines.delay(1_500)
            showBook = true
        }
    }
    if (showBook && endedId != null) {
        TalkDetailScreen(
            sessionId = endedId,
            language = targetLanguage,
            level = level,
            onBack = {},
            onDone = { pitchThenLeave() },
        )
        return
    }

    // The call is on the PLAIN page, not the grouped ground (iOS
    // `ConversationView`: `.background(Color(.systemBackground))`) — white in
    // light, black in dark, header and feed one surface.
    val callPage = MaterialTheme.colorScheme.surface
    Scaffold(
        containerColor = callPage,
        topBar = {
            androidx.compose.material3.CenterAlignedTopAppBar(
                colors = androidx.compose.material3.TopAppBarDefaults.topAppBarColors(
                    containerColor = callPage, scrolledContainerColor = callPage),
                title = {
                    // WHAT the call is, not what it is doing. The phase reads
                    // under the control at the bottom, where the hand is, and
                    // a giant "Listening…" as the page title made the screen
                    // look like a status readout instead of a call.
                    var showingLevel by remember { mutableStateOf(false) }
                    if (showingLevel) LevelInfoSheet(level) { showingLevel = false }
                    // Tapping the title explains the level (iOS `LevelHeaderTitle`).
                    val stagedTitle = preview?.titleRes
                    if (stagedTitle != null) Text(stringResource(stagedTitle),
                        style = MaterialTheme.typography.titleMedium, maxLines = 1)
                    else Column(horizontalAlignment = Alignment.CenterHorizontally,
                        modifier = Modifier.clickable { showingLevel = true }) {
                        Text(topic.ifBlank { stringResource(R.string.lets_talk) },
                            style = MaterialTheme.typography.titleMedium,
                            maxLines = 1, overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis)
                        // The level being spoken at, and the call's own clock
                        // — a phone call shows how long you have been on it.
                        // It freezes while paused and stops once wrapped up.
                        val elapsed by produceState(0L, state.phase) {
                            while (state.phase != TalkPhase.ENDED) {
                                value = vm.elapsedSeconds()
                                kotlinx.coroutines.delay(1000)
                            }
                        }
                        Text(
                            listOfNotNull(
                                // The chevron says the level opens something.
                                level.code.uppercase() + " ›",
                                elapsed.takeIf { it > 0 }?.let {
                                    com.roro.futurevoice.data.TalkTime.clock(it.toInt())
                                },
                            ).joinToString(" · "),
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                },
                navigationIcon = {
                    // A talk with unsaved turns doesn't vanish on a stray tap
                    // — closing is an explicit choice between saving (the End
                    // flow: summary, drills) and discarding. Only the
                    // LEARNER's turns count: an opener alone is not a talk.
                    IconButton(onClick = {
                        if (state.turns.any { it.role == TurnRole.USER } && state.phase != TalkPhase.ENDED) {
                            confirmingDiscard = true
                        } else onExit()
                    }, modifier = Modifier.padding(start = 8.dp).size(44.dp)
                        .background(MaterialTheme.colorScheme.surfaceContainerHighest, CircleShape)) {
                        Icon(Icons.Filled.Close, contentDescription = stringResource(R.string.close))
                    }
                },
                actions = {
                    // End the call and STAY: the wrap-up is the most valuable
                    // minute the app spends, and leaving here skipped it
                    // entirely. Done is what leaves.
                    // iOS draws End as red text on a round glass chip — a
                    // hang-up, not a primary action. Done keeps the accent.
                    val chip = Modifier.padding(end = 8.dp)
                        .background(MaterialTheme.colorScheme.surfaceContainerHighest, CircleShape)
                    if (state.phase == TalkPhase.ENDED) {
                        TextButton(onClick = { pitchThenLeave() }, modifier = chip) {
                            Text(stringResource(R.string.done), style = MaterialTheme.typography.titleMedium)
                        }
                    } else if (state.turns.isNotEmpty()) {
                        // Only once there is a line on screen (iOS: `if
                        // !turns.isEmpty`) — before the call connects there is
                        // nothing to hang up; the close button leaves.
                        TextButton(onClick = {
                            vm.end()
                            // A call nobody spoke in has nothing to wrap up —
                            // `end` skips the save, so there is no board to
                            // hold anyone here. (Set synchronously.)
                            if (vm.state.value.endedSessionId == null) onExit()
                        }, modifier = chip) {
                            Text(stringResource(R.string.end), style = MaterialTheme.typography.titleMedium,
                                color = androidx.compose.ui.graphics.Color(0xFFFF3B30))
                        }
                    }
                },
            )
        }
    ) { padding ->
        Column(Modifier.padding(padding).fillMaxSize()) {
            // Pinned ABOVE the transcript, which scrolls away constantly —
            // the whole point is that it is in front of the learner at the
            // moment they could spend the word.
            val ended = state.phase == TalkPhase.ENDED && state.endedSessionId != null
            // The grammar focus sits above the chips: it is the one thing
            // this call is about, and the chips are the things to spend.
            val focus = state.grammarFocus
            if (coachMode && focus != null && !ended) {
                GrammarFocusStrip(focus.label, focus.pattern.mistake, focus.pattern.correction,
                    repeats = state.focusRepeatTurns.size, onTap = { showingFocus = true })
                androidx.compose.material3.HorizontalDivider(Modifier.alpha(0.15f))
            }
            if (showingFocus && focus != null) {
                GrammarFocusSheet(focus, state.focusRepeatTurns.size, onDismiss = { showingFocus = false })
            }
            if (goals.isNotEmpty() && !ended && showsGoalChips) {
                TalkGoalChipsRow(goals, goalsUsed, onTap = { openGoal = it })
            }
            // Nothing pauses underneath: WordLore is free and globally
            // cached, so a mid-call tap costs nothing metered.
            openGoal?.let { goal ->
                TalkGoalSheet(
                    item = goal,
                    used = goalsUsed.contains(goal.key),
                    nativeLanguage = nativeLanguage,
                    targetLanguage = targetLanguage,
                    onDismiss = { openGoal = null },
                )
            }
            // The call is over: the board takes the screen, as on iOS — the
            // transcript is already in the book it is building.
            if (ended) Spacer(Modifier.weight(1f))
            // During the call the bottom FLOATS (iOS `fadingBottomBar`): the
            // transcript runs on underneath it, and the bar carries no
            // background of its own — a wash of the page colour sits behind
            // it and fades out over the last 36 dp above it, so lines
            // dissolve into the bar instead of being sliced off by an edge.
            // The top gets the same soft edge under the header.
            if (!ended) {
              var floatingBarHeight by remember { mutableIntStateOf(0) }
              Box(Modifier.weight(1f).fillMaxWidth()) {
                    LazyColumn(
                    state = listState,
                    modifier = Modifier
                        .fillMaxSize()
                        // A paused call is picked back up by tapping the
                        // conversation itself — the screen never lost it.
                        .clickable(enabled = paused) { vm.resume() },
                    // The last line clears the floating bar; everything above it
                    // scrolls on underneath and dissolves into the wash.
                    contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = 16.dp,
                        bottom = 16.dp + with(LocalDensity.current) { floatingBarHeight.toDp() }),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    // The first seconds of a call have nothing on them yet: say
                    // what is happening, where the first line will appear (iOS
                    // `feed`: top of the transcript, centred, 40 pt down, the
                    // grey wheel — it sat in the bottom bar, left, in Material).
                    if (state.turns.isEmpty()) item(key = "starting") {
                        Row(Modifier.fillMaxWidth().padding(top = 24.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(10.dp, Alignment.CenterHorizontally)) {
                            com.roro.futurevoice.ui.brand.IosActivityIndicator()
                            Text(stringResource(
                                if (topic.isBlank()) R.string.starting_your_conversation
                                else R.string.setting_the_scene),
                                style = MaterialTheme.typography.bodyLarge,
                                color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                    // Subtitles off: the call is audio only, like a phone call —
                    // the pill still shows whose turn it is.
                    if (!showsTranscript && state.turns.isNotEmpty()) item(key = "subtitles-off") {
                        Text(stringResource(R.string.subtitles_are_off),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f),
                            textAlign = androidx.compose.ui.text.style.TextAlign.Center,
                            modifier = Modifier.fillMaxWidth().padding(top = 24.dp))
                    }
                    if (showsTranscript) items(visibleTurns, key = { it.id }) { turn ->
                        // Everything that changes the feed's height — a bubble
                        // arriving, a correction card a second after the line —
                        // moves on one easing instead of jumping the content
                        // and the scroll chasing it (iOS 8b3b45f2).
                        Box(Modifier.animateItem(fadeInSpec = tween(250), placementSpec = tween(250),
                            fadeOutSpec = tween(250)).animateContentSize(tween(250))) {
                            DialogueLine(turn, scale = DialogueScale.CALL, otherName = cast?.name,
                                showsCorrections = showsCorrections,
                                focusRepeatLabel = if (coachMode && turn.id in state.focusRepeatTurns)
                                    state.grammarFocus?.label else null)
                        }
                    }
                    // The learner's turn, drawn where it will land (iOS
                    // `PartialTurnView`): the You bubble appears EMPTY the moment
                    // it is their turn — that empty bubble is the "your turn"
                    // signal — and fills with the words as they are heard. Not
                    // before the first line exists: the call opens with the
                    // fluent self, and an empty bubble would flash and vanish.
                    if (showsTranscript && state.phase == TalkPhase.LISTENING &&
                        (state.turns.isNotEmpty() || state.partial.isNotBlank())) {
                        // A placeholder is REPLACED by the bubble that follows
                        // it, so it leaves at once (iOS c95242cc): faded out,
                        // it kept its height while the new bubble came in and
                        // the list rose and dropped a little every turn.
                        item(key = "partial-listening") {
                            com.roro.futurevoice.ui.brand.DialogueLine(
                                modifier = Modifier.animateItem(fadeInSpec = tween(250), placementSpec = null,
                                    fadeOutSpec = null),
                                speaker = com.roro.futurevoice.ui.brand.DialogueSpeaker.USER,
                                name = stringResource(R.string.you),
                                scale = DialogueScale.CALL,
                            ) {
                                Text(
                                    state.partial.ifBlank { stringResource(R.string.listening) },
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    fontStyle = if (state.partial.isBlank()) FontStyle.Italic else FontStyle.Normal,
                                )
                            }
                        }
                    }
                    // The reply has begun but has no words yet: the thinking
                    // line keeps its place (same key) until the bubble that
                    // replaces it has text to be drawn with (iOS 8b3b45f2).
                    if ((state.phase == TalkPhase.THINKING && state.turns.lastOrNull()?.role == TurnRole.USER) ||
                        replyHasNoWordsYet) {
                        item(key = "partial-thinking") {
                            Row(Modifier.animateItem(fadeInSpec = tween(250), placementSpec = null, fadeOutSpec = null),
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                CircularProgressIndicator(Modifier.size(14.dp), strokeWidth = 2.dp)
                                Text(stringResource(R.string.future_self_is_thinking),
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                        }
                    }
                }

                val page = callPage
                Box(Modifier.align(Alignment.TopCenter).fillMaxWidth().height(24.dp)
                    .background(Brush.verticalGradient(listOf(page, page.copy(alpha = 0f)))))
                Column(
                    Modifier.align(Alignment.BottomCenter).fillMaxWidth()
                        .onSizeChanged { floatingBarHeight = it.height }
                        .drawBehind {
                            // Nothing in the bar (before the call connects):
                            // no wash either. A gradient brush on an EMPTY draw
                            // size makes no shader, and the paint falls back to
                            // solid black — a 64 dp black band over the page.
                            if (size.height <= 0f) return@drawBehind
                            // Longer than iOS's pre-26 fallback (36 pt): iOS 26's
                            // soft edge dissolves over about a bubble's height,
                            // and 36 read as a cut on a phone this size.
                            val fade = 64.dp.toPx()
                            drawRect(Brush.verticalGradient(listOf(page.copy(alpha = 0f), page),
                                startY = -fade, endY = 0f),
                                topLeft = Offset(0f, -fade), size = Size(size.width, fade))
                            drawRect(page)
                        },
                ) {


                    // A failed reply is answerable: the learner said something and
                    // heard nothing back, and the fix is one tap.
                    state.error?.let {
                        Row(Modifier.fillMaxWidth().padding(16.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                            Text(stringResource(R.string.couldn_t_get_a_response),
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                modifier = Modifier.weight(1f))
                            TextButton(onClick = { vm.retry() }) { Text(stringResource(R.string.retry)) }
                        }
                    }

                    // The bottom bar. The Futureself pill IS the control — it is
                    // what you tap to put the call down and pick it back up, and
                    // while the call runs the living surface is the state display:
                    // it ignites bottom-up with the learner's voice, sweeps while
                    // thinking, blooms centre-out while the fluent self speaks.
                    // A separate outlined "Pause" button below it made the surface
                    // decoration and the control an afterthought.
                    if (onCall || paused) {
                        androidx.compose.runtime.DisposableEffect(Unit) {
                            onDispose { TalkMorph.pillPresent = false }
                        }
                        Column(
                            Modifier.fillMaxWidth().padding(top = 14.dp, bottom = 20.dp),
                            horizontalAlignment = Alignment.CenterHorizontally,
                            verticalArrangement = Arrangement.spacedBy(10.dp),
                        ) {
                            // Coach mode's help sits HERE, right above the pill,
                            // and never in the learner's listening bubble (iOS
                            // `6e9eb92`, device test): the suggestion lands a beat
                            // after the bubble is drawn, the bubble grew under the
                            // bar with nothing scrolling it back into view, and
                            // "Listening…" beside a bold sentence read as two
                            // voices in one shape. A fixed spot can't be scrolled
                            // away.
                            // "You go first" (a situation the learner opens)
                            // shows whatever coach mode says.
                            // When a reply begins the coach's line goes from SIGHT
                            // only (iOS 30e49b07): removing it shrank this bar at
                            // the very moment the reply's bubble pushed the feed
                            // up. The slot keeps its height until the next
                            // suggestion replaces it.
                            val coachAlpha by animateFloatAsState(if (state.coachStale) 0f else 1f, tween(200),
                                label = "coachStale")
                            state.coachReply?.takeIf { coachMode || it.heading != null }?.let { reply ->
                                CoachReplyLabel(reply, Modifier.padding(horizontal = 32.dp).alpha(coachAlpha))
                            }
                            if (coachMode) state.coachHint?.let { hint ->
                                Box(Modifier.padding(horizontal = 24.dp).alpha(coachAlpha)) {
                                    CoachHintLabel(hint, used = hint.key in goalsUsed,
                                        onTap = { if (!state.coachStale) openGoal = hint })
                                }
                            }
                            Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                            // Quiet on purpose: the one primary action here is the pill.
                            IconButton(onClick = { showingCallSettings = true },
                                modifier = Modifier.align(Alignment.CenterStart).padding(start = 16.dp)) {
                                Icon(Icons.Filled.Tune, contentDescription = stringResource(R.string.call_settings),
                                    tint = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                            Box(
                                Modifier
                                    .size(width = 156.dp, height = 64.dp)
                                    // Where the free-talk morph docks (and leaves from).
                                    .onGloballyPositioned {
                                        TalkMorph.pillRect = it.boundsInWindow(); TalkMorph.pillPresent = true }
                                    .clip(CircleShape)
                                    .clickable { vm.togglePause() },
                                contentAlignment = Alignment.Center,
                            ) {
                                Futureself(
                                    mode = when (state.phase) {
                                        TalkPhase.LISTENING -> FutureselfMode.LISTENING
                                        TalkPhase.THINKING, TalkPhase.CONNECTING -> FutureselfMode.THINKING
                                        TalkPhase.SPEAKING -> FutureselfMode.SPEAKING
                                        else -> FutureselfMode.IDLE
                                    },
                                    level = state.level.coerceIn(0f, 1f),
                                    theme = remember { FutureselfTheme.stored(context) },
                                    modifier = Modifier.fillMaxSize(),
                                )
                                // The clock lives INSIDE the pill. Whole minutes only,
                                // and only while there is a figure to show — a
                                // month-long balance must never read as a running
                                // meter, so it joins the surface rather than taking a
                                // line of its own.
                                // Only while it matters (iOS: ≤10 min), and orange
                                // in the last three — the one moment a figure helps.
                                state.minutesRemaining?.takeIf { it <= 10 }?.let { minutes ->
                                    Text(
                                        stringResource(R.string.lld_min_left, minutes),
                                        style = MaterialTheme.typography.labelMedium,
                                        color = if (minutes <= 3) androidx.compose.ui.graphics.Color(0xFFFF9500)
                                        else MaterialTheme.colorScheme.onSurface,
                                    )
                                }
                            }
                            }
                            // The phase, quietly, where the hand is.
                            Text(
                                phaseHint(state.phase, paused, state.pausedForIdle),
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                }
              }
            }
            if (ended) {
                // The first seconds of a call had nothing on them: an empty list
                // and no bottom bar. Say what is happening instead.
                if (state.phase == TalkPhase.CONNECTING && state.turns.isEmpty()) {
                    Row(Modifier.fillMaxWidth().padding(16.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
                        Text(stringResource(
                            if (topic.isBlank()) R.string.starting_your_conversation
                            else R.string.setting_the_scene),
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }


                // A failed reply is answerable: the learner said something and
                // heard nothing back, and the fix is one tap.
                state.error?.let {
                    Row(Modifier.fillMaxWidth().padding(16.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        Text(stringResource(R.string.couldn_t_get_a_response),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.weight(1f))
                        TextButton(onClick = { vm.retry() }) { Text(stringResource(R.string.retry)) }
                    }
                }

            }
            // The wait at the end shows its work (`SummaryProgressView`):
            // the board while the analysis runs, its last frame + the top
            // line once the summary is on disk.
            if (state.phase == TalkPhase.ENDED) {
                state.endedSessionId?.let { sessionId ->
                    EndOfTalkWrapUp(
                        sessionId = sessionId,
                        userTurns = state.turns.count { it.role == TurnRole.USER },
                        spentPool = state.wall == TalkWall.OUT_OF_MINUTES)
                }
                Spacer(Modifier.weight(1.3f))
            }


        }
    }

    spent?.let { pool ->
        AllowanceSpentSheet(
            pool = pool,
            onReview = { spent = null; leaveForPractice() },
            onUpgrade = { spent = null; BillingGate.showPaywall.value = true },
            onDismiss = { spent = null },
        )
    }
}

/**
 * THE one dialogue surface. Speaker separation (name label, alignment,
 * suggestion chip) lives here and nowhere else — callers pass a turn, never
 * re-implement a line locally.
 */
@Composable
fun DialogueLine(turn: Turn) {
    val isUser = turn.role == TurnRole.USER
    Column(
        Modifier.fillMaxWidth(),
        horizontalAlignment = if (isUser) Alignment.End else Alignment.Start,
    ) {
        Text(
            stringResource(if (isUser) R.string.you else R.string.future_self_1384d5),
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Text(turn.transcript, style = MaterialTheme.typography.bodyLarge)
        turn.suggestion?.let { suggestion ->
            SuggestionChip(suggestion, original = turn.transcript)
        }
    }
}

/**
 * A conversation TURN as a dialogue line. The chrome lives in
 * `brand/DialogueLine.kt`; this only maps a Turn onto it and hangs the
 * suggestion chip underneath as this surface's accessory.
 */
@Composable
fun DialogueLine(turn: Turn, isCurrent: Boolean = false,
                 scale: DialogueScale = DialogueScale.STANDARD,
                 otherName: String? = null,
                 selfName: String? = null,
                 showsCorrections: Boolean = true,
                 /** The grammar focus's name when this turn's correction is
                  *  that slip coming back (coach mode) — worn as a badge. */
                 focusRepeatLabel: String? = null) {
    val isUser = turn.role == TurnRole.USER
    DialogueLine(
        speaker = if (isUser) DialogueSpeaker.USER else DialogueSpeaker.OTHER,
        // The other side is the fluent self — unless the call was cast as a
        // person, in which case it is THEM.
        name = if (isUser) selfName ?: stringResource(R.string.you)
        else otherName ?: stringResource(R.string.future_self_1384d5),
        scale = scale,
        isCurrent = isCurrent,
        accessory = {
            if (showsCorrections) turn.suggestion?.let { suggestion ->
                Column {
                    focusRepeatLabel?.let {
                        Box(Modifier.padding(top = 4.dp)) { GrammarFocusRepeatBadge(it) }
                    }
                    SuggestionChip(suggestion, original = turn.transcript)
                }
            }
        },
    ) { Text(turn.transcript) }
}

@Composable
private fun phaseLabel(phase: TalkPhase): String = stringResource(
    when (phase) {
        TalkPhase.IDLE -> R.string.talk
        TalkPhase.CONNECTING -> R.string.connecting
        TalkPhase.LISTENING -> R.string.listening
        TalkPhase.THINKING -> R.string.thinking
        TalkPhase.SPEAKING -> R.string.speaking
        TalkPhase.PAUSED -> R.string.paused
        TalkPhase.ENDED -> R.string.ended
    }
)

/** Board + result for the talk that just ended, keyed to its session row. */
@Composable
private fun EndOfTalkWrapUp(sessionId: String, userTurns: Int, spentPool: Boolean = false) {
    val context = LocalContext.current
    val progressMap by SessionSummarizer.progressBySession.collectAsStateWithLifecycle()
    val revision by StoreEvents.revision.collectAsStateWithLifecycle()
    val progress = progressMap[sessionId] ?: return
    var topLine by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(revision, progress.finished) {
        if (progress.finished) {
            topLine = SessionStore.shared(context).load()
                .firstOrNull { it.id == sessionId }?.summary?.scorecard?.topLine
        }
    }
    Column(Modifier.padding(16.dp)) {
        // Why the call ended, above the board — it wrapped itself up, and a
        // learner who did not press End is owed the reason.
        if (spentPool) {
            Text(stringResource(R.string.your_free_talk_time_is_used_up),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(bottom = 8.dp))
        }
        SummaryBoard(progress, facts = stringResource(R.string.lld_turns, userTurns))
        topLine?.takeIf { it.isNotBlank() }?.let {
            Text(it, style = MaterialTheme.typography.bodyMedium,
                modifier = Modifier.padding(top = 12.dp))
        }
    }

}
/**
 * What the call is doing, in the learner's words — under the control, not as
 * the page title. A paused call SAYS it is paused: without that the screen
 * looks identical to one the learner stopped on purpose, and the only clue
 * that 30 seconds passed is that nothing is happening.
 */
@Composable
private fun phaseHint(phase: TalkPhase, paused: Boolean, pausedForIdle: Boolean): String =
    stringResource(
        when {
            pausedForIdle -> R.string.call_paused_tap_to_pick_it_back_up
            paused -> R.string.paused_tap_to_pick_it_back_up
            phase == TalkPhase.LISTENING -> R.string.listening_pause_to_send_tap_to_stop
            phase == TalkPhase.THINKING || phase == TalkPhase.CONNECTING ->
                R.string.thinking_tap_to_stop
            // Realtime: the learner can talk over the reply and the gateway
            // yields — say so, as iOS does on this path.
            phase == TalkPhase.SPEAKING -> R.string.speaking_talk_over_it_tap_to_stop
            else -> R.string.on_call_tap_to_stop
        }
    )

/**
 * The correction under a turn: the fluent line with the CHANGED words lit up,
 * the reason, and — on demand — that reason in the learner's own language.
 *
 * The highlight compares through [SpokenWords], so "I'm" against "I am"
 * lights up nothing: contraction and punctuation are the transcriber's
 * choices, and painting them as the learner's mistake is the bug this
 * alignment exists to prevent.
 */
@Composable
private fun SuggestionChip(suggestion: com.roro.futurevoice.talk.TurnSuggestion, original: String) {
    val context = LocalContext.current
    // The learner's own language, read here rather than threaded through
    // every caller: a dialogue line is drawn from four screens.
    val nativeLanguage = remember {
        context.getSharedPreferences("futurevoice", 0)
            .getString("futurevoice.nativeLanguage", null) ?: "en"
    }
    val scope = rememberCoroutineScope()
    var showing by remember(suggestion.alternative) { mutableStateOf(false) }
    var loading by remember(suggestion.alternative) { mutableStateOf(false) }
    var reasonNative by remember(suggestion.alternative) {
        mutableStateOf(com.roro.futurevoice.net.Translator.cachedExplanation(
            context, original, suggestion.alternative, nativeLanguage))
    }
    val tint = MaterialTheme.colorScheme.primary
    val language = remember { com.roro.futurevoice.data.LanguageScope.active(context) }
    val line = remember(suggestion.alternative, original, tint) {
        correctionLine(suggestion.alternative, original, language,
            SpanStyle(color = tint, fontWeight = FontWeight.SemiBold))
    }
    Column(Modifier.fillMaxWidth().padding(top = 4.dp),
        verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Text(line, style = MaterialTheme.typography.bodyMedium)
        Text(suggestion.reason, style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant)
        // The second answer: the outright errors, one clause each.
        suggestion.fixes?.takeIf { it.isNotEmpty() }?.let {
            TurnFixRows(it, Modifier.padding(top = 4.dp))
        }
        Row(verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp),
            modifier = Modifier.clickable {
                if (showing) { showing = false; return@clickable }
                showing = true
                if (reasonNative == null && !loading) {
                    loading = true
                    scope.launch {
                        val t = com.roro.futurevoice.net.Translator.explainCorrection(
                            context, original, suggestion.alternative, nativeLanguage)
                        reasonNative = t
                        loading = false
                        if (t == null) showing = false
                    }
                }
            }) {
            if (loading) CircularProgressIndicator(Modifier.size(12.dp), strokeWidth = 1.5.dp)
            Text(stringResource(if (showing) R.string.hide else R.string.explain_in_my_language),
                style = MaterialTheme.typography.labelSmall, color = tint)
        }
        if (showing) reasonNative?.let {
            Text(it, style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

/**
 * A turn's grammar slips, one per row — ✗ what they said (struck through),
 * ✓ the same words corrected, the reason underneath (iOS `TurnFixRows`).
 */
@Composable
fun TurnFixRows(fixes: List<com.roro.futurevoice.talk.TurnFix>, modifier: Modifier = Modifier) {
    Column(modifier, verticalArrangement = Arrangement.spacedBy(6.dp)) {
        for (fix in fixes) {
            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text("✕", style = MaterialTheme.typography.labelSmall,
                        color = androidx.compose.ui.graphics.Color(0xFFFF3B30))
                    Text(fix.was, style = MaterialTheme.typography.labelSmall.copy(
                        textDecoration = androidx.compose.ui.text.style.TextDecoration.LineThrough),
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text("✓", style = MaterialTheme.typography.labelSmall,
                        color = androidx.compose.ui.graphics.Color(0xFF34C759))
                    Text(fix.now, style = MaterialTheme.typography.labelSmall)
                }
                if (fix.why.isNotBlank()) {
                    Text(fix.why, style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f),
                        modifier = Modifier.padding(start = 18.dp))
                }
            }
        }
    }
}
