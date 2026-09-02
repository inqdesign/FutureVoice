package com.roro.futurevoice.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
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
import androidx.compose.ui.unit.dp
import com.roro.futurevoice.R
import com.roro.futurevoice.data.Counterpart
import com.roro.futurevoice.data.CounterpartStore
import com.roro.futurevoice.data.StoreEvents
import com.roro.futurevoice.talk.StockPerson
import kotlinx.coroutines.launch

/**
 * The learner's OWN people — the ones Watch's stories row is made of.
 * Strangers are a different sheet (`FindPeopleScreen`) and a different idea:
 * these are people whose relationship to the learner is the whole point, and
 * a scene with them is grounded in it.
 *
 * Kept deliberately short. A person is not a form to complete — name and
 * "who are they to you" is enough to run a scene, and everything below that
 * only sharpens it.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PeopleSheet(onDismiss: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val store = remember { CounterpartStore.shared(context) }
    var people by remember { mutableStateOf<List<Counterpart>>(emptyList()) }
    var editing by remember { mutableStateOf<Counterpart?>(null) }

    suspend fun reload() { people = store.load().filter { it.remoteId == null } }
    LaunchedEffect(Unit) { reload() }

    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(
            Modifier.fillMaxWidth().navigationBarsPadding().padding(horizontal = 20.dp).padding(bottom = 32.dp)
                .verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            Text(stringResource(R.string.people), style = MaterialTheme.typography.titleLarge,
                modifier = Modifier.padding(bottom = 8.dp))

            people.forEach { person ->
                Row(
                    Modifier.fillMaxWidth().clickable { editing = person }
                        .padding(vertical = 12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Column(Modifier.weight(1f)) {
                        Text(person.name, style = MaterialTheme.typography.bodyLarge)
                        if (person.caption.isNotEmpty()) {
                            Text(person.caption, style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                    IconButton(onClick = {
                        scope.launch { store.delete(person.id); reload(); StoreEvents.bump() }
                    }) {
                        Icon(Icons.Filled.Delete,
                            contentDescription = stringResource(R.string.delete),
                            tint = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }

            if (people.isEmpty()) {
                Text(stringResource(R.string.add_someone_you_actually_talk_to),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(vertical = 8.dp))
            }

            Button(onClick = { editing = Counterpart() },
                modifier = Modifier.fillMaxWidth().padding(top = 12.dp)) {
                Text(stringResource(R.string.add_a_person))
            }
        }
    }

    editing?.let { draft ->
        PersonEditor(
            person = draft,
            onSave = {
                scope.launch { store.save(it); reload(); StoreEvents.bump() }
                editing = null
            },
            onDismiss = { editing = null },
        )
    }
}

/** Name and relationship carry the scene; the rest only sharpens it. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun PersonEditor(
    person: Counterpart,
    onSave: (Counterpart) -> Unit,
    onDismiss: () -> Unit,
) {
    var draft by remember(person.id) { mutableStateOf(person) }
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        // Fully expanded from the start: the form is taller than a half
        // sheet, so a partial one hides Save and asks the learner to discover
        // a scroll before they can finish what they opened.
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
    ) {
        Column(
            Modifier.fillMaxWidth().navigationBarsPadding().padding(horizontal = 20.dp).padding(bottom = 32.dp)
                .verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(stringResource(R.string.add_a_person),
                style = MaterialTheme.typography.titleLarge)
            Field(stringResource(R.string.name), draft.name) { draft = draft.copy(name = it) }
            Field(stringResource(R.string.who_are_they_to_you), draft.relationship) {
                draft = draft.copy(relationship = it)
            }
            Field(stringResource(R.string.shared_context), draft.background, lines = 3) {
                draft = draft.copy(background = it)
            }
            Field(stringResource(R.string.how_they_talk), draft.conversationStyle) {
                draft = draft.copy(conversationStyle = it)
            }

            // Never a clone — the person on the other end is someone else.
            Text(stringResource(R.string.voice), style = MaterialTheme.typography.labelLarge)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                StockPerson.catalog.forEach { preset ->
                    FilterChip(
                        selected = draft.voicePresetId == preset.voiceId,
                        onClick = { draft = draft.copy(voicePresetId = preset.voiceId) },
                        label = { Text(preset.name) },
                    )
                }
            }

            Row(Modifier.fillMaxWidth().padding(top = 8.dp),
                horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                TextButton(onClick = onDismiss, modifier = Modifier.weight(1f)) {
                    Text(stringResource(R.string.cancel))
                }
                Button(
                    onClick = {
                        onSave(draft.copy(voicePresetId = draft.voicePresetId.ifBlank {
                            StockPerson.catalog.first().voiceId
                        }))
                    },
                    enabled = draft.isMinimallyComplete,
                    modifier = Modifier.weight(1f),
                ) { Text(stringResource(R.string.save)) }
            }
        }
    }
}

@Composable
private fun Field(label: String, value: String, lines: Int = 1, onChange: (String) -> Unit) {
    OutlinedTextField(
        value = value,
        onValueChange = onChange,
        label = { Text(label) },
        minLines = lines,
        modifier = Modifier.fillMaxWidth(),
    )
}
