package com.roro.futurevoice.ui

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowLeft
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import com.roro.futurevoice.R
import com.roro.futurevoice.data.AvatarStore
import com.roro.futurevoice.data.LanguageCatalog
import com.roro.futurevoice.talk.UserPersona
import com.roro.futurevoice.ui.brand.AppSurfaces
import com.roro.futurevoice.ui.brand.IosButton as Button
import com.roro.futurevoice.ui.brand.IosOutlinedButton as OutlinedButton
import kotlinx.coroutines.launch

/**
 * Persona EDIT form (Me → Profile) — iOS `PersonaOnboardingView`, presented
 * with an existing persona. Three pages of plain form sections covering more
 * than the first-run intake (`PersonaIntakeScreen`) asks: name + photo; where
 * you live, what you do, who you live with and the remembered lines; then
 * interests, the situations you want the language for, and free notes.
 *
 * Each page is SAVED as it's left with Next (iOS: "a sheet swiped away on page
 * three keeps what pages one and two said"); Back moves a page without
 * saving; system back on the first page closes without saving it. Save on the
 * last page commits and closes. A commit that changed nothing writes nothing,
 * because `savePersona` re-syncs the public intro.
 */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun PersonaEditScreen(
    initial: UserPersona,
    /** The persona on file right now — share corrections are measured
     *  against it, and an unchanged draft is not saved over it. */
    saved: UserPersona?,
    targetLanguage: String,
    nativeLanguage: String,
    onSave: (UserPersona) -> Unit,
    onClose: () -> Unit,
    /** Where the pages open — Me's remembered lines open on the life page. */
    startStep: Int = 0,
    /** "Show the talk" on a remembered line: open that talk's page (iOS
     *  presents `ConversationDetailView` over the form). */
    onShowTalk: ((sessionId: String, language: String) -> Unit)? = null,
) {
    val context = LocalContext.current
    val onFile by rememberUpdatedState(saved)
    // Saveable: "Show the talk" covers this page with the talk's, and the
    // root stack draws only its top page — the draft must come back intact,
    // as it does under iOS's sheet.
    var step by rememberSaveable { mutableIntStateOf(startStep.coerceIn(0, 2)) }
    var persona by rememberSaveable(stateSaver = PersonaSaver) { mutableStateOf(initial) }
    var interestsDraft by rememberSaveable { mutableStateOf("") }
    var situationsDraft by rememberSaveable { mutableStateOf("") }

    /** Writes the draft as it stands (iOS `commit`). */
    fun commit() {
        var p = persona.copy(
            interests = mergeDraft(persona.interests, interestsDraft),
            situations = mergeDraft(persona.situations, situationsDraft),
        )
        interestsDraft = ""; situationsDraft = ""
        // Trim lines, drop emptied ones, record the rungs moved by hand
        // against what is on file — never the draft.
        p = p.committingNotes(onFile?.learnedNotes ?: emptyList())
        persona = p
        if (onFile == p) return
        onSave(p)
    }

    fun back() { if (step > 0) step -= 1 else onClose() }
    androidx.activity.compose.BackHandler { back() }

    val canAdvance = when (step) {
        0 -> persona.displayName.isNotBlank()
        1 -> persona.city.isNotBlank()
        else -> true
    }
    val targetName = LanguageCatalog.ownName(targetLanguage, nativeLanguage)

    Scaffold(
        topBar = {
            TopAppBar(title = {
                Text(when (step) {
                    0 -> stringResource(R.string.profile)
                    1 -> stringResource(R.string.your_life)
                    else -> stringResource(R.string.your_world, targetName)
                })
            })
        },
        bottomBar = {
            Row(Modifier.fillMaxWidth().bottomBarInsets().padding(horizontal = 16.dp, vertical = 12.dp),
                horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                if (step > 0) {
                    OutlinedButton(onClick = { step -= 1 }, modifier = Modifier.weight(1f)) {
                        Icon(Icons.AutoMirrored.Filled.KeyboardArrowLeft, contentDescription = null)
                        Text(stringResource(R.string.back))
                    }
                }
                Button(
                    enabled = canAdvance,
                    onClick = {
                        commit()
                        if (step < 2) step += 1 else onClose()
                    },
                    modifier = Modifier.weight(1f),
                ) { Text(stringResource(if (step < 2) R.string.next else R.string.save)) }
            }
        },
    ) { padding ->
        Column(
            Modifier.padding(padding).fillMaxSize().background(AppSurfaces.ground)
                .padding(horizontal = 16.dp).verticalScroll(rememberScrollState()),
        ) {
            LinearProgressIndicator(progress = { (step + 1) / 3f },
                modifier = Modifier.fillMaxWidth().padding(vertical = 8.dp))
            when (step) {
                0 -> {
                    GroupedSectionHeader(stringResource(R.string.your_fluent_self_wants_to_know_you))
                    GroupedCard {
                        val scope = rememberCoroutineScope()
                        val pick = rememberLauncherForActivityResult(
                            ActivityResultContracts.PickVisualMedia()) { uri ->
                            uri?.let { scope.launch { AvatarStore.save(context, it) } }
                        }
                        Box(Modifier.fillMaxWidth().padding(vertical = 16.dp),
                            contentAlignment = Alignment.Center) {
                            Box(Modifier.clip(CircleShape).clickable {
                                pick.launch(PickVisualMediaRequest(
                                    ActivityResultContracts.PickVisualMedia.ImageOnly))
                            }, contentAlignment = Alignment.BottomEnd) {
                                ProfileAvatar(initials = persona.displayName, size = 88.dp)
                                Box(Modifier.size(28.dp).clip(CircleShape)
                                    .background(MaterialTheme.colorScheme.primary),
                                    contentAlignment = Alignment.Center) {
                                    Icon(Icons.Filled.Edit, contentDescription = null,
                                        modifier = Modifier.size(16.dp),
                                        tint = MaterialTheme.colorScheme.onPrimary)
                                }
                            }
                        }
                        GroupedRowDivider(inset = false)
                        FormTextRow(persona.displayName, { persona = persona.copy(displayName = it) },
                            stringResource(R.string.what_should_i_call_you),
                            capitalization = KeyboardCapitalization.Words)
                    }
                    GroupedFooter(stringResource(
                        R.string.the_more_you_share_the_more_i_ll_sound_like_a_version_of_you_b76d91))
                }
                1 -> {
                    GroupedSectionHeader(stringResource(R.string.where_you_live))
                    GroupedCard {
                        FormTextRow(persona.city, { persona = persona.copy(city = it) },
                            stringResource(R.string.city), capitalization = KeyboardCapitalization.Words)
                        GroupedRowDivider(inset = false)
                        FormTextRow(persona.country, { persona = persona.copy(country = it) },
                            stringResource(R.string.country), capitalization = KeyboardCapitalization.Words)
                        GroupedRowDivider(inset = false)
                        FormTextRow(persona.lengthOfStay, { persona = persona.copy(lengthOfStay = it) },
                            stringResource(R.string.how_long_optional))
                    }
                    GroupedSectionHeader(stringResource(R.string.what_you_do))
                    GroupedCard {
                        FormTextRow(persona.occupation, { persona = persona.copy(occupation = it) },
                            stringResource(R.string.e_g_solo_founder_of_an_ai_app_for_parents),
                            minLines = 2, maxLines = 4)
                    }
                    GroupedSectionHeader(stringResource(R.string.who_you_live_with_optional))
                    GroupedCard {
                        FormTextRow(persona.household, { persona = persona.copy(household = it) },
                            stringResource(R.string.e_g_wife_and_4yo_daughter_at_kita),
                            minLines = 2, maxLines = 4)
                    }
                    RememberedLinesSection(persona,
                        onNotesChange = { persona = persona.copy(learnedNotes = it) },
                        onShowTalk = onShowTalk)
                }
                else -> {
                    GroupedSectionHeader(stringResource(R.string.interests))
                    GroupedCard {
                        PresetChips(PERSONA_INTEREST_PRESETS, persona.interests) {
                            persona = persona.copy(interests = toggled(persona.interests, it))
                        }
                        GroupedRowDivider(inset = false)
                        AddOwnRow(interestsDraft, { interestsDraft = it }) {
                            persona = persona.copy(interests = mergeDraft(persona.interests, interestsDraft))
                            interestsDraft = ""
                        }
                    }
                    GroupedFooter(stringResource(R.string.tap_to_toggle_or_type_your_own_and_hit_return))

                    GroupedSectionHeader(stringResource(R.string.what_do_you_want_to_be_able_to_do_in, targetName))
                    GroupedCard {
                        PresetChips(PERSONA_SITUATION_PRESETS, persona.situations) {
                            persona = persona.copy(situations = toggled(persona.situations, it))
                        }
                        GroupedRowDivider(inset = false)
                        AddOwnRow(situationsDraft, { situationsDraft = it }) {
                            persona = persona.copy(situations = mergeDraft(persona.situations, situationsDraft))
                            situationsDraft = ""
                        }
                    }
                    GroupedFooter(stringResource(R.string.what_you_pick_becomes_your_goal_practice_aims_at_it))

                    GroupedSectionHeader(stringResource(R.string.anything_else_optional))
                    GroupedCard {
                        FormTextRow(persona.freeNotes, { persona = persona.copy(freeNotes = it) },
                            stringResource(R.string.quirks_preferences_anything_that_helps_me_sound_like_you),
                            minLines = 3, maxLines = 6)
                    }
                }
            }
            Spacer(Modifier.height(24.dp))
        }
    }
}

