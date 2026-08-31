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
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.outlined.Circle
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
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
import androidx.compose.foundation.layout.size
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.roro.futurevoice.R
import com.roro.futurevoice.data.ScenarioStore
import com.roro.futurevoice.data.StoreEvents
import com.roro.futurevoice.data.VocabStore
import com.roro.futurevoice.talk.Scenario
import com.roro.futurevoice.talk.ScenarioCurriculum

/**
 * A scenario BOOK — `ScenarioDetailView`'s spine: one scene + the material
 * to master. Mastery is DETERMINISTIC and never LLM-judged, riding the
 * app's existing tracking (iOS rule): a word is mastered when it's in the
 * vocab pool, an expression on real evidence (used or "I know it"), a
 * shadow line by a scored attempt (arrives with ShadowAttemptStore).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ScenarioBookScreen(
    scenarioId: String,
    language: String,
    onWatch: (String) -> Unit,
    onShadow: (String) -> Unit,
    onBack: () -> Unit,
) {
    androidx.activity.compose.BackHandler(onBack = onBack)
    val context = LocalContext.current
    val revision by StoreEvents.revision.collectAsStateWithLifecycle()
    var scenario by remember { mutableStateOf<Scenario?>(null) }
    var wordMastered by remember { mutableStateOf<Set<String>>(emptySet()) }
    var exprMastered by remember { mutableStateOf<Set<String>>(emptySet()) }
    LaunchedEffect(scenarioId, revision) {
        val sc = ScenarioStore.shared(context).load(language).firstOrNull { it.id == scenarioId }
        scenario = sc
        val vocab = VocabStore.shared(context)
        val cur = sc?.curriculum
        wordMastered = cur?.words.orEmpty()
            .filter { vocab.isKnownWord(it.text, language) }.map { it.id }.toSet()
        exprMastered = cur?.expressions.orEmpty()
            .filter { vocab.hasUsedExpression(it.text, language) }.map { it.id }.toSet()
    }
    val sc = scenario ?: return
    val cur = sc.curriculum

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(sc.cardTitle) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = null)
                    }
                },
                actions = {
                    TextButton(onClick = { onWatch(sc.id) }) { Text(stringResource(R.string.watch)) }
                },
            )
        }
    ) { padding ->
        LazyColumn(
            Modifier.padding(padding).fillMaxSize(),
            contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            if (cur == null) {
                item {
                    Text(stringResource(R.string.watch_the_scene_first),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                return@LazyColumn
            }
            val mastered = wordMastered.size + exprMastered.size
            val total = cur.words.size + cur.expressions.size + cur.shadowLines.size
            item {
                Column {
                    Text(stringResource(R.string.lld_of_lld_mastered, mastered, total),
                        style = MaterialTheme.typography.titleMedium)
                    LinearProgressIndicator(
                        progress = { if (total == 0) 0f else mastered / total.toFloat() },
                        modifier = Modifier.fillMaxWidth().padding(top = 4.dp))
                }
            }
            cur.dialogueTitle?.let { item { SectionTitle(it) } }
            item { SectionTitle(stringResource(R.string.words_d26d55)) }
            items(cur.words.size) { i ->
                ItemRow(cur.words[i], cur.words[i].id in wordMastered)
            }
            item { SectionTitle(stringResource(R.string.expressions)) }
            items(cur.expressions.size) { i ->
                ItemRow(cur.expressions[i], cur.expressions[i].id in exprMastered)
            }
            item { SectionTitle(stringResource(R.string.shadowing)) }
            items(cur.shadowLines.size) { i ->
                val line = cur.shadowLines[i]
                Row(Modifier.fillMaxWidth().clickable { onShadow(line.text) }
                    .padding(vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Outlined.Circle, contentDescription = null,
                        tint = MaterialTheme.colorScheme.outlineVariant,
                        modifier = Modifier.size(18.dp))
                    Text(line.text, style = MaterialTheme.typography.bodyLarge,
                        modifier = Modifier.padding(start = 10.dp))
                }
            }
        }
    }
}

@Composable
private fun SectionTitle(t: String) {
    Text(t, style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(top = 8.dp))
}

@Composable
private fun ItemRow(item: ScenarioCurriculum.Item, mastered: Boolean) {
    Row(Modifier.fillMaxWidth().padding(vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically) {
        if (mastered) Icon(Icons.Filled.CheckCircle, contentDescription = null,
            tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(18.dp))
        else Icon(Icons.Outlined.Circle, contentDescription = null,
            tint = MaterialTheme.colorScheme.outlineVariant, modifier = Modifier.size(18.dp))
        Column(Modifier.padding(start = 10.dp)) {
            Text(item.text, style = MaterialTheme.typography.bodyLarge)
            if (item.note.isNotBlank()) {
                Text(item.note, style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}
