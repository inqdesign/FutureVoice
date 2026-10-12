package com.roro.futurevoice.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.StopCircle
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material.icons.outlined.PlayCircle
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.roro.futurevoice.R
import com.roro.futurevoice.audio.Mp3Player
import com.roro.futurevoice.talk.StockPerson
import com.roro.futurevoice.talk.VoicePreset
import com.roro.futurevoice.talk.nameIn
import kotlinx.coroutines.launch

/**
 * The four preset voices, to pick the one that speaks while the learner's
 * own voice is queued (iOS `StandInVoicePicker`, 2026-10-10: the account's
 * monthly voices were spent at signup). Inline rows rather than
 * [VoicePresetPicker]'s list, so it sits under the onboarding copy; the
 * preview clip is the same. Tapping a row picks it AND plays it — the choice
 * is made by ear.
 */
@Composable
internal fun StandInVoicePicker(
    selection: String?,
    targetLanguage: String,
    onChoose: (String) -> Unit,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val player = remember { Mp3Player(context.cacheDir, source = "voice_preview") }
    var loadingId by remember { mutableStateOf<String?>(null) }
    var playingId by remember { mutableStateOf<String?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    DisposableEffect(Unit) { onDispose { player.stop() } }

    fun preview(id: String, restart: Boolean = false) {
        if (!restart && playingId == id) { player.stop(); playingId = null; return }
        player.stop(); playingId = null; error = null
        scope.launch {
            loadingId = id
            val audio = runCatching { VoicePreset.previewAudio(context, id, targetLanguage) }.getOrNull()
            loadingId = null
            if (audio == null) {
                error = context.getString(R.string.couldn_t_play_the_sample_check_your_connection)
                return@launch
            }
            playingId = id
            player.play(audio)
            if (playingId == id) playingId = null
        }
    }

    Column(Modifier.fillMaxWidth().padding(horizontal = 32.dp)) {
        StockPerson.catalog.forEachIndexed { index, preset ->
            if (index > 0) HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
            Row(
                Modifier.fillMaxWidth()
                    .clickable { onChoose(preset.voiceId); preview(preset.voiceId, restart = true) }
                    .padding(vertical = 6.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Box(Modifier.size(28.dp).clip(CircleShape).clickable { preview(preset.voiceId) },
                    contentAlignment = Alignment.Center) {
                    if (loadingId == preset.voiceId) {
                        CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
                    } else {
                        Icon(if (playingId == preset.voiceId) Icons.Filled.StopCircle else Icons.Outlined.PlayCircle,
                            contentDescription = if (playingId == preset.voiceId)
                                stringResource(R.string.stop_preview)
                            else stringResource(R.string.preview, preset.nameIn(targetLanguage)),
                            tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(28.dp))
                    }
                }
                Spacer(Modifier.width(12.dp))
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(preset.nameIn(targetLanguage), style = MaterialTheme.typography.bodyLarge)
                    Text(VoicePreset.caption(context, preset.voiceId, targetLanguage),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                if (selection == preset.voiceId) {
                    Icon(Icons.Filled.Check, contentDescription = null,
                        tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(22.dp))
                }
            }
        }
        error?.let {
            Row(Modifier.padding(top = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Filled.Warning, null, Modifier.size(14.dp), tint = MaterialTheme.colorScheme.error)
                Spacer(Modifier.width(4.dp))
                Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error,
                    fontWeight = FontWeight.Normal)
            }
        }
    }
}
