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
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Lightbulb
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.roro.futurevoice.R
import com.roro.futurevoice.data.AuthRepository
import com.roro.futurevoice.net.EnrichmentClient
import com.roro.futurevoice.talk.DrillCard
import com.roro.futurevoice.talk.UserPersona

/**
 * A card, opened up: three examples set in the learner's OWN life, other ways
 * to say the same thing, and a hook to remember it by.
 *
 * The point is the pattern, not the swap. A card on its own teaches one
 * substitution; what a learner needs is to recognise the shape next time it
 * comes up in a different sentence — which is why the examples are situations
 * rather than more sentences.
 *
 * Generated on demand and NOT persisted here: the sheet is opened rarely and
 * the call is free under the daily cap, so a stale cached payload would cost
 * more in wrongness than the call costs in money.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DrillEnrichmentSheet(
    card: DrillCard,
    persona: UserPersona?,
    targetLanguage: String,
    nativeLanguage: String,
    onDismiss: () -> Unit,
) {
    var payload by remember(card.id) { mutableStateOf<EnrichmentClient.Enrichment?>(null) }
    var failed by remember(card.id) { mutableStateOf(false) }

    suspend fun load() {
        failed = false
        payload = runCatching {
            EnrichmentClient(AuthRepository())
                .generate(card, persona, targetLanguage, nativeLanguage)
        }.getOrElse { failed = true; null }
    }
    LaunchedEffect(card.id) { load() }

    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(
            Modifier.fillMaxWidth().navigationBarsPadding()
                .padding(horizontal = 20.dp).padding(bottom = 32.dp)
                .verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Text(card.targetPhrase, style = MaterialTheme.typography.titleLarge)
            card.reason.takeIf { it.isNotBlank() }?.let {
                Text(it, style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }

            when {
                payload == null && !failed ->
                    CircularProgressIndicator(Modifier.size(22.dp), strokeWidth = 2.dp)
                // A retry, not a dead end: the card is still worth opening and
                // one flaky moment shouldn't cost the learner the lesson.
                failed -> TextButton(onClick = { }) {
                    Text(stringResource(R.string.try_again))
                }
                else -> payload?.let { p ->
                    if (p.examples.isNotEmpty()) {
                        Section(stringResource(R.string.in_your_life))
                        p.examples.forEach { e ->
                            Column(Modifier.padding(vertical = 4.dp)) {
                                Text(e.sentence, style = MaterialTheme.typography.bodyLarge)
                                Text(e.situation, style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                        }
                    }
                    if (p.variants.isNotEmpty()) {
                        Section(stringResource(R.string.other_ways_to_say_it))
                        p.variants.forEach { v ->
                            Column(Modifier.padding(vertical = 4.dp)) {
                                Text(v.phrase, style = MaterialTheme.typography.bodyLarge)
                                Text(v.note, style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                        }
                    }
                    p.memory_hook.takeIf { it.isNotBlank() }?.let { hook ->
                        HorizontalDivider(Modifier.padding(top = 4.dp))
                        Row(verticalAlignment = Alignment.Top,
                            horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                            Icon(Icons.Filled.Lightbulb, contentDescription = null,
                                tint = MaterialTheme.colorScheme.primary,
                                modifier = Modifier.size(18.dp))
                            Text(hook, style = MaterialTheme.typography.bodyMedium)
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun Section(title: String) {
    Text(title, style = MaterialTheme.typography.titleSmall,
        fontWeight = FontWeight.SemiBold, modifier = Modifier.padding(top = 6.dp))
}
