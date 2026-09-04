package com.roro.futurevoice.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
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
import com.roro.futurevoice.audio.Mp3Player
import com.roro.futurevoice.data.AuthRepository
import com.roro.futurevoice.data.VoiceAccent
import com.roro.futurevoice.data.VoiceAccentCatalog
import com.roro.futurevoice.net.VoiceRemixClient
import kotlinx.coroutines.launch

/**
 * Accent picker for the cloned voice — pick an accent, audition a few remix
 * takes of your OWN clone speaking with it, keep the one that sounds most
 * like you.
 *
 * It exists because a clone recorded in the learner's NATIVE language carries
 * no target-language accent at all, and the TTS model fills that gap with its
 * own default (US English for `en`) — wrong for a learner living in London.
 *
 * **Generate, audition, then choose explicitly.** No take is adopted just by
 * being played: remixing REPLACES the live clone and deletes the outgoing
 * voice upstream, so applying one is not something to do by accident.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun VoiceAccentSheet(
    voiceId: String,
    targetLanguage: String,
    /** The accent the live clone was remixed with, if any. */
    appliedAccentId: String?,
    onApplied: (voiceId: String, accentId: String) -> Unit,
    onDismiss: () -> Unit,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val client = remember { VoiceRemixClient(AuthRepository()) }
    val player = remember { Mp3Player(context.cacheDir) }

    val options = remember(targetLanguage) { VoiceAccentCatalog.options(targetLanguage) }
    var accent by remember { mutableStateOf<VoiceAccent?>(null) }
    var previews by remember { mutableStateOf<List<VoiceRemixClient.Preview>>(emptyList()) }
    var picked by remember { mutableStateOf<String?>(null) }
    var playing by remember { mutableStateOf<String?>(null) }
    var generating by remember { mutableStateOf(false) }
    var saving by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }

    DisposableEffect(Unit) { onDispose { runCatching { player.stop() } } }

    ModalBottomSheet(onDismissRequest = { if (!saving && !generating) onDismiss() }) {
        Column(
            Modifier.fillMaxWidth().navigationBarsPadding()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp).padding(bottom = 28.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Text(stringResource(R.string.accent), style = MaterialTheme.typography.titleLarge)
            Text(stringResource(R.string.your_clone_speaking_with_a_different_accent),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant)

            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                options.forEach { o ->
                    FilterChip(
                        selected = accent?.id == o.id,
                        onClick = {
                            // A new accent invalidates the takes on screen —
                            // keeping them would let a British take be applied
                            // under an American label.
                            accent = o; previews = emptyList(); picked = null; error = null
                        },
                        label = {
                            Text(if (o.id == appliedAccentId) "${o.label} ✓" else o.label)
                        },
                    )
                }
            }

            val chosen = accent
            if (chosen != null && previews.isEmpty()) {
                Button(
                    onClick = {
                        generating = true; error = null
                        scope.launch {
                            runCatching {
                                client.previews(voiceId, chosen.prompt,
                                    VoiceAccentCatalog.sampleText(targetLanguage))
                            }.onSuccess { previews = it }
                                .onFailure {
                                    error = context.getString(R.string.couldnt_make_the_takes_try_again)
                                }
                            generating = false
                        }
                    },
                    enabled = !generating,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    if (generating) {
                        Row(verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp)
                            Text(stringResource(R.string.making_a_few_takes))
                        }
                    } else Text(stringResource(R.string.hear_some_takes))
                }
            }

            if (previews.isNotEmpty()) {
                HorizontalDivider()
                Text(stringResource(R.string.pick_the_one_that_sounds_most_like_you),
                    style = MaterialTheme.typography.titleSmall)
                previews.forEachIndexed { i, p ->
                    Row(
                        Modifier.fillMaxWidth()
                            .selectable(selected = picked == p.id, onClick = { picked = p.id })
                            .padding(vertical = 4.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        RadioButton(selected = picked == p.id, onClick = null)
                        Text(stringResource(R.string.take_lld, i + 1), Modifier.weight(1f))
                        IconButton(onClick = {
                            scope.launch {
                                if (playing == p.id) { player.stop(); playing = null }
                                else {
                                    playing = p.id
                                    runCatching { player.play(p.audio) }
                                    playing = null
                                }
                            }
                        }) {
                            Icon(
                                if (playing == p.id) Icons.Filled.Stop else Icons.Filled.PlayArrow,
                                contentDescription = stringResource(
                                    if (playing == p.id) R.string.stop else R.string.play),
                            )
                        }
                    }
                }

                Button(
                    onClick = {
                        val id = picked ?: return@Button
                        saving = true; error = null
                        scope.launch {
                            runCatching {
                                client.save(id, "nawana clone", chosen?.prompt.orEmpty())
                            }.onSuccess { newId ->
                                onApplied(newId, chosen?.id.orEmpty())
                                onDismiss()
                            }.onFailure {
                                error = context.getString(R.string.couldnt_apply_that_take_try_again)
                            }
                            saving = false
                        }
                    },
                    enabled = picked != null && !saving,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    if (saving) CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp)
                    else Text(stringResource(R.string.use_this_take))
                }
                // Said out loud because it can't be undone from here: the old
                // voice is deleted upstream, and the only way back is a fresh
                // clone from the saved recording.
                Text(stringResource(R.string.this_replaces_your_current_voice),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                OutlinedButton(
                    onClick = { previews = emptyList(); picked = null },
                    enabled = !saving,
                    modifier = Modifier.fillMaxWidth(),
                ) { Text(stringResource(R.string.try_again)) }
            }

            error?.let {
                Text(it, style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.error)
            }
        }
    }
}
