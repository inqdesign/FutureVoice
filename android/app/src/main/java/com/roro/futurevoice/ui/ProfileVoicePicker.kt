package com.roro.futurevoice.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.StopCircle
import androidx.compose.material.icons.outlined.PlayCircle
import androidx.compose.material3.CircularProgressIndicator
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
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.roro.futurevoice.R
import com.roro.futurevoice.audio.Mp3Player
import com.roro.futurevoice.talk.ProfileVoice
import kotlinx.coroutines.launch

/**
 * The voice "you" speak with in other learners' Find people (iOS
 * `ProfileVoiceRows`, 2026-10-12): voices from the learner's own country
 * first ([ProfileVoice]), two women and two men where there are that many.
 * Rows inside a host's grouped card, ▶ to hear one in the language being
 * learned, tap to pick. Nothing is picked for them — the app can't tell a
 * voice's gender from a name.
 */
@Composable
fun ProfileVoiceRows(
    selection: String?,
    onSelect: (String) -> Unit,
    nativeLanguage: String,
    targetLanguage: String,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val player = remember { Mp3Player(context.cacheDir, source = "voice_preview") }
    var loadingId by remember { mutableStateOf<String?>(null) }
    var playingId by remember { mutableStateOf<String?>(null) }
    DisposableEffect(Unit) { onDispose { player.stop() } }
    val options = remember(nativeLanguage) { ProfileVoice.options(nativeLanguage) }

    fun preview(voice: ProfileVoice) {
        if (playingId == voice.id) { player.stop(); playingId = null; return }
        player.stop(); playingId = null
        scope.launch {
            loadingId = voice.id
            val audio = runCatching {
                com.roro.futurevoice.data.cachedSynthesis(context, voiceId = voice.id,
                    text = voicePreviewLine(targetLanguage), purpose = "voice_preview", allowLineage = false)
            }.getOrNull()
            loadingId = null
            if (audio == null) return@launch
            playingId = voice.id
            player.play(audio)
            if (playingId == voice.id) playingId = null
        }
    }

    options.forEachIndexed { i, voice ->
        if (i > 0) GroupedRowDivider(inset = false)
        Row(
            Modifier.fillMaxWidth().clickable { onSelect(voice.id) }
                .padding(start = 12.dp, end = 16.dp, top = 8.dp, bottom = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            val previewLabel = stringResource(R.string.preview, voice.name)
            Box(Modifier.size(32.dp).clip(CircleShape).clickable { preview(voice) }
                .semantics { contentDescription = previewLabel },
                contentAlignment = Alignment.Center) {
                if (loadingId == voice.id) {
                    CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
                } else {
                    Icon(if (playingId == voice.id) Icons.Filled.StopCircle else Icons.Outlined.PlayCircle,
                        contentDescription = null, tint = MaterialTheme.colorScheme.primary,
                        modifier = Modifier.size(28.dp))
                }
            }
            Column(Modifier.weight(1f)) {
                Text(voice.name, style = MaterialTheme.typography.bodyLarge)
                Text(stringResource(if (voice.gender == ProfileVoice.Gender.FEMALE) R.string.woman else R.string.man),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            if (selection == voice.id) {
                Icon(Icons.Filled.Check, contentDescription = null,
                    tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(22.dp))
            }
        }
    }
}

