package com.roro.futurevoice.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import com.roro.futurevoice.R
import com.roro.futurevoice.talk.UserPersona

/**
 * Focused editor for the learner's interests — the signal behind the "In the
 * news" topics.
 *
 * Reachable straight from the topic picker so tuning what shows up is one tap
 * away, without diving into the full profile screen. Until now the intake
 * asked once and there was no way back: the news rail was frozen on whatever
 * a learner tapped in their first five minutes.
 */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun InterestsEditorSheet(
    persona: UserPersona?,
    onSave: (UserPersona) -> Unit,
    onDismiss: () -> Unit,
) {
    // Seeded ONCE. Re-reading the persona on recomposition would wipe toggles
    // the learner has made but not yet saved.
    var interests by remember { mutableStateOf(persona?.interests.orEmpty()) }
    var draft by remember { mutableStateOf("") }

    fun mergeDraft() {
        val pieces = draft.split(",").map { it.trim() }.filter { it.isNotEmpty() }
        interests = interests + pieces.filter { it !in interests }
        draft = ""
    }

    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(
            Modifier.fillMaxWidth().navigationBarsPadding()
                .padding(horizontal = 20.dp).padding(bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Text(stringResource(R.string.interests),
                style = MaterialTheme.typography.titleLarge)

            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)) {
                // Presets AND anything the learner typed before, so a custom
                // tag can be switched off again instead of only added.
                (PRESETS + interests.filter { it !in PRESETS }).forEach { tag ->
                    val on = tag in interests
                    Text(
                        tag,
                        style = MaterialTheme.typography.bodyMedium,
                        color = if (on) MaterialTheme.colorScheme.onPrimary
                        else MaterialTheme.colorScheme.onSurface,
                        modifier = Modifier
                            .background(
                                if (on) MaterialTheme.colorScheme.primary
                                else MaterialTheme.colorScheme.surfaceVariant,
                                CircleShape)
                            .clickable {
                                interests = if (on) interests - tag else interests + tag
                            }
                            .padding(horizontal = 12.dp, vertical = 6.dp),
                    )
                }
            }

            OutlinedTextField(
                value = draft,
                onValueChange = { draft = it },
                label = { Text(stringResource(R.string.add_your_own_comma_separated)) },
                singleLine = true,
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
                keyboardActions = KeyboardActions(onDone = { mergeDraft() }),
                modifier = Modifier.fillMaxWidth(),
            )
            Text(stringResource(R.string.tap_to_toggle_or_type_your_own),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant)

            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel)) }
                Button(
                    onClick = {
                        // A tag typed but never submitted is still a tag the
                        // learner asked for.
                        mergeDraft()
                        onSave((persona ?: UserPersona()).copy(interests = interests))
                        onDismiss()
                    },
                    modifier = Modifier.weight(1f),
                ) { Text(stringResource(R.string.save)) }
            }
        }
    }
}

private val PRESETS = listOf(
    "AI / tech", "parenting", "language learning", "music", "podcasts",
    "cooking", "travel", "sports", "fashion", "finance", "science", "art",
)
