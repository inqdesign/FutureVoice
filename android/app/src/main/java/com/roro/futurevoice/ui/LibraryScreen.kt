package com.roro.futurevoice.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
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
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.roro.futurevoice.R
import com.roro.futurevoice.data.CefrLevel
import com.roro.futurevoice.data.CoreVocabulary
import com.roro.futurevoice.data.ExpressionCatalog
import com.roro.futurevoice.data.StoreEvents
import com.roro.futurevoice.data.StudyScheduleStore
import com.roro.futurevoice.data.VocabStore
import com.roro.futurevoice.ui.brand.AppSurfaces

/**
 * The Library: everything the app has collected, as a list you can read.
 *
 * The decks DEAL from this material; this is where it can be looked at, and
 * where a widget tap lands. Kept as a plain list rather than iOS's explorable
 * word cloud — the cloud is a visual decision that belongs to whoever is
 * designing the Android look, and shipping an improvised one would settle it
 * by accident.
 *
 * Two states per item, and they mean different things: KEPT is the learner's
 * bookmark (they are still studying it), KNOWN is a retirement. A word they
 * have actually SAID carries its own record and is neither.
 */
enum class LibraryKind { WORDS, EXPRESSIONS }

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LibraryScreen(kind: LibraryKind, language: String, onBack: () -> Unit) {
    androidx.activity.compose.BackHandler(onBack = onBack)
    val context = LocalContext.current
    val revision by StoreEvents.revision.collectAsStateWithLifecycle()
    val vocab = remember { VocabStore.shared(context) }
    var rows by remember { mutableStateOf<List<Row>>(emptyList()) }
    var showKnown by remember { mutableStateOf(false) }

    LaunchedEffect(kind, language, revision, showKnown) {
        val schedule = StudyScheduleStore.shared(context).snapshot(language)
        rows = when (kind) {
            LibraryKind.WORDS -> {
                val studying = vocab.studying(language)
                studying.map { word ->
                    Row(
                        text = word,
                        kept = true,
                        known = vocab.state(word.lowercase(), language) == "known",
                        note = CoreVocabulary.level(word, language)?.code?.uppercase().orEmpty(),
                        returnsAt = schedule.nextReview(StudyScheduleStore.Kind.WORD, word),
                    )
                }
            }
            LibraryKind.EXPRESSIONS ->
                // The MERGED catalog, not the store: a phrase the fluent self
                // used and the learner hasn't said has no record — by design —
                // and reading the store alone dropped exactly the class of
                // expression the library exists to teach.
                ExpressionCatalog.all(context, language).map { item ->
                    Row(
                        text = item.text,
                        kept = item.bookmarked,
                        known = item.known,
                        note = when {
                            item.origin == ExpressionCatalog.Origin.HEARD ->
                                context.getString(R.string.heard_in_a_call)
                            // A count of 1 says nothing — everything here was
                            // met at least once. Only a repeat is worth printing.
                            item.count > 1 -> "×${item.count}"
                            else -> ""
                        },
                        returnsAt = schedule.nextReview(
                            StudyScheduleStore.Kind.EXPRESSION, item.text),
                    )
                }
        }.filter { showKnown || !it.known }
    }

    Scaffold(
        topBar = {
            androidx.compose.material3.TopAppBar(
                title = {
                    Text(stringResource(
                        if (kind == LibraryKind.WORDS) R.string.words_d26d55
                        else R.string.expressions))
                },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = null)
                    }
                },
            )
        }
    ) { padding ->
        LazyColumn(
            Modifier.padding(padding).fillMaxSize().background(AppSurfaces.ground)
                .padding(horizontal = 16.dp),
        ) {
            item {
                FilterChip(
                    selected = showKnown,
                    onClick = { showKnown = !showKnown },
                    label = { Text(stringResource(R.string.show_known)) },
                    modifier = Modifier.padding(vertical = 8.dp),
                )
            }

            if (rows.isEmpty()) {
                item {
                    Text(
                        stringResource(
                            if (kind == LibraryKind.WORDS)
                                R.string.nothing_to_study_yet_have_a_talk_or_watch_a_scene_first
                            else R.string.expressions_from_your_calls_will_collect_here),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        textAlign = TextAlign.Center,
                        modifier = Modifier.fillMaxWidth().padding(30.dp),
                    )
                }
            }

            items(rows, key = { it.text }) { row ->
                LibraryRow(row)
            }
        }
    }
}

private data class Row(
    val text: String,
    val kept: Boolean,
    val known: Boolean,
    val note: String,
    /** When the deck brings it back; null = it is due now. */
    val returnsAt: Long?,
)

@Composable
private fun LibraryRow(row: Row) {
    androidx.compose.foundation.layout.Row(
        Modifier.fillMaxWidth().padding(vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Column(Modifier.weight(1f)) {
            Text(row.text, style = MaterialTheme.typography.bodyLarge)
            val caption = listOfNotNull(
                row.note.takeIf { it.isNotEmpty() },
                if (row.known) stringResource(R.string.known) else null,
            ).joinToString(" · ")
            if (caption.isNotEmpty()) {
                Text(caption, style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}
