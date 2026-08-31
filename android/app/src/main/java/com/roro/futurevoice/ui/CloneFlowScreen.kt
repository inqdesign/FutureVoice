package com.roro.futurevoice.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.Checkbox
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.roro.futurevoice.R
import com.roro.futurevoice.ui.brand.AppSurfaces
import com.roro.futurevoice.audio.Mp3Player
import com.roro.futurevoice.audio.SampleQuality
import com.roro.futurevoice.audio.WavRecorder
import com.roro.futurevoice.data.AuthRepository
import com.roro.futurevoice.net.EdgeError
import com.roro.futurevoice.net.ElevenLabsClient
import com.roro.futurevoice.net.VoiceCloneClient
import com.roro.futurevoice.talk.VoiceCloneScript
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import androidx.compose.runtime.rememberCoroutineScope
import android.media.MediaPlayer
import java.io.File

/**
 * The voice-clone act — `VoiceCloneOnboardingView`, reduced to its spine:
 * consent (biometric data; asked once, before the mic) → read the script
 * aloud (60–90 s, live meter, min enforced) → review (measured quality +
 * listen back + start over) → uploading (normalize, SNR-driven denoise,
 * multipart clone) → meet (the greeting, first words in the user's own
 * voice). Accent picks and A/B comparison arrive later; the contract they
 * hang off (SNR, takes on disk) is already here.
 */
