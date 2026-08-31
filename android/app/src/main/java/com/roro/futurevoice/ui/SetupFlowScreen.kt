package com.roro.futurevoice.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.roro.futurevoice.R
import com.roro.futurevoice.ui.brand.AppSurfaces
import com.roro.futurevoice.data.CefrLevel
import com.roro.futurevoice.data.LanguageCatalog

/**
 * First-run quick-answer setup — `SetupFlowView.swift`, one question per
 * screen, mostly taps: native language → target language → level → daily
 * goal. Native leads (a plain fact, so the first question never reads like a
 * test); the target scopes the level labels (TOPIK for Korean); the goal
 * closes on a commitment the learner chose. Strings come from the shared
 * catalog — nothing here is authored twice.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SetupFlowScreen(
    initialNative: String,
    initialTarget: String,
    initialLevel: CefrLevel,
    onBackToWelcome: () -> Unit,
    onFinish: (native: String, target: String, level: CefrLevel, goalMinutes: Int) -> Unit,
) {
    var step by remember { mutableIntStateOf(0) }
    var native by remember { mutableStateOf(initialNative) }
    var target by remember { mutableStateOf(initialTarget) }
    var level by remember { mutableStateOf(initialLevel) }
    var goal by remember { mutableIntStateOf(10) }

    val targetChoices = LanguageCatalog.selectableTargets.map { it.code }.filter { it != native }
    fun resolveCollision() { if (target == native) target = targetChoices.firstOrNull() ?: "en" }

    Scaffold(
        topBar = {
            TopAppBar(title = {
                Text(stringResource(when (step) {
                    0 -> R.string.your_native_language
                    1 -> R.string.learn_which_language
                    2 -> R.string.your_level_5f68da
                    else -> R.string.your_daily_goal
                }))
            })
        },
        bottomBar = {
            Row(Modifier.fillMaxWidth().padding(16.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                OutlinedButton(
                    onClick = { if (step > 0) step -= 1 else onBackToWelcome() },
                    modifier = Modifier.weight(1f),
                ) { Text(stringResource(R.string.back_b52b36)) }
                Button(
                    onClick = {
                        if (step < 3) { resolveCollision(); step += 1 }
                        else onFinish(native, target, level, goal)
                    },
                    modifier = Modifier.weight(1f),
                ) { Text(stringResource(if (step < 3) R.string.next else R.string.continue_)) }
            }
        },
    ) { padding ->
        Column(Modifier.padding(padding).fillMaxSize().background(AppSurfaces.ground).padding(horizontal = 16.dp)) {
            LinearProgressIndicator(
                progress = { (step + 1) / 4f },
                modifier = Modifier.fillMaxWidth().padding(vertical = 8.dp),
            )
            Text(
                stringResource(when (step) {
                    0 -> R.string.what_s_your_native_language
                    1 -> R.string.which_language_do_you_want_to_speak
                    2 -> R.string.how_comfortable_are_you_right_now
                    else -> R.string.how_much_will_you_talk_each_day
                }),
                style = MaterialTheme.typography.titleMedium,
                modifier = Modifier.padding(vertical = 8.dp),
            )
            when (step) {
                0 -> ChoiceList(LanguageCatalog.nativeChoices(), selected = native,
                    title = { LanguageCatalog.endonym(it) },
                    subtitle = { LanguageCatalog.ownName(it, native) }) { native = it }
                1 -> ChoiceList(targetChoices, selected = target,
                    title = { LanguageCatalog.endonym(it) },
                    subtitle = { LanguageCatalog.ownName(it, native) },
                    footer = stringResource(R.string.your_fluent_self_speaks_this_language_in_your_own_voice_you_0a47cf)) { target = it }
                2 -> ChoiceList(CefrLevel.entries.toList(), selected = level,
                    title = { LanguageCatalog.levelLabel(it, target) },
                    subtitle = { levelBlurb(it) }) { level = it }
                else -> ChoiceList(listOf(5, 10, 15, 20, 30), selected = goal,
                    title = { stringResource(R.string.lld_min_a_day, it) },
                    subtitle = { goalBlurb(it) },
                    footer = stringResource(R.string.your_goal_your_call_the_ring_on_the_talk_screen_fills_toward_377ab2)) { goal = it }
            }
        }
    }
}

@Composable
private fun <T> ChoiceList(
    options: List<T>,
    selected: T,
    title: @Composable (T) -> String,
    subtitle: @Composable (T) -> String,
    footer: String? = null,
    onPick: (T) -> Unit,
) {
    LazyColumn {
        items(options) { option ->
            Row(
                Modifier.fillMaxWidth().clickable { onPick(option) }.padding(vertical = 10.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Column(Modifier.weight(1f)) {
                    Text(title(option), style = MaterialTheme.typography.bodyLarge)
                    Text(subtitle(option), style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                if (option == selected) {
                    Icon(Icons.Filled.Check, contentDescription = null,
                        tint = MaterialTheme.colorScheme.primary)
                }
            }
        }
        footer?.let {
            item {
                Text(it, style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(vertical = 12.dp))
            }
        }
    }
}

@Composable
private fun levelBlurb(level: CefrLevel): String = stringResource(when (level) {
    CefrLevel.A1 -> R.string.just_starting_a_few_words_and_set_phrases
    CefrLevel.A2 -> R.string.basic_simple_everyday_exchanges
    CefrLevel.B1 -> R.string.conversational_i_get_by_on_familiar_topics
    CefrLevel.B2 -> R.string.independent_i_discuss_most_things_with_some_ease
    CefrLevel.C1 -> R.string.advanced_i_express_myself_fluently_and_precisely
    CefrLevel.C2 -> R.string.mastery_effortless_near_native
})

@Composable
private fun goalBlurb(minutes: Int): String = stringResource(when (minutes) {
    5 -> R.string.a_quick_daily_habit_one_short_call
    10 -> R.string.the_sweet_spot_for_steady_progress
    15 -> R.string.building_real_momentum
    20 -> R.string.serious_about_this
    else -> R.string.full_immersion_pace
})
