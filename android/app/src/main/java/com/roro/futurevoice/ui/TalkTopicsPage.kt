package com.roro.futurevoice.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.Tune
import androidx.compose.material3.IconButton
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.roro.futurevoice.R
import com.roro.futurevoice.talk.Scenario
import com.roro.futurevoice.talk.TalkEntry
import com.roro.futurevoice.ui.brand.AppSurfaces
import com.roro.futurevoice.ui.brand.ContinuousShape

/**
 * What to talk about, behind ONE door on the Talk home (iOS `TalkTopicsPage`,
 * deed6cf4, 2026-10-18). The home used to carry the whole discover block —
 * a chip row per purpose over a list of cards — under the ring, which made
 * the launcher a feed. Now the home has one button and this page is where
 * topics live: the ideas by category (the same [DiscoverSection] the home
 * drew), with a call on a topic of your own floating at the bottom (it opens
 * by asking what to talk about; iOS b43a5282). Every pick still starts the call through
 * the root's own launch, so nothing about a launch changed.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun TalkTopicsPage(
    state: AppState,
    onBack: () -> Unit,
    onStartCall: (topic: String, newsFacts: List<String>, scenarioId: String?, entry: String) -> Unit,
    onStartStarter: (Scenario, entry: String) -> Unit,
    onStartTopic: (topic: String, blurb: String, entry: String) -> Unit,
    /** A call that opens by asking what to talk about. */
    onStartOwnTopic: () -> Unit,
    onSavePersona: (com.roro.futurevoice.talk.UserPersona) -> Unit,
    onAllScenarios: () -> Unit,
) {
    val launchCall = rememberCallLauncher(onStartCall, onStartStarter, onStartTopic, onStartOwnTopic)
    fun launch(topic: String, facts: List<String>, scenarioId: String? = null, mint: Scenario? = null,
               blurb: String = "", entry: String) =
        launchCall(PendingLaunch(topic, facts, scenarioId, mint, blurb, entry))

    /** The ideas' settings (chips, exam, interests), from the page header
     *  (iOS b43a5282). */
    var showingSettings by remember { mutableStateOf(false) }

    Scaffold(
        containerColor = AppSurfaces.ground,
        topBar = {
            CenterAlignedTopAppBar(
                colors = AppSurfaces.topBarColors(),
                title = { com.roro.futurevoice.ui.brand.IosNavTitle(stringResource(R.string.topics)) },
                navigationIcon = { com.roro.futurevoice.ui.brand.IosBackButton(onBack) },
                actions = {
                    IconButton(onClick = { showingSettings = true }) {
                        Icon(Icons.Filled.Tune, contentDescription = stringResource(R.string.talk_settings),
                            tint = MaterialTheme.colorScheme.primary)
                    }
                },
            )
        },
    ) { padding ->
        Box(Modifier.padding(padding).fillMaxSize()) {
            Column(
                Modifier.fillMaxSize().background(AppSurfaces.ground)
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = 20.dp).padding(top = 8.dp),
                verticalArrangement = Arrangement.spacedBy(24.dp),
            ) {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text(stringResource(R.string.ideas), style = PT.title3.copy(fontWeight = FontWeight.SemiBold),
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                    DiscoverSection(
                        state = state,
                        enabled = state.voiceId != null,
                        onSavePersona = onSavePersona,
                        onPickNews = { topic -> launch(topic.title, topic.facts.orEmpty(), entry = TalkEntry.TALK_NEWS) },
                        onPickScenario = { sc -> launch(sc.promptBlurb, emptyList(), sc.id, entry = TalkEntry.TALK_SCENARIO) },
                        onPickStarter = { sc -> launch(sc.promptBlurb, emptyList(), sc.id, mint = sc, entry = TalkEntry.TALK_SCENARIO) },
                        // An ordinary topic call: the blurb tells it which exam and
                        // which part (iOS `runExam`).
                        onPickExam = { t, exam -> launch(t.title, emptyList(), blurb = t.callBlurb(exam), entry = TalkEntry.TALK_EXAM) },
                        onPickTopic = { t -> launch(t.title, emptyList(), blurb = t.blurb, entry = TalkEntry.TALK_FIELD) },
                        onAllScenarios = onAllScenarios,
                        showingSettings = showingSettings,
                        onShowingSettings = { showingSettings = it },
                    )
                }
                // Room for the floating button over the list's end.
                Spacer(Modifier.height(96.dp).windowInsetsPadding(WindowInsets.navigationBars))
            }
            // "My own topic" floats at the bottom, drawn like the home's "Find
            // a topic", and the list dissolves under it (iOS `fadingBottomBar`).
            Box(Modifier.align(Alignment.BottomCenter).fillMaxWidth(), contentAlignment = Alignment.BottomCenter) {
                ScrollEdgeFeather(color = AppSurfaces.ground, ramp = 40.dp, solid = 36.dp)
                com.roro.futurevoice.ui.brand.IosGlassButton(
                    onClick = {
                        launchCall(PendingLaunch("", emptyList(), null, entry = TalkEntry.TALK_OWN_TOPIC,
                            ownTopic = true))
                    },
                    modifier = Modifier.windowInsetsPadding(WindowInsets.navigationBars)
                        .padding(16.dp).height(50.dp),
                ) {
                    Icon(Icons.Filled.Mic, contentDescription = null,
                        tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(20.dp))
                    Spacer(Modifier.width(8.dp))
                    Text(stringResource(R.string.my_own_topic), style = MaterialTheme.typography.bodyLarge,
                        fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.primary,
                        maxLines = 1)
                }
            }
        }
    }
}