private enum class CloneAct { CONSENT, SCRIPT, REVIEW, UPLOADING, MEET }

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CloneFlowScreen(
    targetLanguage: String,
    onCloned: (voiceId: String) -> Unit,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var act by remember { mutableStateOf(CloneAct.CONSENT) }
    var startRecordingRequested by remember { mutableStateOf(false) }
    val recordPermission = androidx.activity.compose.rememberLauncherForActivityResult(
        androidx.activity.result.contract.ActivityResultContracts.RequestPermission()
    ) { granted -> if (granted) startRecordingRequested = true }
    var consented by remember { mutableStateOf(false) }
    val recorder = remember { WavRecorder() }
    val sampleFile = remember { File(context.filesDir, "voice/clone-sample.wav") }
    var recording by remember { mutableStateOf(false) }
    var elapsed by remember { mutableFloatStateOf(0f) }
    var level by remember { mutableFloatStateOf(0f) }
    var quality by remember { mutableStateOf<SampleQuality?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var greeting by remember { mutableStateOf<ByteArray?>(null) }
    var clonedVoiceId by remember { mutableStateOf<String?>(null) }
    val listenPlayer = remember { MediaPlayer() }
    val mp3 = remember { Mp3Player(context.cacheDir) }

    LaunchedEffect(recording) {
        while (recording) {
            elapsed = recorder.elapsedSeconds.toFloat()
            level = recorder.level
            if (elapsed >= MAX_SECONDS) {
                recorder.stop(); recording = false
                quality = SampleQuality.analyze(sampleFile)
                act = CloneAct.REVIEW
            }
            delay(100)
        }
    }

    fun stopRecording() {
        recorder.stop(); recording = false
        quality = SampleQuality.analyze(sampleFile)
        act = CloneAct.REVIEW
    }

    fun performClone() {
        act = CloneAct.UPLOADING
        error = null
        scope.launch {
            try {
                // Boost-only normalize; denoise only a take the quality gate
                // itself would flag (SNR < 22) — a clean take passed through
                // the denoiser loses the cues that make it recognizable.
                val normalized = SampleQuality.peakNormalized(sampleFile)
                val snr = SampleQuality.analyze(normalized)?.estimatedSnrDb
                val auth = AuthRepository()
                val voiceId = VoiceCloneClient(auth).cloneVoice(
                    name = "Future Self",
                    sample = normalized,
                    removeBackgroundNoise = (snr ?: 0f) < 22f,
                )
                clonedVoiceId = voiceId
                // First words in the user's own voice. Fidelity model on
                // purpose — fires once per user, and it's the moment they
                // decide whether the clone sounds like them. Best-effort:
                // a failed synthesis opens the act silent, never blocks.
                greeting = runCatching {
                    ElevenLabsClient(auth).synthesize(
                        voiceId = voiceId,
                        text = VoiceCloneScript.greeting(targetLanguage),
                        modelId = ElevenLabsClient.FIDELITY_MODEL_ID,
                        purpose = "greeting",
                    )
                }.getOrNull()
                act = CloneAct.MEET
                greeting?.let { mp3.play(it) }
            } catch (e: Exception) {
                error = when {
                    e is VoiceCloneClient.VoiceLimitReached ->
                        "Our voice shelf is full right now — please try again in a bit."
                    e is EdgeError -> e.message
                    else -> e.message ?: e::class.java.simpleName
                }
                act = CloneAct.REVIEW
            }
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(title = {
                Text(stringResource(when (act) {
                    CloneAct.CONSENT -> R.string.your_voice_in_safe_hands
                    CloneAct.SCRIPT -> if (recording) R.string.it_s_listening else R.string.read_this_aloud
                    CloneAct.REVIEW -> R.string.how_you_sound
                    CloneAct.UPLOADING -> R.string.becoming_you
                    CloneAct.MEET -> R.string.meet_your_fluent_self
                }))
            })
        },
        bottomBar = {
            // The script runs several screens long; the one control the act
            // needs must never scroll away with it.
            if (act == CloneAct.SCRIPT) {
                Column(Modifier.fillMaxWidth().padding(16.dp)) {
                    if (recording) {
                        LinearProgressIndicator(
                            progress = { (elapsed / MAX_SECONDS).coerceIn(0f, 1f) },
                            modifier = Modifier.fillMaxWidth(),
                        )
                        LinearProgressIndicator(
                            progress = { level },
                            modifier = Modifier.fillMaxWidth().height(3.dp).padding(top = 2.dp))
                        Text(
                            if (elapsed < MIN_SECONDS)
                                stringResource(R.string.keep_going_llds_more, (MIN_SECONDS - elapsed).toInt())
                            else stringResource(R.string.listening_tap_to_finish),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        Button(
                            enabled = elapsed >= MIN_SECONDS,
                            onClick = { stopRecording() },
                            modifier = Modifier.fillMaxWidth(),
                        ) { Text(stringResource(R.string.stop)) }
                    } else {
                        LaunchedEffect(startRecordingRequested) {
                            if (startRecordingRequested) {
                                startRecordingRequested = false
                                recorder.start(sampleFile); recording = true
                            }
                        }
                        Button(
                            onClick = { recordPermission.launch(android.Manifest.permission.RECORD_AUDIO) },
                            modifier = Modifier.fillMaxWidth(),
                        ) { Text(stringResource(R.string.start_recording)) }
                    }
                }
            }
        },
    ) { padding ->
        Column(
            Modifier.padding(padding).fillMaxSize().background(AppSurfaces.ground).padding(16.dp).verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            when (act) {
                CloneAct.CONSENT -> {
                    Text(stringResource(R.string.re_record_it_or_delete_it_whenever_you_want_and_deleting_you_5a997f),
                        style = MaterialTheme.typography.bodyMedium)
                    Row(
                        Modifier.fillMaxWidth().clickable { consented = !consented },
                        verticalAlignment = androidx.compose.ui.Alignment.CenterVertically,
                    ) {
                        Checkbox(checked = consented, onCheckedChange = { consented = it })
                        Text(stringResource(R.string.i_m_lld_or_older_and_i_agree_to_my_recording_being_used_to_b_a31e9d, MINIMUM_AGE),
                            style = MaterialTheme.typography.bodyMedium)
                    }
                    Button(
                        enabled = consented,
                        onClick = {
                            context.getSharedPreferences("futurevoice", 0).edit()
                                .putLong("futurevoice.consent.voiceAt", System.currentTimeMillis())
                                .putLong("futurevoice.consent.ageAt", System.currentTimeMillis())
                                .apply()
                            act = CloneAct.SCRIPT
                        },
                        modifier = Modifier.fillMaxWidth(),
                    ) { Text(stringResource(R.string.next)) }
                }

                CloneAct.SCRIPT -> {
                    VoiceCloneScript.paragraphs(targetLanguage).forEach {
                        Text(it, style = MaterialTheme.typography.bodyLarge)
                    }
                }

                CloneAct.REVIEW -> {
                    quality?.let { q ->
                        Text(when (q.rating) {
                            SampleQuality.Rating.GOOD -> "Great sample"
                            SampleQuality.Rating.OKAY -> "Usable — could be better"
                            SampleQuality.Rating.POOR -> "Re-record recommended"
                        }, style = MaterialTheme.typography.titleMedium)
                        q.issues.forEach {
                            Text(it, style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                    error?.let {
                        Text(it, style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.error)
                    }
                    OutlinedButton(onClick = {
                        runCatching {
                            listenPlayer.reset()
                            listenPlayer.setDataSource(sampleFile.path)
                            listenPlayer.prepare(); listenPlayer.start()
                        }
                    }, modifier = Modifier.fillMaxWidth()) {
                        Text(stringResource(R.string.listen_to_your_recording))
                    }
                    OutlinedButton(onClick = {
                        runCatching { listenPlayer.reset() }
                        quality = null; elapsed = 0f
                        act = CloneAct.SCRIPT
                    }, modifier = Modifier.fillMaxWidth()) {
                        Text(stringResource(R.string.start_over))
                    }
                    Button(onClick = { performClone() }, modifier = Modifier.fillMaxWidth()) {
                        Text(stringResource(R.string.use_this_voice))
                    }
                }

                CloneAct.UPLOADING -> {
                    LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
                    Text(stringResource(R.string.becoming_you),
                        style = MaterialTheme.typography.bodyMedium)
                }

                CloneAct.MEET -> {
                    Text(VoiceCloneScript.greeting(targetLanguage),
                        style = MaterialTheme.typography.bodyLarge)
                    greeting?.let { g ->
                        OutlinedButton(onClick = { scope.launch { mp3.play(g) } },
                            modifier = Modifier.fillMaxWidth()) {
                            Text(stringResource(R.string.listen))
                        }
                    }
                    Button(onClick = { clonedVoiceId?.let(onCloned) },
                        modifier = Modifier.fillMaxWidth()) {
                        Text(stringResource(R.string.continue_))
                    }
                }
            }
            Spacer(Modifier.height(24.dp))
        }
    }
}

private const val MIN_SECONDS = 60f
private const val MAX_SECONDS = 90f
private const val MINIMUM_AGE = 16
