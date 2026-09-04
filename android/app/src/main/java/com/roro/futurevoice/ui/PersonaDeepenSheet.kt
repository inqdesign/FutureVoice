package com.roro.futurevoice.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.roro.futurevoice.R
import com.roro.futurevoice.data.LanguageCatalog
import com.roro.futurevoice.net.PersonaParser
import com.roro.futurevoice.talk.UserPersona
import kotlinx.coroutines.launch

/**
 * The "tell me more about you" ask, deliberately NOT in first-run onboarding:
 * it comes right after the first talk, when the learner has just had a
 * generic conversation and the pitch — a richer persona makes every talk feel
 * more like theirs — lands on lived evidence rather than a promise.
 *
 * It collects the three narrative fields the intake skips: occupation,
 * household, free notes. Each is speak-first with a typing fallback; dictated
 * answers get one polish pass on save, and a failed polish never blocks —
 * raw transcripts are still usable ground truth.
 *
 * Presented once automatically; afterwards reachable any time from Me →
 * Profile.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PersonaDeepenSheet(
    persona: UserPersona?,
    nativeLanguage: String,
    targetLanguage: String,
    onSave: (UserPersona) -> Unit,
    onDismiss: () -> Unit,
) {
    val scope = rememberCoroutineScope()
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    // Editing starts from what is already saved, not blank fields that would
    // overwrite it with "".
    var occupation by remember { mutableStateOf(persona?.occupation.orEmpty()) }
    var household by remember { mutableStateOf(persona?.household.orEmpty()) }
    var freeNotes by remember { mutableStateOf(persona?.freeNotes.orEmpty()) }
    var workVoiced by remember { mutableStateOf(false) }
    var peopleVoiced by remember { mutableStateOf(false) }
    var extrasVoiced by remember { mutableStateOf(false) }
    // Native first — the point of the sheet is that talking about your life
    // shouldn't itself be a language exercise.
    var locale by remember { mutableStateOf(nativeLanguage) }
    var saving by remember { mutableStateOf(false) }

    val hasAnything = listOf(occupation, household, freeNotes).any { it.isNotBlank() }

    ModalBottomSheet(
        onDismissRequest = { if (!saving) onDismiss() },
        sheetState = sheetState,
    ) {
        Column(
            Modifier.fillMaxWidth().navigationBarsPadding()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp).padding(bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(20.dp),
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(stringResource(R.string.make_me_sound_more_like_you),
                    style = MaterialTheme.typography.headlineSmall,
                    fontWeight = FontWeight.SemiBold)
                Text(stringResource(R.string.the_more_i_know_your_life_the_more_real_every_talk_feels),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }

            Row(
                Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Text(stringResource(R.string.answer_in),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                val options = listOf(nativeLanguage, targetLanguage).distinct()
                SingleChoiceSegmentedButtonRow {
                    options.forEachIndexed { i, code ->
                        SegmentedButton(
                            selected = locale == code,
                            onClick = { locale = code },
                            shape = SegmentedButtonDefaults.itemShape(i, options.size),
                        ) { Text(LanguageCatalog.endonym(code)) }
                    }
                }
            }

            Field(stringResource(R.string.what_do_you_do),
                occupation, { occupation = it }, workVoiced, { workVoiced = it },
                stringResource(R.string.work_study_or_your_main_project), locale)
            Field(stringResource(R.string.whos_in_your_daily_life),
                household, { household = it }, peopleVoiced, { peopleVoiced = it },
                stringResource(R.string.who_you_live_with_kids_pets), locale)
            Field(stringResource(R.string.anything_else),
                freeNotes, { freeNotes = it }, extrasVoiced, { extrasVoiced = it },
                stringResource(R.string.quirks_goals_pet_peeves), locale)

            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                TextButton(onClick = onDismiss, enabled = !saving) {
                    Text(stringResource(R.string.later))
                }
                Button(
                    onClick = {
                        saving = true
                        scope.launch {
                            var occ = occupation; var house = household; var notes = freeNotes
                            // Only DICTATED answers go through the polish —
                            // typed text is already deliberate, and rewriting
                            // it would surprise the person who wrote it.
                            val vOcc = if (workVoiced) occ else ""
                            val vHouse = if (peopleVoiced) house else ""
                            val vNotes = if (extrasVoiced) notes else ""
                            if (vOcc.isNotEmpty() || vHouse.isNotEmpty() || vNotes.isNotEmpty()) {
                                runCatching {
                                    PersonaParser.polish(vOcc, vHouse, vNotes, locale)
                                }.onSuccess { p ->
                                    if (vOcc.isNotEmpty() && p.occupation.isNotBlank()) occ = p.occupation
                                    if (vHouse.isNotEmpty() && p.household.isNotBlank()) house = p.household
                                    if (vNotes.isNotEmpty() && p.free_notes.isNotBlank()) notes = p.free_notes
                                }
                                // A failed polish keeps the raw transcripts:
                                // never block the save on a cleanup pass.
                            }
                            onSave((persona ?: UserPersona()).copy(
                                occupation = occ, household = house, freeNotes = notes))
                            saving = false
                            onDismiss()
                        }
                    },
                    enabled = hasAnything && !saving,
                    modifier = Modifier.weight(1f),
                ) {
                    if (saving) {
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp),
                            verticalAlignment = Alignment.CenterVertically) {
                            CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp)
                            Text(stringResource(R.string.sorting_it_out))
                        }
                    } else {
                        Text(stringResource(R.string.save))
                    }
                }
            }
        }
    }
}

@Composable
private fun Field(
    title: String,
    text: String,
    onText: (String) -> Unit,
    usedVoice: Boolean,
    onUsedVoice: (Boolean) -> Unit,
    placeholder: String,
    locale: String,
) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(title, style = MaterialTheme.typography.titleSmall,
            fontWeight = FontWeight.SemiBold)
        SpeakOrTypeField(text, onText, usedVoice, onUsedVoice, placeholder, locale)
    }
}
