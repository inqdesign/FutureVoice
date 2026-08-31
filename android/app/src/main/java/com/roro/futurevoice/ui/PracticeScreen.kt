package com.roro.futurevoice.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.ExperimentalMaterial3Api
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
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.roro.futurevoice.R
import com.roro.futurevoice.data.DrillStore
import com.roro.futurevoice.data.ScenarioStore
import com.roro.futurevoice.data.SessionStore
import com.roro.futurevoice.data.StoreEvents
import com.roro.futurevoice.talk.Scenario
import com.roro.futurevoice.talk.Session

/**
 * Practice — the REVIEW home (`PracticeTab`'s spine): the day's due queue,
 * then the book shelves. Everything here came out of an activity; nothing
 * is born on this screen.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PracticeScreen(
    language: String,
    onOpenDeck: () -> Unit,
    onOpenScenarioBook: (String) -> Unit,
    onOpenTalk: (String) -> Unit,
    onBack: () -> Unit,
) {
    androidx.activity.compose.BackHandler(onBack = onBack)
    val context = LocalContext.current
    val revision by StoreEvents.revision.collectAsStateWithLifecycle()
    var due by remember { mutableStateOf(0) }
    var scenarios by remember { mutableStateOf<List<Scenario>>(emptyList()) }
    var talks by remember { mutableStateOf<List<Session>>(emptyList()) }
    LaunchedEffect(language, revision) {
        due = DrillStore.shared(context).dueCount(language)
        scenarios = ScenarioStore.shared(context).load(language)
            .filter { it.archivedAt == null && it.isMeeting != true }
        talks = SessionStore.shared(context).load(language).filter { it.summary != null }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.practice)) },
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
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            if (due > 0) {
                item {
                    Row(Modifier.fillMaxWidth().clickable { onOpenDeck() }.padding(vertical = 6.dp),
                        verticalAlignment = Alignment.CenterVertically) {
                        Text(stringResource(R.string.review_cards),
                            style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f))
                        Text("$due", style = MaterialTheme.typography.titleMedium,
                            color = MaterialTheme.colorScheme.primary)
                    }
                }
            }
            if (scenarios.isNotEmpty()) {
                item { Text(stringResource(R.string.scenarios),
                    style = MaterialTheme.typography.titleMedium,
                    modifier = Modifier.padding(top = 8.dp)) }
                items(scenarios.size) { i ->
                    val sc = scenarios[i]
                    Column(Modifier.fillMaxWidth().clickable { onOpenScenarioBook(sc.id) }
                        .padding(vertical = 6.dp)) {
                        Text(sc.cardTitle, style = MaterialTheme.typography.bodyLarge)
                        val cur = sc.curriculum
                        Text(
                            if (cur == null) stringResource(R.string.watch_the_scene_first)
                            else stringResource(R.string.lld_of_lld_mastered,
                                cur.words.count { it.masteredAt != null } +
                                    cur.expressions.count { it.masteredAt != null },
                                cur.words.size + cur.expressions.size + cur.shadowLines.size),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
            if (talks.isNotEmpty()) {
                item { Text(stringResource(R.string.talks),
                    style = MaterialTheme.typography.titleMedium,
                    modifier = Modifier.padding(top = 8.dp)) }
                items(talks.size) { i ->
                    val t = talks[i]
                    Column(Modifier.fillMaxWidth().clickable { onOpenTalk(t.id) }
                        .padding(vertical = 6.dp)) {
                        Text(t.displayTitle ?: stringResource(R.string.conversation),
                            style = MaterialTheme.typography.bodyLarge)
                        t.summary?.scorecard?.let {
                            Text("${it.overall} · ${it.cefrLevel?.uppercase().orEmpty()}",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                }
            }
        }
    }
}
