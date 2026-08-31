package com.roro.futurevoice.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.clickable
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.roro.futurevoice.R
import com.roro.futurevoice.data.SessionStore
import com.roro.futurevoice.data.StoreEvents
import com.roro.futurevoice.talk.Session
import com.roro.futurevoice.talk.TurnRole

/**
 * A finished talk's page — `ConversationDetailView` reduced to its reading
 * spine: the scorecard headline, the review material the summary produced
 * (corrections · offered expressions · grammar evidence · drills), then the
 * raw transcript. Continue/Replay/shadowing arrive with the Practice pass.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TalkDetailScreen(sessionId: String, language: String, onBack: () -> Unit,
                     onShadow: (String) -> Unit = {}) {
    androidx.activity.compose.BackHandler(onBack = onBack)
    val context = LocalContext.current
    val revision by StoreEvents.revision.collectAsStateWithLifecycle()
    var session by remember { mutableStateOf<Session?>(null) }
    LaunchedEffect(sessionId, revision) {
        session = SessionStore.shared(context).load(language).firstOrNull { it.id == sessionId }
    }
    val s = session ?: return

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(s.displayTitle ?: stringResource(R.string.conversation)) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = null)
                    }
                },
            )
        }
    ) { padding ->
        LazyColumn(
            Modifier.padding(padding).fillMaxSize(),
            contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            val sm = s.summary
            if (sm != null) {
                sm.scorecard?.let { card ->
                    item {
                        Column {
                            Row(verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
                                Text("${card.overall}", style = MaterialTheme.typography.headlineMedium,
                                    color = MaterialTheme.colorScheme.primary)
                                Text("  ·  ${card.cefrLevel?.uppercase().orEmpty()}",
                                    style = MaterialTheme.typography.titleMedium,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                            if (card.topLine.isNotBlank()) {
                                Text(card.topLine, style = MaterialTheme.typography.bodyMedium)
                            }
                        }
                    }
                }
                if (sm.phrasesUsed.isNotEmpty()) {
                    item { SectionHeader(stringResource(R.string.lines_worth_saying_differently)) }
                    items(sm.phrasesUsed.size) { i ->
                        val p = sm.phrasesUsed[i]
                        Column {
                            Text(p.userSaid, style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant)
                            Text(p.fluentAlternative, style = MaterialTheme.typography.bodyLarge,
                                color = MaterialTheme.colorScheme.primary)
                            if (p.reason.isNotBlank()) {
                                Text(p.reason, style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                        }
                    }
                }
                if (sm.expressionsOffered.isNotEmpty()) {
                    item { SectionHeader(stringResource(R.string.new_expressions_from_the_call)) }
                    item {
                        Text(sm.expressionsOffered.joinToString("  ·  "),
                            style = MaterialTheme.typography.bodyLarge)
                    }
                }
                if (sm.grammarIssues.isNotEmpty()) {
                    item { SectionHeader(stringResource(R.string.corrections_worth_keeping)) }
                    items(sm.grammarIssues.size) { i ->
                        val g = sm.grammarIssues[i]
                        Column {
                            Text(g.quote, style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant)
                            Text(g.correction, style = MaterialTheme.typography.bodyLarge)
                            if (g.note.isNotBlank()) {
                                Text(g.note, style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                        }
                    }
                }
                if (sm.overallNote.isNotBlank()) {
                    item {
                        Text(sm.overallNote, style = MaterialTheme.typography.bodyMedium,
                            modifier = Modifier.padding(vertical = 4.dp))
                    }
                }
            }
            item { HorizontalDivider() }
            item { SectionHeader(stringResource(R.string.transcript)) }
            items(s.turns.size) { i ->
                val turn = s.turns[i]
                androidx.compose.foundation.layout.Box(
                    Modifier.fillMaxWidth().then(
                        if (turn.role == TurnRole.FLUENT_SELF)
                            Modifier.clickable { onShadow(turn.transcript) }
                        else Modifier)
                ) { DialogueLine(turn) }
            }
        }
    }
}

@Composable
private fun SectionHeader(title: String) {
    Text(title, style = MaterialTheme.typography.titleMedium,
        modifier = Modifier.padding(top = 8.dp))
}
