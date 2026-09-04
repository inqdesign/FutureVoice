package com.roro.futurevoice.ui

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
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
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
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.HorizontalDivider
import androidx.compose.ui.draw.alpha
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
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
    onExit: () -> Unit,
) {
    val context = LocalContext.current
    val vm: TalkViewModel = viewModel(
        factory = viewModelFactory {
            initializer { TalkViewModel(context) }
        }
    )
    val state by vm.state.collectAsStateWithLifecycle()
    // System back = hang up and leave, same as End — never kill the activity
    // with a call still holding the mic.
    androidx.activity.compose.BackHandler {
        if (state.phase == TalkPhase.ENDED) onExit()
        else { vm.end(); if (vm.state.value.endedSessionId == null) onExit() }
    }
    /** A spent allowance: a sheet, never an error and never a bare paywall. */
    var spent by remember { mutableStateOf<SpentPool?>(null) }
    var canUpgrade by remember { mutableStateOf(false) }
    LaunchedEffect(spent) {
        if (spent != null) canUpgrade = AccountStatus.load(AuthRepository()).isLightPlan
    }
    val listState = rememberLazyListState()

    LaunchedEffect(voiceId) {
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
            )
        )
    }
    DisposableEffect(Unit) { onDispose { vm.end() } }

    // Today's notebook, dealt once when the call opens. It never re-deals
    // mid-call: a row that changed under the learner would be asking for a
    // different word than the one they were about to say.
    var goals by remember { mutableStateOf<List<TalkGoalItem>>(emptyList()) }
    var goalsUsed by remember { mutableStateOf<Set<String>>(emptySet()) }
    var openGoal by remember { mutableStateOf<TalkGoalItem?>(null) }
    LaunchedEffect(targetLanguage) {
        goals = TalkGoalPicker.pick(context, targetLanguage)
    }
    // ADDITIVE: every version of a user turn's text is checked, from the
    // recognizer's first line to the audio-grounded rewrite, and a tick is
    // never taken back. A check that disappears mid-call reads as the app
    // changing its mind about the learner.
    LaunchedEffect(state.turns) {
        if (goals.isEmpty()) return@LaunchedEffect
        var next = goalsUsed
        for (turn in state.turns) next = next + TalkGoalPicker.hits(turn, goals)
        if (next != goalsUsed) goalsUsed = next
    }

    LaunchedEffect(state.turns.size) {
        if (state.turns.isNotEmpty()) listState.animateScrollToItem(state.turns.lastIndex)
    }

    val paused = state.phase == TalkPhase.PAUSED
    val onCall = state.phase == TalkPhase.LISTENING ||
        state.phase == TalkPhase.THINKING || state.phase == TalkPhase.SPEAKING

    Scaffold(
        topBar = {
            TopAppBar(
                colors = AppSurfaces.topBarColors(),
                title = {
                    // WHAT the call is, not what it is doing. The phase reads
                    // under the control at the bottom, where the hand is, and
                    // a giant "Listening…" as the page title made the screen
                    // look like a status readout instead of a call.
                    Text(topic.ifBlank { stringResource(R.string.lets_talk) })
                },
                actions = {
                    // End the call and STAY: the wrap-up is the most valuable
                    // minute the app spends, and leaving here skipped it
                    // entirely. Done is what leaves.
                    if (state.phase == TalkPhase.ENDED) {
                        Button(onClick = onExit) { Text(stringResource(R.string.done)) }
                    } else {
                        Button(onClick = {
                            vm.end()
                            // A call nobody spoke in has nothing to wrap up —
                            // `end` skips the save, so there is no board to
                            // hold anyone here. (Set synchronously.)
                            if (vm.state.value.endedSessionId == null) onExit()
                        }) { Text(stringResource(R.string.end)) }
                    }
                },
            )
        }
    ) { padding ->
        Column(Modifier.padding(padding).fillMaxSize()) {
            // Pinned ABOVE the transcript, which scrolls away constantly —
            // the whole point is that it is in front of the learner at the
            // moment they could spend the word.
            if (goals.isNotEmpty()) {
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
            LazyColumn(
                state = listState,
                modifier = Modifier
                    .weight(1f)
                    .fillMaxWidth()
                    // A paused call is picked back up by tapping the
                    // conversation itself — the screen never lost it.
                    .clickable(enabled = paused) { vm.resume() }
                    .padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                items(state.turns, key = { it.id }) { turn ->
                    DialogueLine(turn, scale = DialogueScale.CALL, otherName = cast?.name)
                }
            }

            if (state.partial.isNotBlank()) {
                Text(
                    state.partial,
                    style = MaterialTheme.typography.bodyMedium,
                    fontStyle = FontStyle.Italic,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                )
            }

            // A spent allowance is not an error — it gets its own line, in
            // the body colour, and a subscriber never reads the word "credits".
            state.wall?.let { wall ->
                // The call is over and saved either way — the line below says
                // so. What differs is the ANSWER, raised on top of it once.
                LaunchedEffect(wall) {
                    when (wall) {
                        TalkWall.OUT_OF_MINUTES -> {
                            BillingGate.invalidate()
                            BillingGate.showPaywall.value = true
                        }
                        TalkWall.ALLOWANCE_SPENT -> spent = SpentPool.TALK
                        TalkWall.SCENES_SPENT -> spent = SpentPool.SCENES
                    }
                }
                Text(
                    stringResource(
                        when (wall) {
                            TalkWall.OUT_OF_MINUTES ->
                                R.string.your_talk_time_is_used_up_this_call_is_saved_you_can_pick_it_46ade7
                            TalkWall.ALLOWANCE_SPENT ->
                                R.string.this_month_s_talk_time_is_used_up
                            TalkWall.SCENES_SPENT ->
                                R.string.thats_your_watch_scenes_for_this_period
                        }
                    ),
                    style = MaterialTheme.typography.bodyMedium,
                    modifier = Modifier.padding(16.dp),
                )
            }

            state.error?.let {
                Text(
                    it,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.error,
                    modifier = Modifier.padding(16.dp),
                )
            }

            // The wait at the end shows its work (`SummaryProgressView`):
            // the board while the analysis runs, its last frame + the top
            // line once the summary is on disk.
            if (state.phase == TalkPhase.ENDED) {
                state.endedSessionId?.let { sessionId ->
                    EndOfTalkWrapUp(sessionId = sessionId, userTurns = state.turns.count { it.role == TurnRole.USER })
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
                HorizontalDivider(Modifier.alpha(0.15f))
                Column(
                    Modifier.fillMaxWidth().padding(top = 14.dp, bottom = 20.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    Box(
                        Modifier
                            .size(width = 156.dp, height = 64.dp)
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
                        state.minutesRemaining?.let { minutes ->
                            Text(
                                stringResource(R.string.lld_min_left, minutes),
                                style = MaterialTheme.typography.labelMedium,
                                color = MaterialTheme.colorScheme.onSurface,
                            )
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

    spent?.let { pool ->
        AllowanceSpentSheet(
            pool = pool,
            canUpgrade = canUpgrade,
            onReview = { spent = null; onExit() },
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
            Row(
                Modifier.fillMaxWidth().padding(top = 4.dp),
                horizontalArrangement = if (isUser) Arrangement.End else Arrangement.Start,
            ) {
                Text(
                    "→ ${suggestion.alternative}  ·  ${suggestion.reason}",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.primary,
                )
            }
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
                 otherName: String? = null) {
    val isUser = turn.role == TurnRole.USER
    DialogueLine(
        speaker = if (isUser) DialogueSpeaker.USER else DialogueSpeaker.OTHER,
        // The other side is the fluent self — unless the call was cast as a
        // person, in which case it is THEM.
        name = if (isUser) stringResource(R.string.you)
        else otherName ?: stringResource(R.string.future_self_1384d5),
        scale = scale,
        isCurrent = isCurrent,
        accessory = {
            turn.suggestion?.let { suggestion ->
                Text(
                    "→ ${suggestion.alternative}  ·  ${suggestion.reason}",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.primary,
                )
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
private fun EndOfTalkWrapUp(sessionId: String, userTurns: Int) {
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
            phase == TalkPhase.SPEAKING -> R.string.speaking_tap_to_stop
            else -> R.string.on_call_tap_to_stop
        }
    )
