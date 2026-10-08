package com.roro.futurevoice.ui

import com.roro.futurevoice.data.AvatarStore
import kotlinx.coroutines.launch
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.draw.clip
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.clickable
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.compose.foundation.background
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
import com.roro.futurevoice.ui.brand.IosButton as Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import com.roro.futurevoice.ui.brand.IosOutlinedButton as OutlinedButton
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
import com.roro.futurevoice.ui.brand.AppSurfaces
import com.roro.futurevoice.data.LanguageCatalog
import com.roro.futurevoice.talk.UserPersona

/**
 * First-run persona collection — `PersonaIntakeView`, three light cards only:
 * name, home, and interests (they feed the news rail). The fourth card,
 * "What do you want to be able to do in English?", was cut from onboarding on
 * 2026-10-08 (founder, iOS `PersonaIntakeView`): two seconds of chips, never
 * revisited, and the first call learns what someone needs the language for
 * far better; its slot went to the accent question (`SetupFlowScreen`).
 * `persona.situations` stays editable in Me → Profile (`PersonaEditScreen`,
 * iOS `PersonaOnboardingView`), which is its own form, not these cards. The
 * narrative answers are
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
    // iOS `PersonaIntakeView`'s draft: answers + the current card survive an
    // app kill and a cross-stage Back, so a relaunch resumes where the
    // learner left off instead of re-asking the cards. Saved at every step
    // transition, cleared on finish.
    val context = LocalContext.current
    // A draft from an interrupted run wins over [initial].
    val seed = remember { PersonaDraft.load(context) }
    val from = seed?.first ?: initial
    val lastStep = 2
    var step by remember { mutableIntStateOf((seed?.second ?: 0).coerceIn(0, lastStep)) }
    var name by remember { mutableStateOf(from.displayName) }
    var city by remember { mutableStateOf(from.city) }
    var country by remember { mutableStateOf(from.country) }
    var stay by remember { mutableStateOf(from.lengthOfStay) }
    var interests by remember { mutableStateOf(from.interests.toSet()) }
    fun draft() = initial.copy(
        displayName = name.trim(), city = city.trim(),
        country = country.trim(), lengthOfStay = stay.trim(),
        interests = interests.toList(),
    )
    fun saveDraft() { PersonaDraft.save(context, draft(), step) }
    /** Back: a step within the cards, or — on the first — reopen setup.
     *  Answers survive either way: the draft here, the app state there. */
    fun back() {
        if (step > 0) { step -= 1; saveDraft() } else { saveDraft(); onBackToSetup() }
    }
    androidx.activity.compose.BackHandler { back() }

    val canAdvance = when (step) {
        0 -> name.isNotBlank()
        1 -> city.isNotBlank()
        else -> true
    }

    Scaffold(
        topBar = { TopAppBar(title = { Text(stringResource(R.string.about_you)) }) },
        bottomBar = {
            Row(Modifier.fillMaxWidth().bottomBarInsets().padding(16.dp),
                horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                OutlinedButton(
                    onClick = { back() },
                    modifier = Modifier.weight(1f),
                ) { Text(stringResource(R.string.back)) }
                Button(
                    enabled = canAdvance,
                    onClick = {
                        if (step < lastStep) { step += 1; saveDraft() }
                        else {
                            PersonaDraft.clear(context)
                            onFinish(draft())
                        }
                    },
                    modifier = Modifier.weight(1f),
                ) { Text(stringResource(R.string.next)) }
            }
        },
    ) { padding ->
        Column(
            Modifier.padding(padding).fillMaxSize().background(AppSurfaces.ground).padding(16.dp).verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            LinearProgressIndicator(progress = { (step + 1) / (lastStep + 1f) }, modifier = Modifier.fillMaxWidth())
            when (step) {
                0 -> {
                    Header(stringResource(R.string.what_should_i_call_you),
                        stringResource(R.string.we_re_building_your_fluent_self_it_ll_speak_in_your_own_voic_e7ccbb))
                    // The picture is the learner's to pick: neither sign-in
                    // hands one over.
                    val scope = rememberCoroutineScope()
                    val context = LocalContext.current
                    val pick = rememberLauncherForActivityResult(
                        ActivityResultContracts.PickVisualMedia()) { uri ->
                        uri?.let { scope.launch { AvatarStore.save(context, it) } }
                    }
                    Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                        Box(Modifier.clip(CircleShape).clickable {
                            pick.launch(PickVisualMediaRequest(
                                ActivityResultContracts.PickVisualMedia.ImageOnly))
                        }) { ProfileAvatar(initials = name, size = 88.dp) }
                    }
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
                    // City only (iOS 2026-10-08, founder): this card tells the
                    // fluent self where they live, and a city says that —
                    // typing the country too was effort for nothing. The
                    // field stays on the persona and in Me → Profile.
                    OutlinedTextField(value = stay, onValueChange = { stay = it },
                        label = { Text(stringResource(R.string.how_long_have_you_been_there_optional)) },
                        singleLine = true, modifier = Modifier.fillMaxWidth())
                }
                2 -> {
                    Header(stringResource(R.string.what_are_you_into),
                        stringResource(R.string.tap_what_fits_these_pick_your_news_stories_and_fuel_conversa_369fbd))
                    ChipGrid(PERSONA_INTEREST_PRESETS, interests) { tag ->
                        interests = if (tag in interests) interests - tag else interests + tag
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
                label = { Text(presetLabel(tag)) })
        }
    }
}

/**
 * The first-run intake's draft (iOS `futurevoice.personaDraft` /
 * `futurevoice.personaDraftStep`): the answers and the card they were on.
 */
internal object PersonaDraft {
    private const val KEY = "futurevoice.personaDraft"
    private const val STEP_KEY = "futurevoice.personaDraftStep"

    fun load(c: android.content.Context): Pair<UserPersona, Int>? {
        val p = c.getSharedPreferences("futurevoice", 0)
        val raw = p.getString(KEY, null) ?: return null
        val persona = runCatching {
            com.roro.futurevoice.data.StoreJson.json.decodeFromString(UserPersona.serializer(), raw)
        }.getOrNull() ?: return null
        // A step from an older, longer flow can point past the end — clamp
        // instead of silently restarting at card one.
        return persona to p.getInt(STEP_KEY, 0).coerceIn(0, 2)
    }

    fun save(c: android.content.Context, persona: UserPersona, step: Int) {
        c.getSharedPreferences("futurevoice", 0).edit()
            .putString(KEY, com.roro.futurevoice.data.StoreJson.json.encodeToString(UserPersona.serializer(), persona))
            .putInt(STEP_KEY, step).apply()
    }

    fun clear(c: android.content.Context) {
        c.getSharedPreferences("futurevoice", 0).edit().remove(KEY).remove(STEP_KEY).apply()
    }
}
