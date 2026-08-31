package com.roro.futurevoice.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
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
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.roro.futurevoice.R
import com.roro.futurevoice.data.DrillStore
import com.roro.futurevoice.ui.brand.BookCard
import com.roro.futurevoice.ui.brand.Books
import com.roro.futurevoice.data.ScenarioStore
import com.roro.futurevoice.data.SessionStore
import com.roro.futurevoice.data.StoreEvents
import com.roro.futurevoice.data.TalkTimeLog
import com.roro.futurevoice.talk.Scenario
import com.roro.futurevoice.talk.Session

/**
 * Practice — the REVIEW home (`PracticeTab`'s spine): the day's due queue,
 * then the book shelves. Everything here came out of an activity; nothing is
 * born on this screen. Hosted by the tab shell, so no Scaffold of its own.
 */
@Composable
fun PracticeBody(
    language: String,
    onOpenDeck: () -> Unit,
    onOpenScenarioBook: (String) -> Unit,
    onOpenTalk: (String) -> Unit,
) {
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

    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        if (due > 0) {
            Row(Modifier.fillMaxWidth().clickable { onOpenDeck() }.padding(vertical = 6.dp),
                verticalAlignment = Alignment.CenterVertically) {
                Text(stringResource(R.string.review_cards),
                    style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f))
                Text("$due", style = MaterialTheme.typography.titleMedium,
                    color = MaterialTheme.colorScheme.primary)
            }
        }
        if (scenarios.isNotEmpty()) {
            Text(stringResource(R.string.scenarios), style = MaterialTheme.typography.titleMedium,
                modifier = Modifier.padding(top = 8.dp))
            scenarios.forEach { sc ->
                val cur = sc.curriculum
                val total = cur?.let { it.words.size + it.expressions.size + it.shadowLines.size } ?: 0
                val done = cur?.let {
                    it.words.count { w -> w.masteredAt != null } +
                        it.expressions.count { e -> e.masteredAt != null }
                } ?: 0
                BookCard(
                    title = sc.cardTitle,
                    origin = sc.category,
                    accent = Books.scenarios,
                    detail = if (cur == null) stringResource(R.string.watch_the_scene_first)
                    else stringResource(R.string.lld_of_lld_mastered, done, total),
                    progress = if (total == 0) null else done / total.toFloat(),
                    onClick = { onOpenScenarioBook(sc.id) },
                    modifier = Modifier.padding(vertical = 4.dp),
                )
            }
        }
        if (talks.isNotEmpty()) {
            Text(stringResource(R.string.talks), style = MaterialTheme.typography.titleMedium,
                modifier = Modifier.padding(top = 8.dp))
            talks.forEach { t ->
                BookCard(
                    title = t.displayTitle ?: stringResource(R.string.conversation),
                    origin = when (t.origin?.name?.lowercase()) {
                        "news" -> stringResource(R.string.news)
                        "scenario" -> stringResource(R.string.scenarios)
                        else -> stringResource(R.string.free_talk)
                    },
                    accent = if (t.origin?.name?.lowercase() == "news") Books.topics else Books.talks,
                    detail = t.summary?.scorecard?.let {
                        "${it.overall} · ${it.cefrLevel?.uppercase().orEmpty()}"
                    },
                    onClick = { onOpenTalk(t.id) },
                    modifier = Modifier.padding(vertical = 4.dp),
                )
            }
        }
    }
}

/**
 * Progress — measured, never guessed: the CEFR read comes from the talks
 * themselves (the summary's holistic estimate), the minutes from the meter.
 * The per-skill pages and the 14-day rep bars arrive with the Progress pass.
 */
@Composable
fun ProgressBody(language: String) {
    val context = LocalContext.current
    val revision by StoreEvents.revision.collectAsStateWithLifecycle()
    var talks by remember { mutableStateOf<List<Session>>(emptyList()) }
    var todaySeconds by remember { mutableStateOf(0) }
    LaunchedEffect(language, revision) {
        talks = SessionStore.shared(context).load(language)
        todaySeconds = TalkTimeLog.secondsToday(context)
    }
    val scored = talks.mapNotNull { it.summary?.scorecard }
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        scored.firstOrNull()?.let { card ->
            Column {
                val level = card.cefrLevel?.uppercase().orEmpty()
                Text(level,
                    style = com.roro.futurevoice.ui.brand.DisplayFace
                        .style(level, MaterialTheme.typography.displaySmall),
                    color = MaterialTheme.colorScheme.primary)
                Text(stringResource(R.string.a_level_measured_not_guessed),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(24.dp)) {
            Stat(stringResource(R.string.today), "${todaySeconds / 60}")
            Stat(stringResource(R.string.talks), "${talks.count { it.endedAt != null }}")
            if (scored.isNotEmpty()) {
                Stat(stringResource(R.string.overall), "${scored.map { it.overall }.average().toInt()}")
            }
        }
    }
}

@Composable
private fun Stat(label: String, value: String) {
    Column {
        Text(value, style = MaterialTheme.typography.headlineMedium)
        Text(label, style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}