private val PersonaSaver = androidx.compose.runtime.saveable.Saver<UserPersona, String>(
    save = { com.roro.futurevoice.data.StoreJson.json.encodeToString(UserPersona.serializer(), it) },
    restore = { runCatching {
        com.roro.futurevoice.data.StoreJson.json.decodeFromString(UserPersona.serializer(), it)
    }.getOrNull() },
)

/** The presets only, as iOS's chip grid draws them — a tag the learner typed
 *  is kept in the list but has no chip. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun PresetChips(presets: List<String>, selected: List<String>, onTap: (String) -> Unit) {
    FlowRow(Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        presets.forEach { tag ->
            FilterChip(selected = tag in selected, onClick = { onTap(tag) },
                label = { Text(presetLabel(tag)) })
        }
    }
}

/** "Add your own (comma-separated)" — folded in on the keyboard's Done
 *  (iOS `onSubmit`) and on every commit. */
@Composable
private fun AddOwnRow(value: String, onChange: (String) -> Unit, onDone: () -> Unit) {
    val style = MaterialTheme.typography.bodyLarge.copy(color = MaterialTheme.colorScheme.onSurface)
    BasicTextField(
        value = value, onValueChange = onChange, textStyle = style, singleLine = true,
        cursorBrush = SolidColor(MaterialTheme.colorScheme.primary),
        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
        keyboardActions = KeyboardActions(onDone = { onDone() }),
        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 11.dp),
        decorationBox = { inner ->
            Box {
                if (value.isEmpty()) Text(stringResource(R.string.add_your_own_comma_separated),
                    style = style, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.3f),
                    maxLines = 1)
                inner()
            }
        },
    )
}

private fun toggled(list: List<String>, value: String): List<String> =
    if (value in list) list - value else list + value

/** iOS `mergeDraft`: comma-split, trimmed, appended when new. */
private fun mergeDraft(list: List<String>, draft: String): List<String> {
    val pieces = draft.split(",").map { it.trim() }.filter { it.isNotEmpty() }
    return pieces.fold(list) { acc, p -> if (p in acc) acc else acc + p }
}

// iOS `PersonaOnboardingView.interestPresets` / `.situationPresets` — stored
// values stay English (prompt material + selection keys); only the label
// localizes (`presetLabel`). Also the interests source for the first-run
// intake's chip card.
internal val PERSONA_INTEREST_PRESETS = listOf(
    "AI / tech", "parenting", "language learning", "music", "podcasts",
    "cooking", "travel", "sports", "fashion", "finance", "science", "art",
)
internal val PERSONA_SITUATION_PRESETS = listOf(
    "Work meetings", "Client calls", "Kita / school",
    "Doctor / clinic", "Travel", "Online shopping",
    "Customer service", "Streaming / shows", "Reading articles",
    "Daily small talk",
)
