package com.roro.futurevoice.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Abc
import androidx.compose.material.icons.filled.FormatQuote
import androidx.compose.material.icons.filled.MenuBook
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.Style
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
import androidx.compose.ui.Alignment
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
import com.roro.futurevoice.ui.brand.AppSurfaces
import com.roro.futurevoice.ui.brand.BookmarkTab
import com.roro.futurevoice.ui.brand.BookmarkedPage
import com.roro.futurevoice.ui.brand.DialogueLine
import com.roro.futurevoice.ui.brand.DisplayFace

/** The Talk book's chapters — the same set iOS opens (`ConversationDetailView`). */
private enum class TalkChapter { INTRO, WORDS, EXPRESSIONS, LINES, CARDS }

/**
 * A finished talk's BOOK. Same object as the Watch book: one ribbon page,
 * chapters named by what you do in them. The overview is the cover — the
 * score, the note, and the transcript underneath.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TalkDetailScreen(
    sessionId: String,
    language: String,
    onBack: () -> Unit,
    onShadow: (String) -> Unit = {},
) {
    androidx.activity.compose.BackHandler(onBack = onBack)
    val context = LocalContext.current
    val revision by StoreEvents.revision.collectAsStateWithLifecycle()
    var session by remember { mutableStateOf<Session?>(null) }
    var chapter by remember { mutableStateOf(TalkChapter.INTRO) }
    LaunchedEffect(sessionId, revision) {
        session = SessionStore.shared(context).load(language).firstOrNull { it.id == sessionId }
    }
    val s = session ?: return
    val sm = s.summary
    val fluentLines = s.turns.filter { it.role == TurnRole.FLUENT_SELF }.map { it.transcript }
    val corrections = sm?.phrasesUsed.orEmpty()
    val grammar = sm?.grammarIssues.orEmpty()

    val tabs = buildList {
        add(BookmarkTab(TalkChapter.INTRO, Icons.Filled.MenuBook, stringResource(R.string.overview)))
        if (!sm?.newWordsUsed.isNullOrEmpty()) {
            add(BookmarkTab(TalkChapter.WORDS, Icons.Filled.Abc,
                stringResource(R.string.words_d26d55), count = sm.newWordsUsed.size))
        }
        val expressions = sm?.expressionsOffered.orEmpty() + sm?.expressionsUsed.orEmpty()
        if (expressions.isNotEmpty()) {
            add(BookmarkTab(TalkChapter.EXPRESSIONS, Icons.Filled.FormatQuote,
                stringResource(R.string.expressions), count = expressions.size))
        }
        if (fluentLines.isNotEmpty()) {
            add(BookmarkTab(TalkChapter.LINES, Icons.Filled.Mic,
                stringResource(R.string.shadow), count = fluentLines.size))
        }
        if (corrections.isNotEmpty() || grammar.isNotEmpty()) {
            add(BookmarkTab(TalkChapter.CARDS, Icons.Filled.Style,
                stringResource(R.string.drill), count = corrections.size + grammar.size))
        }
    }

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
        BookmarkedPage(
            tabs = tabs,
            selection = if (tabs.any { it.id == chapter }) chapter else TalkChapter.INTRO,
            onSelect = { chapter = it },
            modifier = Modifier.padding(padding).background(AppSurfaces.ground)
                .padding(end = 16.dp, top = 8.dp, bottom = 16.dp),
        ) {
            Column(Modifier.fillMaxWidth()) {
                when (if (tabs.any { it.id == chapter }) chapter else TalkChapter.INTRO) {
                    TalkChapter.INTRO -> {
                        Column(Modifier.padding(20.dp),
                            verticalArrangement = Arrangement.spacedBy(10.dp)) {
                            sm?.scorecard?.let { card ->
                                Row(verticalAlignment = Alignment.CenterVertically) {
                                    val overall = "${card.overall}"
                                    Text(overall,
                                        style = DisplayFace.style(overall,
                                            MaterialTheme.typography.displaySmall),
                                        color = MaterialTheme.colorScheme.primary)
                                    Text("  ${card.cefrLevel?.uppercase().orEmpty()}",
                                        style = MaterialTheme.typography.titleMedium,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                                }
                                if (card.topLine.isNotBlank()) Text(card.topLine)
                            }
                            sm?.overallNote?.takeIf { it.isNotBlank() }?.let {
                                Text(it, style = MaterialTheme.typography.bodyMedium)
                            }
                            HorizontalDivider(Modifier.padding(vertical = 6.dp))
                            PageTitle(stringResource(R.string.transcript))
                        }
                        Column(Modifier.padding(horizontal = 20.dp),
                            verticalArrangement = Arrangement.spacedBy(12.dp)) {
                            s.turns.forEach { DialogueLine(it) }
                        }
                    }

                    TalkChapter.WORDS -> {
                        PageTitle(stringResource(R.string.words_d26d55))
                        Column(Modifier.padding(horizontal = 20.dp)) {
                            sm?.newWordsUsed.orEmpty().forEach {
                                Text(it, style = MaterialTheme.typography.bodyLarge,
                                    modifier = Modifier.padding(vertical = 5.dp))
                            }
                        }
                    }

                    TalkChapter.EXPRESSIONS -> {
                        PageTitle(stringResource(R.string.expressions))
                        Column(Modifier.padding(horizontal = 20.dp),
                            verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            // Offered ABOVE used: a book exists to teach what
                            // you can't say yet (iOS ordering).
                            sm?.expressionsOffered.orEmpty().forEach {
                                Text(it, style = MaterialTheme.typography.bodyLarge)
                            }
                            if (!sm?.expressionsUsed.isNullOrEmpty()) {
                                HorizontalDivider(Modifier.padding(vertical = 4.dp))
                                sm.expressionsUsed.forEach {
                                    Text(it, style = MaterialTheme.typography.bodyLarge,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                                }
                            }
                        }
                        PageFooter(stringResource(
                            R.string.the_reusable_phrases_this_talk_produced_the_ones_your_fluent_1940be))
                    }

                    TalkChapter.LINES -> {
                        PageTitle(stringResource(R.string.shadow))
                        Column(Modifier.padding(horizontal = 20.dp)) {
                            fluentLines.forEach { line ->
                                Text(line, style = MaterialTheme.typography.bodyLarge,
                                    modifier = Modifier.fillMaxWidth()
                                        .clickable { onShadow(line) }.padding(vertical = 8.dp))
                            }
                        }
                        PageFooter(stringResource(R.string.repeat_your_fluent_self_s_lines_from_this_talk))
                    }

                    TalkChapter.CARDS -> {
                        PageTitle(stringResource(R.string.drill))
                        Column(Modifier.padding(horizontal = 20.dp),
                            verticalArrangement = Arrangement.spacedBy(12.dp)) {
                            corrections.forEach { p ->
                                Column {
                                    Text(p.userSaid, style = MaterialTheme.typography.bodyMedium,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                                    Text(p.fluentAlternative,
                                        style = MaterialTheme.typography.bodyLarge,
                                        color = MaterialTheme.colorScheme.primary)
                                    if (p.reason.isNotBlank()) {
                                        Text(p.reason, style = MaterialTheme.typography.bodySmall,
                                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                                    }
                                }
                            }
                            grammar.forEach { g ->
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
                    }
                }
            }
        }
    }
}

@Composable
private fun PageTitle(title: String) {
    Text(title, style = MaterialTheme.typography.titleMedium,
        modifier = Modifier.padding(horizontal = 20.dp).padding(top = 18.dp, bottom = 6.dp))
}

@Composable
private fun PageFooter(text: String) {
    Text(text, style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.padding(horizontal = 20.dp).padding(top = 10.dp, bottom = 6.dp))
}
