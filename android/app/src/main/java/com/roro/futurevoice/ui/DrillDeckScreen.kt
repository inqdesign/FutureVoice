package com.roro.futurevoice.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.roro.futurevoice.R
import com.roro.futurevoice.data.DrillStore
import com.roro.futurevoice.data.StoreEvents
import com.roro.futurevoice.talk.DrillCard
import kotlinx.coroutines.launch
import androidx.compose.runtime.rememberCoroutineScope

/**
 * The drill deck, reduced to its SRS spine (`DrillSheet` v1): the learner's
 * own slip on the front — say it out loud, tap to check — the fluent line +
 * reason on the back, then "Got it" (graduates, iOS rule) or demote. TTS,
 * folders and snooze bins arrive with the Practice pass.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DrillDeckScreen(language: String, onBack: () -> Unit) {
    androidx.activity.compose.BackHandler(onBack = onBack)
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val store = remember { DrillStore.shared(context) }
    var deck by remember { mutableStateOf<List<DrillCard>>(emptyList()) }
    var index by remember { mutableIntStateOf(0) }
    var revealed by remember { mutableStateOf(false) }
    LaunchedEffect(language) { deck = store.due(language) }

    fun grade(known: Boolean) {
        val card = deck.getOrNull(index) ?: return
        scope.launch {
            if (known) store.markKnown(card, language) else store.markIncorrect(card, language)
            StoreEvents.bump()
        }
        revealed = false
        index += 1
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.review_cards)) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = null)
                    }
                },
            )
        }
    ) { padding ->
        Column(
            Modifier.padding(padding).fillMaxSize().padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            if (deck.isEmpty() || index >= deck.size) {
                Text(stringResource(R.string.done_for_today),
                    style = MaterialTheme.typography.titleMedium)
                return@Column
            }
            LinearProgressIndicator(
                progress = { index / deck.size.toFloat() },
                modifier = Modifier.fillMaxWidth(),
            )
            val card = deck[index]
            Card(Modifier.fillMaxWidth().clickable { revealed = true }) {
                Column(Modifier.fillMaxWidth().padding(20.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    if (card.sourcePhrase.isNotBlank()) {
                        Text(card.sourcePhrase, style = MaterialTheme.typography.bodyLarge)
                    }
                    if (revealed) {
                        Text(card.targetPhrase, style = MaterialTheme.typography.titleMedium,
                            color = MaterialTheme.colorScheme.primary)
                        if (card.reason.isNotBlank()) {
                            Text(card.reason, style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    } else {
                        Text(stringResource(
                            if (card.sourcePhrase.isBlank()) R.string.tap_to_reveal
                            else R.string.say_it_out_loud_then_tap_the_card_to_check),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
            if (revealed) {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    OutlinedButton(onClick = { grade(known = false) }, modifier = Modifier.weight(1f)) {
                        Text(stringResource(R.string.not_yet))
                    }
                    Button(onClick = { grade(known = true) }, modifier = Modifier.weight(1f)) {
                        Text(stringResource(R.string.got_it))
                    }
                }
            }
        }
    }
}
