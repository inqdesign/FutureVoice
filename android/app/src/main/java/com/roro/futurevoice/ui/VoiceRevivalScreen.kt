package com.roro.futurevoice.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.GraphicEq
import androidx.compose.material.icons.filled.Warning
import com.roro.futurevoice.ui.brand.IosButton as Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import com.roro.futurevoice.ui.brand.IosOutlinedButton as OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.roro.futurevoice.R
import com.roro.futurevoice.audio.Mp3Player
import com.roro.futurevoice.data.AuthRepository
import com.roro.futurevoice.data.VoiceAccent
import com.roro.futurevoice.data.VoiceAccentCatalog
import com.roro.futurevoice.data.VoiceParking
import com.roro.futurevoice.data.VoiceRevival
import com.roro.futurevoice.talk.VoiceCloneScript
import kotlinx.coroutines.launch
import androidx.lifecycle.compose.collectAsStateWithLifecycle

/**
 * A PARKED voice (see [VoiceParking]) comes back at the tap that needs it
 * (iOS `VoiceRevivalView`, founder's call 2026-10-01). There is no "your
 * voice is resting" notice anywhere: nothing to spend → the paywall (decided
 * by [com.roro.futurevoice.data.BillingGate] before this is asked); allowed to
 * spend → the voice is rebuilt from the recording on the phone in front of
 * them, the speed and accent are set again (the accent remix died with the
 * old voice), and Start runs what was tapped.
 *
 * A full-screen DIALOG, not a branch of the root's `when`: a launcher can sit
 * in a bottom sheet (the situation composer), and a dialog is a window of its
 * own that opens on top of it.
 */
@Composable
fun VoiceRevivalHost(app: AppViewModel) {
    val request by VoiceRevival.request.collectAsStateWithLifecycle()
    val r = request ?: return
    val state by app.state.collectAsStateWithLifecycle()
    val context = LocalContext.current
    fun finish(go: Boolean) {
        com.roro.futurevoice.core.Analytics.capture("voice_revival_closed",
            mapOf("purpose" to r.purpose.name.lowercase(), "started" to go))
        VoiceRevival.request.value = null
        r.result.complete(go)
    }
    // No recording on this phone (a reinstall, another device): it can't be
    // rebuilt here, so straight to "let's make your voice again".
    val decision = remember(r) {
        VoiceRevival.decide(state.voiceId, VoiceParking.parkedId.value,
            VoiceComparison.exists(context.filesDir))
    }
    LaunchedEffect(r, decision) {
        when (decision) {
            VoiceRevival.Decision.PROCEED -> finish(true)
            VoiceRevival.Decision.RECORD_AGAIN -> { finish(false); app.parkedVoiceNeedsRecording() }
            VoiceRevival.Decision.REBUILD -> Unit
        }
    }
    if (decision != VoiceRevival.Decision.REBUILD) return
    Dialog(
        onDismissRequest = { finish(false) },
        properties = DialogProperties(
            usePlatformDefaultWidth = false,
            dismissOnClickOutside = false,
            decorFitsSystemWindows = false,
        ),
    ) {
        Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
            VoiceRevivalScreen(app = app, purpose = r.purpose, onFinish = ::finish)
        }
    }
}

private enum class RevivalStage { REBUILDING, FAILED, TUNE }

