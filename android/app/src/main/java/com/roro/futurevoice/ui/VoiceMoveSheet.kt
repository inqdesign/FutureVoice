package com.roro.futurevoice.ui

import android.content.Context
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.GraphicEq
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
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
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.roro.futurevoice.R
import com.roro.futurevoice.audio.Mp3Player
import com.roro.futurevoice.data.AuthRepository
import com.roro.futurevoice.data.VoiceAccentCatalog
import com.roro.futurevoice.net.ElevenLabsClient
import com.roro.futurevoice.net.VoiceRemixClient
import kotlinx.coroutines.launch

/**
 * "Your voice is moving to a new engine" — iOS `VoiceMoveSheet` (2026-10-12).
 * The one-time move from an ElevenLabs clone to a Cartesia one: says the old
 * voice is deleted, keeps or picks an accent, rebuilds from the recording on
 * this device (the server clones on Cartesia), and applies the accent onto the
 * new voice as "<uuid>:<accent>". Names neither company — "Learn more" opens
 * the privacy page's processor list. Shown at most once a day ([VoiceMove]).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun VoiceMoveSheet(
    targetLanguage: String,
    currentAccentId: String?,
    onRebuilt: (String) -> Unit,
    onAccentApplied: (voiceId: String, accentId: String) -> Unit,
    currentVoiceId: () -> String?,
    onDismiss: () -> Unit,
) {
    val context = LocalContext.current
    val uri = LocalUriHandler.current
    val scope = rememberCoroutineScope()
    val options = remember(targetLanguage) { VoiceAccentCatalog.options(targetLanguage) }
    val hasRecording = remember { VoiceComparison.exists(context.filesDir) }
    var accentId by remember {
        mutableStateOf(currentAccentId?.takeIf { it.isNotEmpty() }
            ?: VoiceAccentCatalog.defaultAccent(targetLanguage)?.id)
    }
    var working by remember { mutableStateOf(false) }
    var done by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val player = remember { Mp3Player(context.cacheDir, source = "voice_move") }
    DisposableEffect(Unit) { onDispose { runCatching { player.stop() } } }
    LaunchedEffect(Unit) {
        VoiceMove.markShown(context)
        com.roro.futurevoice.core.Analytics.capture("voice_move_shown", mapOf("has_recording" to hasRecording))
    }

    fun playSample() {
        val id = currentVoiceId() ?: return
        scope.launch {
            runCatching {
                val data = ElevenLabsClient(AuthRepository()).synthesize(
                    voiceId = id, text = VoiceAccentCatalog.sampleText(targetLanguage),
                    purpose = "voice_comparison")
                player.play(data)
            }
        }
    }

    fun move() {
        if (working) return
        working = true; error = null
        val accent = options.firstOrNull { it.id == accentId }
        com.roro.futurevoice.core.Analytics.capture("voice_move_started", mapOf("accent" to (accent?.id ?: "original")))
        scope.launch {
            runCatching {
                val name = com.roro.futurevoice.data.VoiceName.display(context,
                    com.roro.futurevoice.data.PersonaStore.shared(context).load()?.displayName)
                // The server clones on Cartesia (CLONE_PROVIDER).
                val newId = com.roro.futurevoice.net.VoiceCloneClient(AuthRepository()).cloneVoice(
                    name = name, sample = VoiceComparison.sampleFile(context.filesDir),
                    removeBackgroundNoise = false)
                onRebuilt(newId)
                val cartesiaAccent = accent?.let { VoiceMove.cartesiaAccent(it.id) }
                if (accent != null && cartesiaAccent != null) {
                    // On Cartesia an accent is a setting on the same voice.
                    val accented = VoiceRemixClient(AuthRepository())
                        .save("$newId:$cartesiaAccent", name, accent.prompt)
                    onAccentApplied(accented, accent.id)
                }
            }.onSuccess {
                com.roro.futurevoice.core.Analytics.capture("voice_move_done", mapOf("accent" to (accent?.id ?: "original")))
                done = true
                playSample()
            }.onFailure {
                com.roro.futurevoice.core.Analytics.capture("voice_move_failed", mapOf("reason" to (it.localizedMessage ?: "").take(200)))
                error = it.localizedMessage ?: it.toString()
            }
            working = false
        }
    }

    ModalBottomSheet(
        sheetState = androidx.compose.material3.rememberModalBottomSheetState(skipPartiallyExpanded = true),
        onDismissRequest = { if (!working) onDismiss() },
    ) {
        Column(
            Modifier.sheetBody().padding(horizontal = 24.dp).padding(top = 8.dp, bottom = 28.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Icon(Icons.Filled.GraphicEq, contentDescription = null,
                modifier = Modifier.size(34.dp), tint = MaterialTheme.colorScheme.primary)
            Text(stringResource(if (done) R.string.voice_move_done_title else R.string.voice_move_title),
                style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold)
            if (done) {
                Text(stringResource(R.string.voice_move_done_body),
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                TextButton(onClick = { playSample() }) { Text(stringResource(R.string.hear_it)) }
                Button(onClick = onDismiss, modifier = Modifier.fillMaxWidth()) { Text(stringResource(R.string.done)) }
                return@Column
            }
            Text(stringResource(R.string.voice_move_body))
            Text(stringResource(R.string.voice_move_loss), color = MaterialTheme.colorScheme.onSurfaceVariant)
            Text(stringResource(R.string.voice_move_learn_more),
                color = MaterialTheme.colorScheme.primary,
                modifier = Modifier.clickable { uri.openUri(com.roro.futurevoice.data.ConsentStore.privacyUrl() + "#processors") })
            if (options.isNotEmpty()) {
                Text(stringResource(R.string.accent), style = MaterialTheme.typography.titleSmall)
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    FilterChip(selected = accentId == null, enabled = !working,
                        onClick = { accentId = null },
                        label = { Text(stringResource(R.string.accent_original)) })
                    options.forEach { o ->
                        FilterChip(selected = accentId == o.id, enabled = !working,
                            onClick = { accentId = o.id }, label = { Text(accentLabel(o)) })
                    }
                }
            }
            if (hasRecording) {
                Button(onClick = { move() }, enabled = !working, modifier = Modifier.fillMaxWidth()) {
                    if (working) CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp)
                    else Text(stringResource(R.string.voice_move_cta))
                }
            } else {
                Text(stringResource(R.string.voice_move_no_recording),
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            TextButton(onClick = {
                com.roro.futurevoice.core.Analytics.capture("voice_move_later")
                onDismiss()
            }, enabled = !working, modifier = Modifier.align(Alignment.CenterHorizontally)) {
                Text(stringResource(R.string.later))
            }
            error?.let { Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall) }
        }
    }
}

/** When the move sheet is due, and the accent ids it maps (iOS `VoiceMove`). */
object VoiceMove {
    private const val SHOWN_KEY = "futurevoice.voiceMove.lastShown"
    private val CARTESIA = Regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}(:[a-z-]+)?$")

    fun isCartesia(id: String) = CARTESIA.matches(id)

    fun isDue(context: Context, voiceId: String?, signedIn: Boolean): Boolean {
        if (!signedIn || voiceId == null || isCartesia(voiceId)) return false
        if (com.roro.futurevoice.data.VoiceParking.isParked(voiceId)) return false
        val last = prefs(context).getLong(SHOWN_KEY, 0L)
        if (last > 0 && android.text.format.DateUtils.isToday(last)) return false
        return true
    }

    fun markShown(context: Context) {
        prefs(context).edit().putLong(SHOWN_KEY, System.currentTimeMillis()).apply()
    }

    fun cartesiaAccent(appAccentId: String): String? = when (appAccentId) {
        "en-US" -> "general-american"
        "en-GB" -> "british"
        "en-AU" -> "australian"
        "de-DE" -> "standard-german"
        else -> null
    }

    private fun prefs(context: Context) =
        context.getSharedPreferences("futurevoice", Context.MODE_PRIVATE)
}
