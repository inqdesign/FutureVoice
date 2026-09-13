package com.roro.futurevoice.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Bookmark
import androidx.compose.material.icons.outlined.BookmarkBorder
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
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.roro.futurevoice.R
import com.roro.futurevoice.data.SavedLine
import com.roro.futurevoice.data.SavedLineStore
import com.roro.futurevoice.data.SessionStore
import com.roro.futurevoice.data.StoreEvents
import com.roro.futurevoice.talk.Session
import com.roro.futurevoice.talk.Turn
import com.roro.futurevoice.talk.TurnRole
import com.roro.futurevoice.ui.brand.AppSurfaces
import kotlinx.coroutines.launch
import java.text.DateFormat
import java.util.Date

/**
 * Every line the fluent self has said, talk by talk, newest first — the
 * BROWSER behind the Shadowing tile's dealt hand. Tap a line to shadow it;
 * the bookmark keeps it in the personal archive (`SavedLineStore`), which
 * heads the list so a kept line is one scroll from the top.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ShadowBrowserScreen(language: String, onShadow: (Turn) -> Unit, onBack: () -> Unit) {
    androidx.activity.compose.BackHandler(onBack = onBack)
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val revision by StoreEvents.revision.collectAsStateWithLifecycle()
    var sessions by remember { mutableStateOf<List<Session>>(emptyList()) }
    var saved by remember { mutableStateOf<List<SavedLine>>(emptyList()) }
    val store = remember { SavedLineStore.shared(context) }
    LaunchedEffect(language, revision) {
        sessions = SessionStore.shared(context).load(language)
            .filter { it.endedAt != null }
            .sortedByDescending { it.endedAt ?: it.startedAt }
        saved = store.load()
    }
    val savedIds = saved.map { it.id }.toSet()
    val df = remember { DateFormat.getDateInstance(DateFormat.MEDIUM) }

    Scaffold(
        topBar = {
            TopAppBar(
                colors = AppSurfaces.topBarColors(),
                title = { Text(stringResource(R.string.shadow)) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = null)
                    }
                },
            )
        }
    ) { padding ->
        LazyColumn(Modifier.padding(padding).fillMaxSize().background(AppSurfaces.ground)) {
            if (saved.isNotEmpty()) {
                item { Header(stringResource(R.string.saved)) }
                items(saved.size) { i ->
                    val l = saved[i]
                    LineRow(text = l.text, source = l.source, isSaved = true,
                        onTap = { onShadow(Turn(id = l.id, role = TurnRole.FLUENT_SELF, transcript = l.text, timestamp = l.savedAt)) },
                        onToggle = { scope.launch { store.delete(l.id) } })
                }
            }
            if (sessions.isEmpty() && saved.isEmpty()) {
                item {
                    Text(stringResource(R.string.have_a_conversation_or_watch_a_scene_then_come_back_to_shado_9066e7),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(20.dp))
                }
            }
            sessions.forEach { s ->
                val lines = s.turns.filter { it.role == TurnRole.FLUENT_SELF && it.transcript.isNotBlank() }
                if (lines.isEmpty()) return@forEach
                val title = s.topic?.takeIf { it.isNotBlank() } ?: stringResource(R.string.free_talk)
                item { Header("$title · ${df.format(Date(s.endedAt ?: s.startedAt))}") }
                items(lines.size) { i ->
                    val t = lines[i]
                    LineRow(text = t.transcript, source = "", isSaved = t.id in savedIds,
                        onTap = { onShadow(t) },
                        onToggle = { scope.launch { store.toggle(SavedLine(id = t.id, text = t.transcript, source = s.topic.orEmpty())) } })
                }
            }
        }
    }
}

@Composable
private fun Header(text: String) {
    Text(text.uppercase(), style = MaterialTheme.typography.labelSmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.padding(start = 20.dp, top = 18.dp, bottom = 6.dp))
}

@Composable
private fun LineRow(text: String, source: String, isSaved: Boolean, onTap: () -> Unit, onToggle: () -> Unit) {
    Column {
        Row(
            Modifier.fillMaxWidth().clickable(onClick = onTap).padding(start = 20.dp, end = 6.dp, top = 8.dp, bottom = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(text, style = MaterialTheme.typography.bodyLarge)
                if (source.isNotBlank()) Text(source, style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            IconButton(onClick = onToggle) {
                Icon(if (isSaved) Icons.Filled.Bookmark else Icons.Outlined.BookmarkBorder,
                    contentDescription = stringResource(if (isSaved) R.string.unsave else R.string.save),
                    modifier = Modifier.size(20.dp),
                    tint = if (isSaved) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        HorizontalDivider(Modifier.padding(start = 20.dp), color = MaterialTheme.colorScheme.outlineVariant)
    }
}
