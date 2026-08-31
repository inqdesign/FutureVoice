package com.roro.futurevoice.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.background
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
import androidx.compose.material.icons.filled.Abc
import androidx.compose.material.icons.filled.FormatQuote
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.PlayArrow
import com.roro.futurevoice.ui.brand.AppSurfaces
import com.roro.futurevoice.ui.brand.BookmarkTab
import com.roro.futurevoice.ui.brand.BookmarkedPage
import com.roro.futurevoice.ui.brand.DialogueLine
import com.roro.futurevoice.ui.brand.DialogueSpeaker
import com.roro.futurevoice.R
import com.roro.futurevoice.data.BookDocument
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
    var chapter by remember { mutableStateOf(Chapter.SCENE) }
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
                    BookExportMenu { BookDocument.make(context, sc, counterpartName = null) }
                },
            )
        }
    ) { padding ->
        if (cur == null) {
            Text(stringResource(R.string.watch_the_scene_first),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(padding).padding(20.dp))
            return@Scaffold
        }
        // Ribbon bookmarks, not a table of contents: chapters are named by
        // what you DO in them, and the page swaps in place.
        val tabs = listOf(
            BookmarkTab(Chapter.SCENE, Icons.Filled.PlayArrow,
                stringResource(R.string.watch), count = cur.dialogue?.size),
            BookmarkTab(Chapter.WORDS, Icons.Filled.Abc,
                stringResource(R.string.words_d26d55),
                done = wordMastered.size, total = cur.words.size),
            BookmarkTab(Chapter.EXPRESSIONS, Icons.Filled.FormatQuote,
                stringResource(R.string.expressions),
                done = exprMastered.size, total = cur.expressions.size),
            BookmarkTab(Chapter.SHADOW, Icons.Filled.Mic,
                stringResource(R.string.shadowing), count = cur.shadowLines.size),
        )
        BookmarkedPage(
            tabs = tabs, selection = chapter, onSelect = { chapter = it },
            modifier = Modifier.padding(padding).background(AppSurfaces.ground)
                .padding(start = 0.dp, end = 16.dp, top = 8.dp, bottom = 16.dp),
        ) {
            Column(Modifier.padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp)) {
                when (chapter) {
                    Chapter.SCENE -> {
                        cur.dialogueTitle?.let { SectionTitle(it) }
                        cur.dialogue.orEmpty().forEach { turn ->
                            DialogueLine(
                                speaker = if (turn.speaker == "user") DialogueSpeaker.USER
                                else DialogueSpeaker.OTHER,
                                name = if (turn.speaker == "user")
                                    stringResource(R.string.you)
                                else stringResource(R.string.future_self_1384d5),
                            ) { Text(turn.text) }
                        }
                    }
                    Chapter.WORDS -> cur.words.forEach {
                        ItemRow(it, it.id in wordMastered)
                    }
                    Chapter.EXPRESSIONS -> cur.expressions.forEach {
                        ItemRow(it, it.id in exprMastered)
                    }
                    Chapter.SHADOW -> cur.shadowLines.forEach { line ->
                        Row(Modifier.fillMaxWidth().clickable { onShadow(line.text) }
                            .padding(vertical = 4.dp),
                            verticalAlignment = Alignment.CenterVertically) {
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
    }
}

/** The book's chapters — named by what you DO in them. */
private enum class Chapter { SCENE, WORDS, EXPRESSIONS, SHADOW }

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
