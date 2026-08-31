package com.roro.futurevoice.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.roro.futurevoice.R
import com.roro.futurevoice.data.LanguageCatalog
import com.roro.futurevoice.talk.UserPersona

/**
 * First-run persona collection — `PersonaIntakeView`, four light cards only:
 * name, home, and the two chip picks (interests feed the news rail,
 * situations steer scenario suggestions). The narrative answers are
 * deliberately NOT asked here; the first talk works generic-but-warm.
 * Chip VALUES stay English on purpose (they are prompt material and the
 * selection match key); only labels would localize.
 */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun PersonaIntakeScreen(
    initial: UserPersona,
    targetLanguage: String,
    nativeLanguage: String,
    onBackToSetup: () -> Unit,
    onFinish: (UserPersona) -> Unit,
) {
    var step by remember { mutableIntStateOf(0) }
    androidx.activity.compose.BackHandler { if (step > 0) step -= 1 else onBackToSetup() }
    var name by remember { mutableStateOf(initial.displayName) }
    var city by remember { mutableStateOf(initial.city) }
    var country by remember { mutableStateOf(initial.country) }
    var stay by remember { mutableStateOf(initial.lengthOfStay) }
    var interests by remember { mutableStateOf(initial.interests.toSet()) }
    var situations by remember { mutableStateOf(initial.situations.toSet()) }

    val canAdvance = when (step) {
        0 -> name.isNotBlank()
        1 -> city.isNotBlank()
        else -> true
    }

    Scaffold(
        topBar = { TopAppBar(title = { Text(stringResource(R.string.about_you)) }) },
        bottomBar = {
            Row(Modifier.fillMaxWidth().padding(16.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                OutlinedButton(
                    onClick = { if (step > 0) step -= 1 else onBackToSetup() },
                    modifier = Modifier.weight(1f),
                ) { Text(stringResource(R.string.back_b52b36)) }
                Button(
                    enabled = canAdvance,
                    onClick = {
                        if (step < 3) step += 1
                        else onFinish(initial.copy(
                            displayName = name.trim(), city = city.trim(),
                            country = country.trim(), lengthOfStay = stay.trim(),
                            interests = interests.toList(), situations = situations.toList(),
                        ))
                    },
                    modifier = Modifier.weight(1f),
                ) { Text(stringResource(R.string.next)) }
            }
        },
    ) { padding ->
        Column(
            Modifier.padding(padding).fillMaxSize().padding(16.dp).verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            LinearProgressIndicator(progress = { (step + 1) / 4f }, modifier = Modifier.fillMaxWidth())
            when (step) {
                0 -> {
                    Header(stringResource(R.string.what_should_i_call_you),
                        stringResource(R.string.we_re_building_your_fluent_self_it_ll_speak_in_your_own_voic_e7ccbb))
                    OutlinedTextField(value = name, onValueChange = { name = it },
                        label = { Text(stringResource(R.string.your_name)) },
                        singleLine = true, modifier = Modifier.fillMaxWidth())
                }
                1 -> {
                    Header(stringResource(R.string.where_s_home_these_days),
                        stringResource(R.string.real_places_make_your_conversations_concrete_no_small_talk_a_d2fe54))
                    OutlinedTextField(value = city, onValueChange = { city = it },
                        label = { Text(stringResource(R.string.city)) },
                        singleLine = true, modifier = Modifier.fillMaxWidth())
                    OutlinedTextField(value = country, onValueChange = { country = it },
                        label = { Text(stringResource(R.string.country)) },
                        singleLine = true, modifier = Modifier.fillMaxWidth())
                    OutlinedTextField(value = stay, onValueChange = { stay = it },
                        label = { Text(stringResource(R.string.how_long_have_you_been_there_optional)) },
                        singleLine = true, modifier = Modifier.fillMaxWidth())
                }
                2 -> {
                    Header(stringResource(R.string.what_are_you_into),
                        stringResource(R.string.tap_what_fits_these_pick_your_news_stories_and_fuel_conversa_369fbd))
                    ChipGrid(INTEREST_PRESETS, interests) { tag ->
                        interests = if (tag in interests) interests - tag else interests + tag
                    }
                }
                else -> {
                    Header(stringResource(R.string.what_do_you_want_to_be_able_to_do_in,
                        LanguageCatalog.ownName(targetLanguage, nativeLanguage)),
                        stringResource(R.string.what_you_pick_becomes_your_goal_practice_aims_at_it))
                    ChipGrid(SITUATION_PRESETS, situations) { tag ->
                        situations = if (tag in situations) situations - tag else situations + tag
                    }
                }
            }
        }
    }
}

@Composable
private fun Header(question: String, detail: String) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(question, style = MaterialTheme.typography.titleMedium)
        Text(detail, style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun ChipGrid(presets: List<String>, selection: Set<String>, onToggle: (String) -> Unit) {
    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        presets.forEach { tag ->
            FilterChip(selected = tag in selection, onClick = { onToggle(tag) },
                label = { Text(tag) })
        }
    }
}

// `PersonaOnboardingView` presets — stored values stay English (prompt
// material + selection keys); localizing them would un-select saved chips.
private val INTEREST_PRESETS = listOf(
    "AI / tech", "parenting", "language learning", "music", "podcasts",
    "cooking", "travel", "sports", "fashion", "finance", "science", "art",
)
private val SITUATION_PRESETS = listOf(
    "Work meetings", "Client calls", "Kita / school",
    "Doctor / clinic", "Travel", "Online shopping",
    "Customer service", "Streaming / shows", "Reading articles",
    "Daily small talk",
)