@Composable
internal fun VoiceRevivalScreen(
    app: AppViewModel,
    purpose: VoiceRevival.Purpose,
    onFinish: (Boolean) -> Unit,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val state by app.state.collectAsStateWithLifecycle()
    val player = remember { Mp3Player(context.cacheDir, source = "voice_revival") }
    DisposableEffect(Unit) { onDispose { runCatching { player.stop() } } }

    var stage by remember { mutableStateOf(RevivalStage.REBUILDING) }
    var failure by remember { mutableStateOf<String?>(null) }
    /** Bumped by Try again — re-runs the rebuild. */
    var attempt by remember { mutableIntStateOf(0) }
    var accentToPick by remember { mutableStateOf<VoiceAccent?>(null) }
    var removingAccent by remember { mutableStateOf(false) }

    /**
     * Back to the voice as recorded. Hidden since 2026-10-08 (founder's call):
     * the "Original" pill is off the row, the plain voice is reachable via
     * Me → Voice → Remove accent. Kept, not deleted, like iOS.
     */
    @Suppress("unused")
    fun removeAccent() {
        if (state.voiceAccentId.isNullOrEmpty() || removingAccent) return
        player.stop()
        removingAccent = true
        scope.launch {
            runCatching {
                com.roro.futurevoice.net.VoiceCloneClient(AuthRepository()).cloneVoice(
                    name = "Future Self",
                    sample = VoiceComparison.sampleFile(context.filesDir),
                    removeBackgroundNoise = false,
                )
            }.onSuccess { app.adoptRemixedVoice(it, "") }
            removingAccent = false
        }
    }

    LaunchedEffect(attempt) {
        stage = RevivalStage.REBUILDING
        // Capture harness: no session, no network — hold the stage asked for
        // (iOS `VoiceRevivalView` does the same for `voice-revival[-tune]`).
        com.roro.futurevoice.capture.flags.TalkCaptureFlags.revivalStage?.let {
            if (it == "tune") stage = RevivalStage.TUNE
            return@LaunchedEffect
        }
        app.reviveParkedVoice()
            .onSuccess { stage = RevivalStage.TUNE }
            .onFailure { e ->
                failure = e.message
                stage = RevivalStage.FAILED
            }
    }

    Column(Modifier.fillMaxSize().systemBarsPadding()) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 4.dp)) {
            IconButton(onClick = { player.stop(); onFinish(false) }) {
                Icon(Icons.Filled.Close, contentDescription = stringResource(R.string.close),
                    tint = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        when (stage) {
            RevivalStage.REBUILDING -> Column(
                Modifier.fillMaxWidth().weight(1f).padding(horizontal = 24.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(16.dp, Alignment.CenterVertically),
            ) {
                Icon(Icons.Filled.GraphicEq, contentDescription = null,
                    modifier = Modifier.size(56.dp), tint = MaterialTheme.colorScheme.primary)
                Text(stringResource(R.string.recreating_your_voice),
                    style = MaterialTheme.typography.titleLarge.copy(fontWeight = FontWeight.Bold),
                    textAlign = TextAlign.Center)
                Text(stringResource(R.string.this_takes_a_few_seconds),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                CircularProgressIndicator(Modifier.size(24.dp), strokeWidth = 2.dp)
                Spacer(Modifier.height(80.dp))
            }

            RevivalStage.FAILED -> Column(
                Modifier.fillMaxWidth().weight(1f).padding(horizontal = 24.dp)
                    .padding(bottom = 16.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Column(
                    Modifier.weight(1f),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(16.dp, Alignment.CenterVertically),
                ) {
                    Icon(Icons.Filled.Warning, contentDescription = null,
                        modifier = Modifier.size(44.dp),
                        tint = MaterialTheme.colorScheme.onSurfaceVariant)
                    Text(stringResource(R.string.couldn_t_make_your_voice),
                        style = MaterialTheme.typography.titleLarge.copy(fontWeight = FontWeight.Bold),
                        textAlign = TextAlign.Center)
                    failure?.let {
                        Text(it, style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            textAlign = TextAlign.Center, maxLines = 4,
                            overflow = TextOverflow.Ellipsis)
                    }
                }
                Button(onClick = { attempt++ }, modifier = Modifier.fillMaxWidth()) {
                    Text(stringResource(R.string.try_again))
                }
            }

            RevivalStage.TUNE -> Column(Modifier.fillMaxWidth().weight(1f)) {
                Column(
                    Modifier.weight(1f).verticalScroll(rememberScrollState())
                        .padding(horizontal = 24.dp),
                    verticalArrangement = Arrangement.spacedBy(28.dp),
                ) {
                    Column(Modifier.padding(top = 12.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text(stringResource(R.string.your_voice_is_back),
                            style = MaterialTheme.typography.headlineMedium.copy(fontWeight = FontWeight.Bold))
                        Text(stringResource(R.string.set_the_speed_and_accent_again_then_start),
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    // Same control as the meet act's: a pill selects the rung
                    // AND speaks it, so the pick is made by ear. Keyed on the
                    // voice: an accent applied below is a new voice, and the
                    // takes already heard belong to the old one.
                    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        Text(stringResource(R.string.speaking_speed),
                            style = MaterialTheme.typography.titleMedium)
                        key(state.voiceId) {
                            SpeedAudition(
                                voiceId = state.voiceId,
                                line = VoiceCloneScript.paceSample(state.targetLanguage),
                                player = player,
                                showLaterHint = false,
                            )
                        }
                    }
                    val options = remember(state.targetLanguage) {
                        VoiceAccentCatalog.options(state.targetLanguage)
                    }
                    // A single option is the default remix itself — nothing to choose.
                    if (options.size > 1) {
                        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                            Text(stringResource(R.string.accent),
                                style = MaterialTheme.typography.titleMedium)
                            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                // "Original" (the plain clone) is off the pills since
                                // 2026-10-08: every clone is remixed into the default
                                // accent, and the plain voice lives behind Me → Voice →
                                // Remove accent. Kept (`removeAccent` above), not
                                // deleted — founder's call (iOS `VoiceRevivalView`).
                                options.forEach { o ->
                                    AccentPill(
                                        label = accentLabel(o),
                                        selected = state.voiceAccentId == o.id,
                                        loading = false, enabled = !removingAccent,
                                        modifier = Modifier.weight(1f),
                                    ) { player.stop(); accentToPick = o }
                                }
                            }
                        }
                    }
                }
                Button(
                    onClick = {
                        player.stop()
                        onFinish(true)
                    },
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 24.dp)
                        .padding(bottom = 16.dp),
                ) {
                    Text(stringResource(
                        if (purpose == VoiceRevival.Purpose.CALL) R.string.start_the_call
                        else R.string.continue_))
                }
            }
        }
    }

    accentToPick?.let {
        val voiceId = state.voiceId
        if (voiceId != null) {
            VoiceAccentSheet(
                voiceId = voiceId,
                targetLanguage = state.targetLanguage,
                appliedAccentId = state.voiceAccentId?.takeIf { a -> a.isNotEmpty() },
                onApplied = app::adoptRemixedVoice,
                // Leaving without applying leaves the learner on the rebuilt,
                // un-accented clone — the app has to know which voice it holds.
                onCloneRebuilt = { id -> app.adoptRemixedVoice(id, "") },
                initialAccent = it,
                onDismiss = { accentToPick = null },
            )
        }
    }
}

@Composable
internal fun AccentPill(
    label: String,
    selected: Boolean,
    loading: Boolean,
    enabled: Boolean,
    modifier: Modifier = Modifier,
    onClick: () -> Unit,
) {
    val content: @Composable () -> Unit = {
        Box(contentAlignment = Alignment.Center) {
            if (loading) CircularProgressIndicator(Modifier.size(14.dp), strokeWidth = 2.dp)
            // Four pills share a row: the label shrinks before it is cut, and
            // the pill's padding is a pill's, not a CTA's ("그…", "미…" at 1.3).
            else com.roro.futurevoice.ui.brand.FitButtonLabel(label, MaterialTheme.typography.labelMedium)
        }
    }
    val pad = androidx.compose.foundation.layout.PaddingValues(horizontal = 6.dp, vertical = 10.dp)
    if (selected) Button(onClick = onClick, enabled = enabled, modifier = modifier, contentPadding = pad) { content() }
    else OutlinedButton(onClick = onClick, enabled = enabled, modifier = modifier, contentPadding = pad) { content() }
}
