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
    androidx.activity.compose.BackHandler { vm.end(); onExit() }
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
            )
        )
    }
    DisposableEffect(Unit) { onDispose { vm.end() } }

    LaunchedEffect(state.turns.size) {
        if (state.turns.isNotEmpty()) listState.animateScrollToItem(state.turns.lastIndex)
    }

    val paused = state.phase == TalkPhase.PAUSED
    val onCall = state.phase == TalkPhase.LISTENING ||
        state.phase == TalkPhase.THINKING || state.phase == TalkPhase.SPEAKING

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    // Minutes left ride on the title, whole minutes only — a
                    // month-long balance must never read as a running meter.
                    val minutes = state.minutesRemaining
                    val label = phaseLabel(state.phase)
                    Text(
                        if (minutes != null && state.phase != TalkPhase.ENDED)
                            "$label · ${stringResource(R.string.lld_min_left, minutes)}"
                        else label
                    )
                },
                actions = {
                    Button(onClick = { vm.end(); onExit() }) { Text(stringResource(R.string.end)) }
                },
            )
        }
    ) { padding ->
        Column(Modifier.padding(padding).fillMaxSize()) {
            // Subtle only — a level bar, not a bouncing waveform.
            LinearProgressIndicator(
                progress = { state.level.coerceIn(0f, 1f) },
                modifier = Modifier.fillMaxWidth(),
            )

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
                items(state.turns, key = { it.id }) { turn -> DialogueLine(turn) }
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

            // A call that put itself down says so. Without this the screen
            // looks identical to one the learner stopped on purpose, and the
            // only clue that 30 s passed is that nothing is happening.
            if (paused) {
                Text(
                    stringResource(
                        if (state.pausedForIdle) R.string.call_paused_tap_to_pick_it_back_up
                        else R.string.paused_tap_to_pick_it_back_up
                    ),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                )
            }

            // A spent allowance is not an error — it gets its own line, in
            // the body colour, and a subscriber never reads the word "credits".
            state.wall?.let { wall ->
                Text(
                    stringResource(
                        when (wall) {
                            TalkWall.OUT_OF_MINUTES ->
                                R.string.your_talk_time_is_used_up_this_call_is_saved_you_can_pick_it_46ade7
                            TalkWall.ALLOWANCE_SPENT ->
                                R.string.this_month_s_talk_time_is_used_up
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

            // The one in-call control besides End: put the call down, pick it
            // up. Pausing has no consequences (no summary, no book), which is
            // why it needs no confirmation.
            if (onCall || paused) {
                Row(
                    Modifier.fillMaxWidth().padding(16.dp),
                    horizontalArrangement = Arrangement.Center,
                ) {
                    OutlinedButton(onClick = { vm.togglePause() }) {
                        Text(stringResource(if (paused) R.string.resume else R.string.pause))
                    }
                }
            }
        }
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
