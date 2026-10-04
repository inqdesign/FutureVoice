package com.roro.futurevoice.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.roro.futurevoice.R
import com.roro.futurevoice.data.CefrLevel

/**
 * What the level in the call header changes (iOS `LevelInfoSheet`, talk
 * surface): how the future self pitches its words, the band table with the
 * learner's own band ticked, and that the level is measured, not set by hand.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LevelInfoSheet(level: CefrLevel, onDismiss: () -> Unit) {
    val bands = listOf(
        Triple("A1 · A2", listOf(CefrLevel.A1, CefrLevel.A2), R.string.the_most_ordinary_everyday_words_one_clause_sentences_rarely_3dc042),
        Triple("B1 · B2", listOf(CefrLevel.B1, CefrLevel.B2), R.string.everyday_words_plus_the_common_idioms_and_phrasal_verbs_subo_b2b74a),
        Triple("C1 · C2", listOf(CefrLevel.C1, CefrLevel.C2), R.string.the_full_range_idiom_precise_nuance_register_shifts_asides_a_e48bdb),
    )
    ModalBottomSheet(
        sheetState = androidx.compose.material3.rememberModalBottomSheetState(skipPartiallyExpanded = true),onDismissRequest = onDismiss) {
        Column(Modifier.fillMaxWidth().padding(horizontal = 20.dp).padding(bottom = 24.dp).navigationBarsPadding(),
            verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Header(stringResource(R.string.how_your_future_self_talks))
            Text(stringResource(R.string.your_future_self_speaks_mostly_at_your_level_and_lets_a_word_2bb6d2),
                style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Header(stringResource(R.string.by_level))
            bands.forEach { (band, levels, detail) ->
                Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text(band, style = MaterialTheme.typography.titleSmall, modifier = Modifier.width(62.dp))
                    Text(stringResource(detail), style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.weight(1f))
                    if (level in levels) Icon(Icons.Filled.Check, contentDescription = null,
                        tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(16.dp))
                }
            }
            Text(stringResource(R.string.every_level_gets_the_same_length_and_the_same_amount_of_subs_ff323e),
                style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Header(stringResource(R.string.how_your_level_moves))
            Text(stringResource(R.string.your_level_is_measured_from_the_talks_you_actually_have_it_i_4769ab),
                style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
private fun Header(text: String) {
    Text(text.uppercase(), style = MaterialTheme.typography.labelSmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(top = 10.dp))
}
