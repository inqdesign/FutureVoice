package com.roro.futurevoice.ui

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
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
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
import com.roro.futurevoice.talk.Turn
import com.roro.futurevoice.talk.TurnRole

/**
 * Phone-call mode, not a chat app: one dialogue surface, a status line, and an
 * End button. Speaker separation lives in [DialogueLine] alone — restyling the
 * conversation must stay a single-composable change.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TalkScreen(
    voiceId: String,
    targetLanguage: String,
    nativeLanguage: String,
    level: CefrLevel,
    onExit: () -> Unit,
) {
    val context = LocalContext.current
    val vm: TalkViewModel = viewModel(
        factory = viewModelFactory {
            initializer { TalkViewModel(context) }
        }
    )
    val state by vm.state.collectAsStateWithLifecycle()
    val listState = rememberLazyListState()

    LaunchedEffect(voiceId) {
        vm.start(
            TalkConfig(
                voiceId = voiceId,
                targetLanguage = targetLanguage,
                nativeLanguage = nativeLanguage,
                level = level,
            )
        )
    }
    DisposableEffect(Unit) { onDispose { vm.end() } }

    LaunchedEffect(state.turns.size) {
        if (state.turns.isNotEmpty()) listState.animateScrollToItem(state.turns.lastIndex)
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(phaseLabel(state.phase)) },
                actions = {
                    Button(onClick = { vm.end(); onExit() }) { Text("End") }
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
                modifier = Modifier.weight(1f).fillMaxWidth().padding(16.dp),
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

            state.error?.let {
                Text(
                    it,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.error,
                    modifier = Modifier.padding(16.dp),
                )
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
            if (isUser) "You" else "Fluent self",
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

private fun phaseLabel(phase: TalkPhase): String = when (phase) {
    TalkPhase.IDLE -> "Talk"
    TalkPhase.CONNECTING -> "Connecting…"
    TalkPhase.LISTENING -> "Listening"
    TalkPhase.THINKING -> "…"
    TalkPhase.SPEAKING -> "Speaking"
    TalkPhase.ENDED -> "Ended"
}
