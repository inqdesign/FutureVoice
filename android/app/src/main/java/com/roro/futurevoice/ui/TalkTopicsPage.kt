package com.roro.futurevoice.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
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
 * topics live: a call on a topic of your own at the top (it opens by asking
 * what to talk about), then the ideas by category (the same
 * [DiscoverSection] the home drew). Every pick still starts the call through
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

    Scaffold(
        containerColor = AppSurfaces.ground,
        topBar = {
            CenterAlignedTopAppBar(
                colors = AppSurfaces.topBarColors(),
                title = { com.roro.futurevoice.ui.brand.IosNavTitle(stringResource(R.string.topics)) },
                navigationIcon = { com.roro.futurevoice.ui.brand.IosBackButton(onBack) },
            )
        },
    ) { padding ->
        Column(
            Modifier.padding(padding).fillMaxSize().background(AppSurfaces.ground)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp).padding(top = 8.dp),
            verticalArrangement = Arrangement.spacedBy(24.dp),
        ) {
            DoorButton(
                title = stringResource(R.string.my_own_topic),
                subtitle = stringResource(R.string.say_what_you_want_to_talk_about_and_the_call_starts_there),
                onClick = {
                    launchCall(PendingLaunch("", emptyList(), null, entry = TalkEntry.TALK_OWN_TOPIC,
                        ownTopic = true))
                },
            )
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
                )
            }
            Spacer(Modifier.height(24.dp).windowInsetsPadding(WindowInsets.navigationBars))
        }
    }
}

/** The page's "my own topic" tile (iOS `DoorButton`, prominent). */
@Composable
private fun DoorButton(title: String, subtitle: String, onClick: () -> Unit) {
    // TOP-aligned, not centred (iOS): a centred row floats its icon and
    // title down the card when the subtitle wraps.
    Row(
        Modifier.fillMaxWidth().heightIn(min = 72.dp)
            .clip(ContinuousShape(18.dp))
            .background(MaterialTheme.colorScheme.primary.copy(alpha = 0.12f))
            .clickable(onClick = onClick)
            .padding(14.dp),
        verticalAlignment = Alignment.Top,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Icon(Icons.Filled.Mic, contentDescription = null, tint = MaterialTheme.colorScheme.primary,
            modifier = Modifier.size(22.dp))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(title, style = PT.subheadline.copy(fontWeight = FontWeight.SemiBold),
                color = MaterialTheme.colorScheme.onSurface)
            Text(subtitle, style = PT.caption, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}
