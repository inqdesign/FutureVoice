package com.roro.futurevoice.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Switch
import androidx.compose.ui.graphics.asImageBitmap
import com.roro.futurevoice.data.CounterpartPhotoStore
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
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
            Modifier.fillMaxWidth().bottomBarInsets().padding(horizontal = 20.dp).padding(bottom = 32.dp)
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
                    PersonBubble(person.name, person.id, size = 40.dp)
                    Spacer(Modifier.width(12.dp))
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
internal fun PersonEditor(
    person: Counterpart,
    onSave: (Counterpart) -> Unit,
    onDismiss: () -> Unit,
    /** A photo picked before the person existed (the intake's first card). */
    initialPhoto: android.graphics.Bitmap? = null,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var draft by remember(person.id) { mutableStateOf(person) }
    /** The photo to save with this person on Save; `removePhoto` = delete
     *  the one on file. Saved only on Save, so Cancel leaves the face alone. */
    var pendingPhoto by remember(person.id) { mutableStateOf(initialPhoto) }
    var removePhoto by remember(person.id) { mutableStateOf(false) }
    val onFile = rememberPersonPhoto(person.id)
    val shownPhoto = pendingPhoto?.asImageBitmap() ?: if (removePhoto) null else onFile
    var lookingUp by remember { mutableStateOf(false) }
    var lookupError by remember { mutableStateOf<String?>(null) }
    // Once there is something to lose, Cancel is the ONLY way out: a small
    // vertical drag while reaching for a field used to take the whole form
    // with it (iOS `32f20a1`).
    val dirty = draft != person || pendingPhoto != null || removePhoto
    val sheetState = rememberModalBottomSheetState(
        skipPartiallyExpanded = true,
        confirmValueChange = { value ->
            value != androidx.compose.material3.SheetValue.Hidden || !dirty
        },
    )
    ModalBottomSheet(
        onDismissRequest = { if (!dirty) onDismiss() },
        // Fully expanded from the start: the form is taller than a half
        // sheet, so a partial one hides Save and asks the learner to discover
        // a scroll before they can finish what they opened.
        sheetState = sheetState,
    ) {
        Column(
            Modifier.fillMaxWidth().bottomBarInsets().padding(horizontal = 20.dp).padding(bottom = 32.dp)
                .verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(stringResource(R.string.add_a_person),
                style = MaterialTheme.typography.titleLarge)
            // Their face, optional — photo picker, camera or a file; saved
            // small and square with the person, never sent anywhere.
            Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(6.dp)) {
                PersonPhotoButton(
                    onImage = { pendingPhoto = it; removePhoto = false },
                    onRemove = if (shownPhoto == null) null else ({ pendingPhoto = null; removePhoto = true }),
                ) {
                    PersonBubble(draft.name, photoId = null, size = 88.dp, photo = shownPhoto)
                }
                Text(stringResource(R.string.a_photo_is_optional_without_one_their_initials_stand_in),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Field(stringResource(R.string.name), draft.name) { draft = draft.copy(name = it) }
            Field(stringResource(R.string.who_are_they_to_you), draft.relationship) {
                draft = draft.copy(relationship = it)
            }
            // A public figure is a RELATIONSHIP, not "Other" (iOS `59c6481`):
            // their profile comes from public coverage, and their voice is a
            // preset like any stranger's — never their real one.
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Text(stringResource(R.string.public_figure), style = MaterialTheme.typography.bodyLarge,
                    modifier = Modifier.weight(1f))
                Switch(checked = draft.isPublicFigure == true,
                    onCheckedChange = { draft = draft.copy(isPublicFigure = if (it) true else null) })
            }
            if (draft.isPublicFigure == true) {
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    draft.publicIdentity?.takeIf { it.isNotBlank() }?.let { who ->
                        Row(Modifier.fillMaxWidth()) {
                            Text(stringResource(R.string.who), style = MaterialTheme.typography.bodyMedium,
                                modifier = Modifier.weight(1f))
                            Text(who, style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                    OutlinedButton(
                        enabled = !lookingUp && draft.name.isNotBlank(),
                        onClick = {
                            lookingUp = true; lookupError = null
                            scope.launch {
                                val native = context.getSharedPreferences("futurevoice", android.content.Context.MODE_PRIVATE)
                                    .getString("futurevoice.nativeLanguage", null)
                                    ?: com.roro.futurevoice.data.LanguageCatalog.defaultNative()
                                val target = context.getSharedPreferences("futurevoice", android.content.Context.MODE_PRIVATE)
                                    .getString("futurevoice.targetLanguage", null) ?: "en"
                                runCatching {
                                    com.roro.futurevoice.talk.PublicFigureLookup.lookUp(draft, native, target)
                                }.onSuccess { draft = it }
                                    .onFailure { lookupError = it.message }
                                lookingUp = false
                            }
                        },
                    ) {
                        if (lookingUp) CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp)
                        else Icon(Icons.Filled.Refresh, contentDescription = null, modifier = Modifier.size(16.dp))
                        Spacer(Modifier.width(8.dp))
                        Text(stringResource(R.string.refresh_public_info))
                    }
                    val at = draft.factsRefreshedAt
                    Text(
                        when {
                            lookupError != null -> lookupError!!
                            at != null -> stringResource(
                                R.string.looked_up_only_public_facts_nothing_private_nothing_invented_0a1d96,
                                java.time.format.DateTimeFormatter.ofLocalizedDate(java.time.format.FormatStyle.MEDIUM)
                                    .format(java.time.Instant.ofEpochMilli(at).atZone(java.time.ZoneId.systemDefault())))
                            else -> stringResource(R.string.a_public_figure_s_profile_comes_from_public_coverage_their_v_f715e8)
                        },
                        style = MaterialTheme.typography.bodySmall,
                        color = if (lookupError != null) MaterialTheme.colorScheme.error
                        else MaterialTheme.colorScheme.onSurfaceVariant)
                }
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
                        val saved = draft.copy(voicePresetId = draft.voicePresetId.ifBlank {
                            StockPerson.catalog.first().voiceId
                        })
                        val photo = pendingPhoto
                        val drop = removePhoto
                        scope.launch {
                            when {
                                photo != null -> CounterpartPhotoStore.save(context, saved.id, photo)
                                drop -> CounterpartPhotoStore.delete(context, saved.id)
                            }
                        }
                        onSave(saved)
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
