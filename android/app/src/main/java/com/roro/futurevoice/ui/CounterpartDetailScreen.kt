package com.roro.futurevoice.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
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
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.roro.futurevoice.R
import com.roro.futurevoice.ui.brand.AppSurfaces
import com.roro.futurevoice.data.Counterpart
import com.roro.futurevoice.data.CounterpartStore
import com.roro.futurevoice.data.PersonaStore
import com.roro.futurevoice.data.ScenarioStore
import com.roro.futurevoice.data.StoreEvents
import com.roro.futurevoice.talk.CounterpartIdeas
import com.roro.futurevoice.talk.Scenario
import com.roro.futurevoice.talk.StockPerson
import kotlinx.coroutines.launch

/**
 * MANAGEMENT page for one of your own people — iOS `CounterpartDetailView`:
 * profile, cached situation ideas, and the scenes made with them. Watching
 * is deliberately NOT launched from here; the one watch flow is the Watch
 * tab's composer, so every scene mints the same Practice book.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CounterpartDetailScreen(
    counterpartId: String,
    language: String,
    onOpenBook: (String) -> Unit,
    onBack: () -> Unit,
) {
    androidx.activity.compose.BackHandler(onBack = onBack)
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val store = remember { CounterpartStore.shared(context) }
    var person by remember { mutableStateOf<Counterpart?>(null) }
    var loaded by remember { mutableStateOf(false) }
    var scenes by remember { mutableStateOf<List<Scenario>>(emptyList()) }
    var editing by remember { mutableStateOf(false) }
    var loadingIdeas by remember { mutableStateOf(false) }
    var ideasError by remember { mutableStateOf<String?>(null) }

    suspend fun reload() {
        person = store.load().firstOrNull { it.id == counterpartId }
        scenes = ScenarioStore.shared(context).load(language)
            .filter { it.counterpartId == counterpartId && it.archivedAt == null }
            .sortedByDescending { it.createdAt }
        loaded = true
    }
    LaunchedEffect(counterpartId, language) { reload() }

    fun regenerate(c: Counterpart) {
        loadingIdeas = true; ideasError = null
        scope.launch {
            runCatching {
                val fresh = CounterpartIdeas.suggest(PersonaStore.shared(context).load(), c, language)
                store.save(c.copy(scenariosByLanguage = c.scenariosByLanguage + (language to fresh)))
                reload(); StoreEvents.bump()
            }.onFailure { ideasError = context.getString(R.string.person_couldnt_refresh_scenarios, it.message ?: "") }
            loadingIdeas = false
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                colors = AppSurfaces.topBarColors(),
                title = { Text(person?.name ?: "") },
                navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = null) } },
                actions = { if (person != null) TextButton(onClick = { editing = true }) { Text(stringResource(R.string.edit)) } },
            )
        }
    ) { padding ->
        val c = person
        if (loaded && c == null) {
            Box(Modifier.padding(padding).fillMaxSize().background(AppSurfaces.ground), contentAlignment = Alignment.Center) {
                Text(stringResource(R.string.this_person_has_been_deleted), color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            return@Scaffold
        }
        if (c == null) return@Scaffold
        val ideas = c.scenariosByLanguage[language].orEmpty()
        Column(Modifier.padding(padding).fillMaxSize().background(AppSurfaces.ground)
            .verticalScroll(rememberScrollState()).padding(horizontal = 20.dp, vertical = 12.dp)) {
            GroupedCard {
                Row(Modifier.fillMaxWidth().padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
                    Box(Modifier.size(48.dp).background(MaterialTheme.colorScheme.primary.copy(alpha = 0.15f), CircleShape), contentAlignment = Alignment.Center) {
                        Text(initials(c.name), style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.primary)
                    }
                    Spacer(Modifier.size(14.dp))
                    Column {
                        Text(c.name, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold)
                        if (c.relationship.isNotEmpty()) Text(c.relationship, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        Text(stringResource(R.string.voiced_by_0ed8e5, StockPerson.by(c.voicePresetId).name),
                            style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.outline)
                    }
                }
            }
            section(stringResource(R.string.about_them), listOf(null to c.location))
            section(stringResource(R.string.your_history_together),
                listOf(stringResource(R.string.person_how_you_met) to c.howWeMet, stringResource(R.string.shared_context) to c.background))
            section(stringResource(R.string.how_they_talk),
                listOf(stringResource(R.string.person_style) to c.conversationStyle, stringResource(R.string.person_common_topics) to c.commonTopics))
            section(stringResource(R.string.person_notes), listOf(null to c.freeNotes))

            GroupedSectionSpacer()
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.weight(1f)) { GroupedSectionHeader(stringResource(R.string.situation_ideas)) }
                if (ideas.isNotEmpty()) {
                    if (loadingIdeas) CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
                    else IconButton(onClick = { regenerate(c) }) { Icon(Icons.Filled.Refresh, contentDescription = stringResource(R.string.refresh)) }
                }
            }
            GroupedCard {
                if (ideas.isEmpty()) {
                    if (loadingIdeas) Row(Modifier.padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
                        CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp); Spacer(Modifier.size(10.dp))
                        Text(stringResource(R.string.building_scenarios_for, c.name), color = MaterialTheme.colorScheme.onSurfaceVariant)
                    } else Text(stringResource(R.string.generate_scenarios_for, c.name), color = MaterialTheme.colorScheme.primary,
                        modifier = Modifier.fillMaxWidth().clickable { regenerate(c) }.padding(16.dp))
                } else ideas.forEachIndexed { i, idea ->
                    if (i > 0) GroupedRowDivider(inset = false)
                    Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp)) {
                        Text(idea.title, style = MaterialTheme.typography.bodyLarge)
                        if (idea.blurb.isNotEmpty()) Text(idea.blurb, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
                ideasError?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error, modifier = Modifier.padding(16.dp)) }
            }
            GroupedFooter(stringResource(R.string.grounded_in_your_relationship_with_these_appear_as_ideas_whe_d659c0, c.name))

            if (scenes.isNotEmpty()) {
                GroupedSectionSpacer()
                GroupedSectionHeader(stringResource(R.string.person_scenes_with_person, c.name))
                GroupedCard {
                    scenes.forEachIndexed { i, s ->
                        if (i > 0) GroupedRowDivider(inset = false)
                        Column(Modifier.fillMaxWidth().clickable { onOpenBook(s.id) }.padding(horizontal = 16.dp, vertical = 12.dp)) {
                            Text(s.environment, style = MaterialTheme.typography.bodyLarge, maxLines = 2)
                            if (s.role.isNotEmpty()) Text(s.role, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                }
            }
        }
    }

    if (editing && person != null) {
        PersonEditor(
            person = person!!,
            onSave = { scope.launch { store.save(it); reload(); StoreEvents.bump() }; editing = false },
            onDismiss = { editing = false },
        )
    }
}

/** A grouped section, drawn only when at least one row has text. */
@Composable
private fun section(title: String, rows: List<Pair<String?, String>>) {
    val shown = rows.map { it.first to it.second.trim() }.filter { it.second.isNotEmpty() }
    if (shown.isEmpty()) return
    GroupedSectionSpacer()
    GroupedSectionHeader(title)
    GroupedCard {
        shown.forEachIndexed { i, (label, text) ->
            if (i > 0) GroupedRowDivider(inset = false)
            Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp)) {
                if (label != null) Text(label, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Text(text, style = MaterialTheme.typography.bodyLarge)
            }
        }
    }
}

internal fun initials(name: String): String =
    name.trim().split(Regex("\\s+")).filter { it.isNotEmpty() }.take(2).joinToString("") { it.take(1).uppercase() }
