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
    /**
     * Called the moment a native language is tapped, not at the end. This
     * screen IS the language picker, and the pick used to sit in its own
     * state until `onFinish` — so tapping 日本語 left every word around it in
     * the old language, and the learner answered the remaining questions in
     * the language they had just said they cannot read (iOS `19436f8`).
     */
    onPickNative: (String) -> Unit = {},
    onFinish: (native: String, target: String, level: CefrLevel, goalMinutes: Int) -> Unit,
) {
    // The screen speaks the language under the finger. Overriding the locale
    // for this subtree beats recreating the activity, which would throw away
    // the answers already given.
    val base = androidx.compose.ui.platform.LocalContext.current
    var native0 by remember { mutableStateOf(initialNative) }
    val localized = remember(native0) { com.roro.futurevoice.core.UILanguage.contextFor(base, native0) }
    androidx.compose.runtime.CompositionLocalProvider(
        androidx.compose.ui.platform.LocalContext provides localized,
        androidx.compose.ui.platform.LocalConfiguration provides localized.resources.configuration,
    ) {
        SetupFlowBody(
            initialNative = initialNative, initialTarget = initialTarget,
            initialLevel = initialLevel, onBackToWelcome = onBackToWelcome,
            onPickNative = { native0 = it; onPickNative(it) }, onFinish = onFinish)
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SetupFlowBody(
    initialNative: String,
    initialTarget: String,
    initialLevel: CefrLevel,
    onBackToWelcome: () -> Unit,
    onPickNative: (String) -> Unit,
    onFinish: (native: String, target: String, level: CefrLevel, goalMinutes: Int) -> Unit,
) {
    var step by remember { mutableIntStateOf(0) }
    var native by remember { mutableStateOf(initialNative) }
    // Practice targets on offer — ALL of them. The language picked on the
    // first step is the APP language, and learning the language the app is
    // set to is immersion, which Me → App language has always allowed;
    // filtering it made the result depend on the order things were set in
    // (iOS `ae2a0c5`). Only the PRE-selection avoids it.
    val targetChoices = LanguageCatalog.selectableTargets.map { it.code }
    fun defaultTarget(nativeCode: String): String =
        targetChoices.firstOrNull { !LanguageCatalog.sameLanguage(it, nativeCode) } ?: "en"
    var target by remember {
        mutableStateOf(if (LanguageCatalog.sameLanguage(initialTarget, initialNative))
            defaultTarget(initialNative) else initialTarget)
    }
    /** Set once the learner taps a target — from then on a match with the app
     *  language is their choice, not a default to move. */
    var targetPickedByHand by remember { mutableStateOf(false) }
    var level by remember { mutableStateOf(initialLevel) }
    var goal by remember { mutableIntStateOf(10) }

    /** Leaving the language step: move a pre-selection that now matches the
     *  app language. Leaving the target step with it is the learner's own
     *  choice and stands. */
    fun resolveCollision() {
        if (step == 0 && !targetPickedByHand && LanguageCatalog.sameLanguage(target, native))
            target = defaultTarget(native)
    }

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
            Row(Modifier.fillMaxWidth().bottomBarInsets().padding(16.dp),
                horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                OutlinedButton(
                    onClick = { if (step > 0) step -= 1 else onBackToWelcome() },
                    modifier = Modifier.weight(1f),
                ) { Text(stringResource(R.string.back)) }
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
            // Step 0 asks its question as the first section's HEADER, because
            // it has two sections and each needs its own — repeating it above
            // them said the same thing twice.
            if (step > 0) {
                Text(
                    stringResource(when (step) {
                        1 -> R.string.which_language_do_you_want_to_speak
                        2 -> R.string.how_comfortable_are_you_right_now
                        else -> R.string.how_much_will_you_talk_each_day
                    }),
                    style = MaterialTheme.typography.titleMedium,
                    modifier = Modifier.padding(vertical = 8.dp),
                )
            }
            when (step) {
                // Two groups, not one flat list of sixty-six: a handful of
                // languages are translated end to end and the rest only get
                // the coaching text. Picking Vietnamese from a single list
                // chose an English app without saying so, and the caveat has
                // to be readable BEFORE the tap.
                0 -> {
                    val groups = remember { LanguageCatalog.nativeGroups() }
                    ChoiceList(groups.translated, selected = native,
                        title = { LanguageCatalog.endonym(it) },
                        subtitle = { LanguageCatalog.ownName(it, native) },
                        footer = stringResource(R.string.everything_you_read_in_the_app),
                        header = stringResource(R.string.what_s_your_native_language),
                        more = groups.coachingOnly,
                        moreHeader = stringResource(R.string.corrections_and_notes_only),
                        moreFooter = stringResource(
                            R.string.your_corrections_notes_and_word_meanings_come_back_in_this_l_95bb21),
                    ) { native = it; onPickNative(it) }
                }
                1 -> ChoiceList(targetChoices, selected = target,
                    title = { LanguageCatalog.endonym(it) },
                    subtitle = { LanguageCatalog.ownName(it, native) },
                    footer = stringResource(R.string.your_fluent_self_speaks_this_language_in_your_own_voice_you_0a47cf)) {
                    target = it
                    targetPickedByHand = true
                }
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
    header: String? = null,
    /** A SECOND group under its own header — what a choice buys can differ
     *  inside one question, and the difference belongs beside the rows. */
    more: List<T> = emptyList(),
    moreHeader: String? = null,
    moreFooter: String? = null,
    onPick: (T) -> Unit,
) {
    LazyColumn {
        header?.let { item { GroupedSectionHeader(it) } }
        item {
            GroupedCard {
                options.forEachIndexed { i, option ->
                    if (i > 0) GroupedRowDivider()
                    ChoiceRow(title(option), subtitle(option), option == selected) { onPick(option) }
                }
            }
        }
        footer?.let { item { GroupedFooter(it) } }
        if (more.isNotEmpty()) {
            item { GroupedSectionSpacer() }
            moreHeader?.let { item { GroupedSectionHeader(it) } }
            item {
                GroupedCard {
                    more.forEachIndexed { i, option ->
                        if (i > 0) GroupedRowDivider()
                        ChoiceRow(title(option), subtitle(option), option == selected) { onPick(option) }
                    }
                }
            }
            moreFooter?.let { item { GroupedFooter(it) } }
        }
        item { Spacer(Modifier.padding(vertical = 12.dp)) }
    }
}

@Composable
private fun ChoiceRow(title: String, subtitle: String, selected: Boolean, onPick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().clickable { onPick() }
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.bodyLarge)
            Text(subtitle, style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        if (selected) {
            Icon(Icons.Filled.Check, contentDescription = null,
                tint = MaterialTheme.colorScheme.primary)
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
