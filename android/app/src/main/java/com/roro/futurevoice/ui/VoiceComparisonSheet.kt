package com.roro.futurevoice.ui

import android.media.AudioAttributes
import android.media.MediaPlayer
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
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
import com.roro.futurevoice.ui.brand.IosOutlinedButton as OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.lifecycle.compose.collectAsStateWithLifecycle
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
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import com.roro.futurevoice.ui.brand.AppSurfaces
import com.roro.futurevoice.ui.brand.IosGlassTextButton
import com.roro.futurevoice.R
import com.roro.futurevoice.audio.Mp3Player
import com.roro.futurevoice.data.AuthRepository
import com.roro.futurevoice.net.VoiceClient
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

    /** Which language the recording was read in (iOS
     *  `AppState.cloneScriptLanguage`), so the comparison can put the same
     *  words on both sides. A rebuild from the saved sample leaves it alone —
     *  same recording, same script. Null = before this was kept. */
    private const val SCRIPT_LANGUAGE_KEY = "futurevoice.cloneScriptLanguage"
    fun scriptLanguage(context: android.content.Context): String? =
        context.getSharedPreferences("futurevoice", 0).getString(SCRIPT_LANGUAGE_KEY, null)
    fun setScriptLanguage(context: android.content.Context, code: String) {
        context.getSharedPreferences("futurevoice", 0).edit().putString(SCRIPT_LANGUAGE_KEY, code).apply()
    }

    /** The opening of the script the learner READ, trimmed to ~10 s of
     *  speech (iOS `VoiceCloneScript.comparisonOpening`): a take read in
     *  another language is compared in that language. */
    fun opening(scriptLanguage: String?, targetLanguage: String): String {
        val paragraphs = scriptLanguage
            ?.takeIf { !com.roro.futurevoice.data.LanguageCatalog.sameLanguage(it, targetLanguage) }
            ?.let { com.roro.futurevoice.talk.CloneScriptStore.handAuthored(it) }
            ?: VoiceCloneScript.paragraphs(targetLanguage)
        val text = paragraphs.firstOrNull() ?: ""
        if (text.length <= 120) return text
        val head = text.take(160)
        val stop = head.indexOfLast { it in ".?!。？！" }
        return if (stop > 40) head.substring(0, stop + 1) else text.take(120)
    }

    /** How much of the recording to play: the take runs 60–90 s; only its
     *  opening is the same words the clone says. */
    const val SAMPLE_WINDOW_MS = 12_000L
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun VoiceComparisonSheet(
    voiceId: String,
    targetLanguage: String,
    /** The app language, for naming the recording's language. */
    nativeLanguage: String,
    /** What the take was read in; null = the stored answer. */
    scriptLanguage: String? = null,
    onRerecord: () -> Unit,
    onDismiss: () -> Unit,
) {
    val changeStatus by com.roro.futurevoice.data.VoiceChanges.status
        .collectAsStateWithLifecycle()
    val canChange = changeStatus?.canChange ?: true
    androidx.compose.runtime.LaunchedEffect(Unit) { com.roro.futurevoice.data.VoiceChanges.refresh() }
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val readLanguage = remember(scriptLanguage) { scriptLanguage ?: VoiceComparison.scriptLanguage(context) }
    val opening = remember(readLanguage, targetLanguage) { VoiceComparison.opening(readLanguage, targetLanguage) }
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
        val cache = File(context.filesDir, "voice/comparison-${voiceId.hashCode()}-${opening.hashCode()}.mp3")
        if (cache.length() > 0) { cloneAudio = withContext(Dispatchers.IO) { cache.readBytes() }; return@LaunchedEffect }
        loading = true
        runCatching {
            VoiceClient(AuthRepository()).synthesize(voiceId, opening,
                purpose = "voice_comparison")
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
    // iOS: a List under an inline title with Done — the two voices and the
    // line they both say in one card, then the verdict in its own.
    ModalBottomSheet(
        sheetState = com.roro.futurevoice.ui.rememberModalBottomSheetState(skipPartiallyExpanded = true),
        onDismissRequest = { stopAll(); onDismiss() },
        containerColor = AppSurfaces.ground,
    ) {
        SheetHeader(
            title = stringResource(R.string.same_words_both_voices),
            leading = { IosGlassTextButton(stringResource(R.string.done), onClick = { stopAll(); onDismiss() }) },
            modifier = Modifier.padding(horizontal = 16.dp).padding(top = 4.dp, bottom = 8.dp),
        )
        Column(Modifier.sheetBody().padding(horizontal = 16.dp).padding(bottom = 28.dp)) {
            Column(Modifier.fillMaxWidth().padding(top = 20.dp)) {
                FormCard {
                    Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp).padding(top = 15.dp, bottom = 11.dp),
                        horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        Side(stringResource(R.string.my_recording), playingMine,
                            ready = VoiceComparison.exists(context.filesDir), loading = false,
                            Modifier.weight(1f)) { toggleMine() }
                        Side(stringResource(R.string.the_made_voice), playingClone,
                            ready = cloneAudio != null, loading = loading,
                            Modifier.weight(1f)) { toggleClone() }
                    }
                    GroupedRowDivider(inset = false)
                    Text("\u201C$opening\u201D", style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(horizontal = 16.dp, vertical = 11.dp))
                }
                GroupedFooter(stringResource(R.string.tap_one_then_the_other_listen_for_the_voice_not_the_words_ev_f4a3b5))
                // The comparison speaks whatever the recording holds, which
                // for a native-script take is NOT the language being learned.
                if (readLanguage != null &&
                    !com.roro.futurevoice.data.LanguageCatalog.sameLanguage(readLanguage, targetLanguage)) {
                    Spacer(Modifier.height(8.dp))
                    GroupedFooter(stringResource(R.string.the_recording_is_in_so_the_comparison_is_too_if_the_two_matc_1a0886,
                        com.roro.futurevoice.data.LanguageCatalog.ownName(readLanguage, nativeLanguage)))
                }
            }
            FormSection(header = null, footer = if (canChange)
                stringResource(R.string.the_voice_you_have_now_is_only_replaced_if_you_keep_the_new_2247d6)
                else com.roro.futurevoice.data.VoiceChangeStatus.againLine(context, changeStatus?.nextAt)) {
                MeRow(Icons.Filled.Check, stringResource(R.string.it_s_me_keep_it), kind = MeRowKind.ACTION,
                    onClick = { stopAll(); onDismiss() })
                GroupedRowDivider()
                // Dismiss first: the caller walks to the record step, and a
                // sheet still up over that transition is a stale comparison.
                // A re-record is the learner's one change for 30 days; with
                // none left the button would lead to a minute of reading and
                // a refusal (iOS 2026-10-09).
                MeRow(Icons.Filled.Mic, stringResource(R.string.not_me_record_again),
                    kind = MeRowKind.DESTRUCTIVE_LABEL, enabled = canChange,
                    onClick = { stopAll(); onDismiss(); onRerecord() })
            }
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
