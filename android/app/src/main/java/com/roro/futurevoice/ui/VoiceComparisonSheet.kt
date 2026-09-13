package com.roro.futurevoice.ui

import android.media.AudioAttributes
import android.media.MediaPlayer
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.roro.futurevoice.R
import com.roro.futurevoice.audio.Mp3Player
import com.roro.futurevoice.data.AuthRepository
import com.roro.futurevoice.net.ElevenLabsClient
import com.roro.futurevoice.talk.VoiceCloneScript
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

/**
 * A/B the recording against the clone built from it — iOS
 * `VoiceComparisonSheet`. "It doesn't sound like me" is judged against a
 * memory of one's own voice, which everybody finds strange; put the two side
 * by side on the SAME sentence and the question answers itself.
 *
 * Both sides speak the opening of the script the learner read. The clone's
 * line is synthesized once (fidelity model, cached on disk under the voice),
 * so reopening costs nothing.
 */
object VoiceComparison {
    fun sampleFile(filesDir: File) = File(filesDir, "voice/clone-sample.wav")
    fun exists(filesDir: File) = sampleFile(filesDir).length() > 0

    /** The script's first paragraph, trimmed to ~10 s of speech as on iOS. */
    fun opening(targetLanguage: String): String {
        val text = VoiceCloneScript.paragraphs(targetLanguage).firstOrNull() ?: ""
        if (text.length <= 120) return text
        val head = text.take(160)
        val stop = head.indexOfLast { it in ".?!。？！" }
        return if (stop > 40) head.substring(0, stop + 1) else head
    }

    /** How much of the recording to play: the take runs 60–90 s; only its
     *  opening is the same words the clone says. */
    const val SAMPLE_WINDOW_MS = 12_000L
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun VoiceComparisonSheet(voiceId: String, targetLanguage: String, onRerecord: () -> Unit, onDismiss: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val opening = remember(targetLanguage) { VoiceComparison.opening(targetLanguage) }
    val clonePlayer = remember { Mp3Player(context.cacheDir, source = "voice_comparison") }
    var mine by remember { mutableStateOf<MediaPlayer?>(null) }
    var mineJob by remember { mutableStateOf<Job?>(null) }
    var playingMine by remember { mutableStateOf(false) }
    var playingClone by remember { mutableStateOf(false) }
    var cloneAudio by remember { mutableStateOf<ByteArray?>(null) }
    var loading by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }

    fun stopAll() {
        mineJob?.cancel(); mineJob = null
        mine?.let { runCatching { it.stop() }; it.release() }; mine = null
        playingMine = false
        clonePlayer.stop(); playingClone = false
    }
    DisposableEffect(Unit) { onDispose { stopAll() } }

    // Cache first — this sheet is opened exactly when someone is unsure,
    // which is also when they open it twice.
    LaunchedEffect(voiceId) {
        val cache = File(context.filesDir, "voice/comparison-${voiceId.hashCode()}.mp3")
        if (cache.length() > 0) { cloneAudio = withContext(Dispatchers.IO) { cache.readBytes() }; return@LaunchedEffect }
        loading = true
        runCatching {
            ElevenLabsClient(AuthRepository()).synthesize(voiceId, opening,
                modelId = ElevenLabsClient.FIDELITY_MODEL_ID, purpose = "voice_comparison")
        }.onSuccess { data ->
            cloneAudio = data
            withContext(Dispatchers.IO) { cache.parentFile?.mkdirs(); cache.writeBytes(data) }
        }.onFailure { error = it.message ?: "" }
        loading = false
    }

    // One at a time, always — comparing means alternating.
    fun toggleMine() {
        if (playingMine) { stopAll(); return }
        stopAll()
        runCatching {
            val mp = MediaPlayer().apply {
                setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build())
                setDataSource(VoiceComparison.sampleFile(context.filesDir).absolutePath)
                setOnCompletionListener { playingMine = false }
                prepare(); start()
            }
            mine = mp; playingMine = true
            mineJob = scope.launch { delay(VoiceComparison.SAMPLE_WINDOW_MS); if (playingMine) stopAll() }
        }.onFailure { error = it.message ?: "" }
    }
    fun toggleClone() {
        if (playingClone) { stopAll(); return }
        stopAll()
        val data = cloneAudio ?: return
        playingClone = true
        scope.launch { runCatching { clonePlayer.play(data) }.onFailure { error = it.message ?: "" }; playingClone = false }
    }

    error?.let {
        AlertDialog(onDismissRequest = { error = null }, title = { Text(stringResource(R.string.couldn_t_play_the_comparison)) },
            text = { Text(it) }, confirmButton = { TextButton(onClick = { error = null }) { Text(stringResource(R.string.ok)) } })
    }
    ModalBottomSheet(onDismissRequest = { stopAll(); onDismiss() }) {
        Column(Modifier.fillMaxWidth().navigationBarsPadding().padding(horizontal = 20.dp).padding(bottom = 28.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text(stringResource(R.string.same_words_both_voices), style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold)
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Side(stringResource(R.string.my_recording), playingMine, ready = VoiceComparison.exists(context.filesDir), loading = false,
                    Modifier.weight(1f)) { toggleMine() }
                Side(stringResource(R.string.the_made_voice), playingClone, ready = cloneAudio != null, loading = loading,
                    Modifier.weight(1f)) { toggleClone() }
            }
            Text("\u201C$opening\u201D", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            GroupedFooter(stringResource(R.string.tap_one_then_the_other_listen_for_the_voice_not_the_words_ev_f4a3b5))
            GroupedSectionSpacer()
            GroupedCard {
                Row(Modifier.fillMaxWidth().padding(4.dp), verticalAlignment = Alignment.CenterVertically) {
                    TextButton(onClick = { stopAll(); onDismiss() }, modifier = Modifier.fillMaxWidth()) {
                        Icon(Icons.Filled.Check, contentDescription = null); Text("  " + stringResource(R.string.it_s_me_keep_it))
                    }
                }
                GroupedRowDivider(inset = false)
                Row(Modifier.fillMaxWidth().padding(4.dp), verticalAlignment = Alignment.CenterVertically) {
                    // Dismiss first: the caller walks to the record step, and a
                    // sheet still up over that transition is a stale comparison.
                    TextButton(onClick = { stopAll(); onDismiss(); onRerecord() }, modifier = Modifier.fillMaxWidth()) {
                        Icon(Icons.Filled.Mic, contentDescription = null, tint = MaterialTheme.colorScheme.error)
                        Text("  " + stringResource(R.string.not_me_record_again), color = MaterialTheme.colorScheme.error)
                    }
                }
            }
            GroupedFooter(stringResource(R.string.recording_again_during_setup_is_free_and_the_voice_you_have_75a508))
        }
    }
}

@Composable
private fun Side(label: String, playing: Boolean, ready: Boolean, loading: Boolean, modifier: Modifier, onClick: () -> Unit) {
    OutlinedButton(onClick = onClick, enabled = ready, modifier = modifier.heightIn(min = 76.dp)) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
            if (loading) CircularProgressIndicator(Modifier.size(22.dp), strokeWidth = 2.dp)
            else Icon(if (playing) Icons.Filled.Stop else Icons.Filled.PlayArrow, contentDescription = null)
            Text(label, style = MaterialTheme.typography.labelLarge)
        }
    }
}
