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
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.GraphicEq
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
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
 * the privacy page's processor list. Shown on every open while the live voice
 * is an ElevenLabs one ([VoiceMove]), with no Later: the move is required
 * (iOS 2026-10-13).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun VoiceMoveSheet(
    targetLanguage: String,
    currentAccentId: String?,
    onRebuilt: (String) -> Unit,
    onAccentApplied: (voiceId: String, accentId: String) -> Unit,
    currentVoiceId: () -> String?,
    /** A voice the server rebuilt from its own copy of the recording (iOS
     *  `AppState.adoptMovedVoice`, `f1aa915`). */
    onMoved: (String) -> Unit = onRebuilt,
    /** What the recording screen offers to read in. */
    nativeLanguage: String = targetLanguage,
    /** Neither phone nor server holds the recording: a re-record (the
     *  recording screen on its own, never the onboarding) made this voice. */
    onVoiceRecorded: (String) -> Unit = onRebuilt,
    onDismiss: () -> Unit,
) {
    val context = LocalContext.current
    val uri = LocalUriHandler.current
    val scope = rememberCoroutineScope()
    val options = remember(targetLanguage) { VoiceAccentCatalog.options(targetLanguage) }
    val hasRecording = remember { VoiceComparison.exists(context.filesDir) }
    // The accent they have; else the one picked in setup (since 2026-10-08 —
    // "as I recorded it" means Original); else the language's default
    // (American / Standard German). iOS `587bcc8`.
    var accentId by remember {
        val picked = PreferredAccent.get(context)
        mutableStateOf(when {
            !currentAccentId.isNullOrEmpty() -> currentAccentId
            picked == PreferredAccent.NONE -> null
            picked != null && options.any { it.id == picked } -> picked
            else -> VoiceAccentCatalog.defaultAccent(targetLanguage)?.id
        })
    }
    /** Neither this phone nor the server holds the recording (an accent
     *  remix keeps none upstream): only a new recording can move the voice. */
    var needsRecording by remember { mutableStateOf(false) }
    var rerecording by remember { mutableStateOf(false) }
    var working by remember { mutableStateOf(false) }
    var done by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    /** The voice moved but its accent didn't go on (iOS 2026-10-13): the move
     *  is done, so the sheet closes like any done move and says where to pick it. */
    var accentMissed by remember { mutableStateOf(false) }
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

    /** On Cartesia an accent is a setting on the same voice, so saving
     *  "<uuid>:<accent>" is the whole of applying it. */
    suspend fun applyPickedAccent() {
        val accent = options.firstOrNull { it.id == accentId } ?: return
        val newId = currentVoiceId() ?: return
        val cartesiaAccent = VoiceMove.cartesiaAccent(accent.id) ?: return
        val name = com.roro.futurevoice.data.VoiceName.display(context,
            com.roro.futurevoice.data.PersonaStore.shared(context).load()?.displayName)
        val accented = VoiceRemixClient(AuthRepository())
            .save("$newId:$cartesiaAccent", name, accent.prompt)
        onAccentApplied(accented, accent.id)
    }

    fun move() {
        if (working) return
        working = true; error = null
        val accent = options.firstOrNull { it.id == accentId }
        com.roro.futurevoice.core.Analytics.capture("voice_move_started", mapOf(
            "accent" to (accent?.id ?: "original"), "from" to if (hasRecording) "device" else "server"))
        scope.launch {
            // A retry after the voice already moved must not make a second
            // one: only the accent is left to do.
            val moveResult = runCatching {
                if (VoiceMove.isCartesia(currentVoiceId() ?: "")) return@runCatching true
                val name = com.roro.futurevoice.data.VoiceName.display(context,
                    com.roro.futurevoice.data.PersonaStore.shared(context).load()?.displayName)
                if (hasRecording) {
                    // The server clones on Cartesia (CLONE_PROVIDER) and the
                    // old voice is staged for deletion like any rebuild.
                    val newId = com.roro.futurevoice.net.VoiceCloneClient(AuthRepository()).cloneVoice(
                        name = name, sample = VoiceComparison.sampleFile(context.filesDir),
                        removeBackgroundNoise = false)
                    onRebuilt(newId)
                } else {
                    // No recording here: the server rebuilds from the copy the
                    // old voice was made from — or says there is none.
                    val moved = ElevenLabsClient(AuthRepository()).moveVoiceFromServer()
                    if (moved == null) {
                        com.roro.futurevoice.core.Analytics.capture("voice_move_no_original")
                        needsRecording = true
                        return@runCatching false
                    }
                    onMoved(moved)
                }
                true
            }
            moveResult.onFailure {
                com.roro.futurevoice.core.Analytics.capture("voice_move_failed", mapOf("reason" to (it.localizedMessage ?: "").take(200)))
                error = context.getString(R.string.tap_it_once_more_your_voice_didn_t_move_this_time)
            }
            if (moveResult.getOrNull() == true) {
                // The voice has moved. An accent that won't go on is not a
                // failed move: it can be picked again in Me → Voice.
                runCatching { applyPickedAccent() }.onFailure {
                    com.roro.futurevoice.core.Analytics.capture("voice_move_accent_failed", mapOf("reason" to (it.localizedMessage ?: "").take(200)))
                    accentMissed = true
                }
                com.roro.futurevoice.core.Analytics.capture("voice_move_done",
                    mapOf("accent" to if (accentMissed) "original" else (accent?.id ?: "original")))
                done = true
                playSample()
            }
            working = false
        }
    }

    // The recording screen on its own (iOS `fullScreenCover`). The sheet
    // steps aside while it is up and comes back to finish the move.
    if (rerecording) {
        VoiceRerecordCover(
            targetLanguage = targetLanguage,
            nativeLanguage = nativeLanguage,
            onCloned = onVoiceRecorded,
            onClose = {
                rerecording = false
                // A new voice: give it the accent picked above, then let them hear it.
                if (VoiceMove.isCartesia(currentVoiceId() ?: "")) {
                    working = true
                    scope.launch {
                        runCatching { applyPickedAccent() }.onFailure { accentMissed = true }
                        working = false
                        done = true
                        playSample()
                    }
                }
            },
        )
        return
    }
    // Not optional (iOS 2026-10-13, founder): every voice moves, so the sheet
    // has no Later and can't be swiped or backed away until it is done.
    ModalBottomSheet(
        sheetState = androidx.compose.material3.rememberModalBottomSheetState(skipPartiallyExpanded = true,
            confirmValueChange = { it != androidx.compose.material3.SheetValue.Hidden || done }),
        onDismissRequest = { if (done) onDismiss() },
        properties = androidx.compose.material3.ModalBottomSheetProperties(shouldDismissOnBackPress = false),
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
                if (accentMissed) {
                    Text(stringResource(R.string.pick_your_accent_again_in_me_voice_it_didn_t_go_on_this_time),
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
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
                // One row per accent with a check, as iOS's `accentRow` —
                // a chip row ran out of width at four accents (en).
                Column {
                    AccentRow(stringResource(R.string.accent_original), accentId == null, !working) { accentId = null }
                    options.forEach { o ->
                        AccentRow(accentLabel(o), accentId == o.id, !working) { accentId = o.id }
                    }
                }
            }
            if (needsRecording) {
                Text(stringResource(R.string.your_original_recording_isn_t_kept_for_this_voice_record_for_8f818c),
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                Button(onClick = { rerecording = true }, modifier = Modifier.fillMaxWidth()) {
                    Text(stringResource(R.string.record_again), fontWeight = FontWeight.SemiBold)
                }
            } else {
                Button(onClick = { move() }, enabled = !working, modifier = Modifier.fillMaxWidth()) {
                    if (working) CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp)
                    else Text(stringResource(R.string.voice_move_cta))
                }
            }
            error?.let { Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall) }
        }
    }
}

@Composable
private fun AccentRow(text: String, selected: Boolean, enabled: Boolean, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().clickable(enabled = enabled, onClick = onClick).padding(vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically) {
        Text(text, style = MaterialTheme.typography.bodyLarge, modifier = Modifier.weight(1f))
        if (selected) Icon(Icons.Filled.Check, contentDescription = null, modifier = Modifier.size(20.dp),
            tint = MaterialTheme.colorScheme.primary)
    }
}

/** When the move sheet is due, and the accent ids it maps (iOS `VoiceMove`). */
object VoiceMove {
    private const val SHOWN_KEY = "futurevoice.voiceMove.lastShown"
    private val CARTESIA = Regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}(:[a-z-]+)?$")

    fun isCartesia(id: String) = CARTESIA.matches(id)

    fun isDue(context: Context, voiceId: String?, signedIn: Boolean, standIn: Boolean = false): Boolean {
        // Not a stand-in preset (its own voice is queued, iOS `isDue`).
        if (!signedIn || voiceId == null || standIn || isCartesia(voiceId)) return false
        if (com.roro.futurevoice.data.VoiceParking.isParked(voiceId)) return false
        // Every open until the voice has moved: the move is not optional.
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
