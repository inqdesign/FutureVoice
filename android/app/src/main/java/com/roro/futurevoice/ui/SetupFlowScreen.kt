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
import com.roro.futurevoice.ui.brand.IosButton as Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import com.roro.futurevoice.ui.brand.IosOutlinedButton as OutlinedButton
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
 * screen, mostly taps: native language → target language → (accent) →
 * level → daily goal. The accent step shows only where the target has
 * accents to pick (English): the voice is remixed into it right after the
 * clone, so the pick costs nothing more (iOS 2026-10-08 — before, every
 * English clone was made American and a British learner paid for a second
 * remix to get theirs). Native leads (a plain fact, so the first question never reads like a
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
    /** A real account is behind the session — going back to Welcome then
     *  means signing out, so it is confirmed first (iOS). */
    signedIn: Boolean = false,
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
            initialLevel = initialLevel, signedIn = signedIn, onBackToWelcome = onBackToWelcome,
            onPickNative = { native0 = it; onPickNative(it) }, onFinish = onFinish)
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SetupFlowBody(
    initialNative: String,
    initialTarget: String,
    initialLevel: CefrLevel,
    signedIn: Boolean,
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
    /** The accent picked on the accent step — null until the target has one. */
    var accentId by remember { mutableStateOf<String?>(null) }
    /** The accent step exists only where there is a choice to make. */
    val accentOptions = com.roro.futurevoice.data.VoiceAccentCatalog.options(target)
    val steps = if (accentOptions.size > 1)
        listOf(SetupStep.NATIVE, SetupStep.TARGET, SetupStep.ACCENT, SetupStep.LEVEL, SetupStep.GOAL)
    else listOf(SetupStep.NATIVE, SetupStep.TARGET, SetupStep.LEVEL, SetupStep.GOAL)
    val current = steps[step.coerceAtMost(steps.size - 1)]
    // Same key the Talk home ring and Me's picker read — the ring's 100%.
    val goalContext = androidx.compose.ui.platform.LocalContext.current
    var goal by remember {
        mutableIntStateOf(goalContext.getSharedPreferences("futurevoice", 0)
            .getInt("futurevoice.dailyGoalMinutes", 10))
    }
    /** Backing out of step one crosses the auth boundary — asked first
     *  instead of silently signing out. */
    var confirmingSignOut by remember { mutableStateOf(false) }
    fun back() {
        when {
            step > 0 -> step -= 1
            // Account-free onboarding (the normal path): Welcome is just the
            // previous screen — no auth boundary to cross.
            !signedIn -> onBackToWelcome()
            else -> confirmingSignOut = true
        }
    }
    androidx.activity.compose.BackHandler { back() }
    if (confirmingSignOut) {
        androidx.compose.material3.AlertDialog(
            onDismissRequest = { confirmingSignOut = false },
            title = { Text(stringResource(R.string.back_to_the_welcome_screen)) },
            text = { Text(stringResource(R.string.this_signs_you_out_your_answers_stay_on_this_device)) },
            confirmButton = {
                androidx.compose.material3.TextButton(onClick = { confirmingSignOut = false; onBackToWelcome() }) {
                    Text(stringResource(R.string.sign_out_go_back), color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = {
                androidx.compose.material3.TextButton(onClick = { confirmingSignOut = false }) {
                    Text(stringResource(R.string.stay))
                }
            },
        )
    }

    /** Leaving the language step: move a pre-selection that now matches the
     *  app language. Leaving the target step with it is the learner's own
     *  choice and stands. */
    fun resolveCollision() {
        if (current == SetupStep.NATIVE && !targetPickedByHand && LanguageCatalog.sameLanguage(target, native))
            target = defaultTarget(native)
    }

    Scaffold(
        topBar = {
            TopAppBar(title = {
                Text(stringResource(when (current) {
                    SetupStep.NATIVE -> R.string.your_native_language
                    SetupStep.TARGET -> R.string.learn_which_language
                    SetupStep.ACCENT -> R.string.which_accent
                    SetupStep.LEVEL -> R.string.your_level_5f68da
                    SetupStep.GOAL -> R.string.your_daily_goal
                }))
            })
        },
        bottomBar = {
            Row(Modifier.fillMaxWidth().bottomBarInsets().padding(16.dp),
                horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                OutlinedButton(
                    onClick = { back() },
                    modifier = Modifier.weight(1f),
                ) { Text(stringResource(R.string.back)) }
                Button(
                    onClick = {
                        if (step < steps.size - 1) { resolveCollision(); step += 1 }
                        else {
                            // The accent the first clone is remixed into. A
                            // pick made for a target they then moved away
                            // from doesn't belong to this one.
                            val picked = accentId?.takeIf { id ->
                                id == PreferredAccent.NONE || accentOptions.any { it.id == id } }
                            PreferredAccent.set(goalContext, picked ?: accentOptions.firstOrNull()?.id)
                            onFinish(native, target, level, goal)
                        }
                    },
                    modifier = Modifier.weight(1f),
                ) { Text(stringResource(if (step < steps.size - 1) R.string.next else R.string.continue_)) }
            }
        },
    ) { padding ->
        Column(Modifier.padding(padding).fillMaxSize().background(AppSurfaces.ground).padding(horizontal = 16.dp)) {
            LinearProgressIndicator(
                progress = { (step + 1) / steps.size.toFloat() },
                modifier = Modifier.fillMaxWidth().padding(vertical = 8.dp),
            )
            // Step 0 asks its question as the first section's HEADER, because
            // it has two sections and each needs its own — repeating it above
            // them said the same thing twice.
            if (current != SetupStep.NATIVE) {
                Text(
                    stringResource(when (current) {
                        SetupStep.TARGET -> R.string.which_language_do_you_want_to_speak
                        SetupStep.ACCENT -> R.string.which_accent_do_you_want_to_speak_with
                        SetupStep.LEVEL -> R.string.how_comfortable_are_you_right_now
                        else -> R.string.how_much_will_you_talk_each_day
                    }),
                    style = MaterialTheme.typography.titleMedium,
                    modifier = Modifier.padding(vertical = 8.dp),
                )
            }
            when (current) {
                // Two groups, not one flat list of sixty-six: a handful of
                // languages are translated end to end and the rest only get
                // the coaching text. Picking Vietnamese from a single list
                // chose an English app without saying so, and the caveat has
                // to be readable BEFORE the tap.
                SetupStep.NATIVE -> {
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
                SetupStep.TARGET -> ChoiceList(targetChoices, selected = target,
                    title = { LanguageCatalog.endonym(it) },
                    subtitle = { LanguageCatalog.ownName(it, native) },
                    footer = stringResource(R.string.your_fluent_self_speaks_this_language_in_your_own_voice_you_0a47cf)) {
                    target = it
                    targetPickedByHand = true
                }
                // Nothing can be heard yet — the voice doesn't exist — so
                // this is a name pick; the meet act's pills change it once
                // it's audible. What it buys is that the ONE remix made after
                // the clone is already theirs.
                // The plain clone, as a choice (iOS 2026-10-08) — last,
                // because from a native-language take the model invents the
                // accent line by line, which is why a remix is the default.
                SetupStep.ACCENT -> ChoiceList(accentOptions.map { it.id } + PreferredAccent.NONE,
                    selected = accentId?.takeIf { id -> id == PreferredAccent.NONE || accentOptions.any { it.id == id } }
                        ?: accentOptions.first().id,
                    title = { id ->
                        accentOptions.firstOrNull { it.id == id }?.let { accentLabel(it) }
                            ?: stringResource(R.string.accent_original)
                    },
                    subtitle = { id ->
                        if (id == PreferredAccent.NONE)
                            stringResource(R.string.your_voice_as_you_recorded_it_with_no_accent_applied)
                        else null
                    },
                    footer = stringResource(R.string.your_fluent_self_speaks_with_this_accent_in_your_own_voice)) {
                    accentId = it
                }
                SetupStep.LEVEL -> ChoiceList(CefrLevel.entries.toList(), selected = level,
                    title = { LanguageCatalog.levelLabel(it, target) },
                    subtitle = { levelBlurb(it) },
                    footer = stringResource(R.string.you_re_about_to_build_your_fluent_self_another_you_that_alre_1eac72,
                        LanguageCatalog.ownName(target, native))) { level = it }
                SetupStep.GOAL -> ChoiceList(listOf(5, 10, 15, 20, 30), selected = goal,
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
    subtitle: @Composable (T) -> String?,
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
private fun ChoiceRow(title: String, subtitle: String?, selected: Boolean, onPick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().clickable { onPick() }
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.bodyLarge)
            if (subtitle != null) Text(subtitle, style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        if (selected) {
            Icon(Icons.Filled.Check, contentDescription = null,
                tint = MaterialTheme.colorScheme.primary)
        }
    }
}

private enum class SetupStep { NATIVE, TARGET, ACCENT, LEVEL, GOAL }

@Composable
internal fun levelBlurb(level: CefrLevel): String = stringResource(when (level) {
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
