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
import com.roro.futurevoice.audio.RoomCheck
import com.roro.futurevoice.audio.RoomGates
import androidx.compose.runtime.DisposableEffect
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material.icons.filled.Headphones
import androidx.compose.material3.Icon
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.Alignment
import androidx.compose.foundation.layout.Box
import com.roro.futurevoice.ui.brand.Futureself
import com.roro.futurevoice.ui.brand.FutureselfTheme
import com.roro.futurevoice.ui.brand.FutureselfMode
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.border
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.draw.clip
import androidx.compose.foundation.layout.size
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
/**
 * The acts, in iOS's order. The three before SCRIPT are not ceremony — they
 * are what protects the ONE take that becomes the learner's voice:
 *
 *   INTRO — why they are about to read their own voice aloud at all.
 *   MIC   — take the AirPods out. Bluetooth records at phone-call quality,
 *           and the clone is the one surface where the worn mic must NOT win.
 *   SPOT  — the room, measured. Quiet AND dry, both gates green.
 *
 * A clone made in the wrong room cannot be undone without spending another
 * provider slot, which is why these come before the recorder and not after.
 */
private enum class CloneAct { INTRO, CONSENT, MIC, SPOT, SCRIPT, REVIEW, UPLOADING, MEET, ACCOUNT }

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CloneFlowScreen(
    targetLanguage: String,
    onCloned: (voiceId: String) -> Unit,
    /** True once the session has a real account behind it. */
    signedIn: Boolean = false,
    /** Opens the sign-up. Null when there is nothing to keep the voice in. */
    onSaveVoice: (() -> Unit)? = null,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var act by remember { mutableStateOf(CloneAct.INTRO) }
    val room = remember { RoomCheck() }
    var ambient by remember { mutableFloatStateOf(-90f) }
    var echoTail by remember { mutableStateOf<Double?>(null) }
    var theme by remember { mutableStateOf(FutureselfTheme.stored(context)) }
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

    // The room is listened to ONLY on the spot step — an open mic on every
    // screen of onboarding is both a battery cost and a thing to explain.
    LaunchedEffect(act) {
        if (act == CloneAct.SPOT) {
            room.start()
            while (act == CloneAct.SPOT) {
                ambient = room.ambientDbfs
                echoTail = room.echoTailMs
                level = room.level
                delay(100)
            }
        }
        room.stop()
    }
    DisposableEffect(Unit) { onDispose { room.stop() } }

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
                    CloneAct.INTRO -> R.string.your_fluent_self
                    CloneAct.CONSENT -> R.string.your_voice_in_safe_hands
                    CloneAct.MIC -> R.string.mic_check
                    CloneAct.SPOT -> R.string.find_a_quiet_spot
                    CloneAct.SCRIPT -> if (recording) R.string.it_s_listening else R.string.read_this_aloud
                    CloneAct.REVIEW -> R.string.how_you_sound
                    CloneAct.UPLOADING -> R.string.becoming_you
                    CloneAct.MEET -> R.string.meet_your_fluent_self
                    CloneAct.ACCOUNT -> R.string.make_it_yours
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
            // The orb, present on every act and never decoration: it is the
            // thing the learner is building, and it reacts to what the act is
            // about. The spot step wears LISTENING because ambient noise
            // visibly stirs the surface — walking into a closet visibly
            // settles it, which is the instruction that step is giving.
            Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                Futureself(
                    mode = when (act) {
                        CloneAct.SPOT -> FutureselfMode.LISTENING
                        CloneAct.SCRIPT -> if (recording) FutureselfMode.LISTENING
                        else FutureselfMode.IDLE
                        CloneAct.REVIEW -> FutureselfMode.IDLE
                        CloneAct.UPLOADING -> FutureselfMode.THINKING
                        CloneAct.MEET -> FutureselfMode.SPEAKING
                        else -> FutureselfMode.IDLE
                    },
                    level = when (act) {
                        CloneAct.SPOT -> level
                        CloneAct.SCRIPT -> if (recording) level else 0f
                        // Something is happening that the learner cannot
                        // see; a still surface would read as a hang.
                        CloneAct.UPLOADING -> 0.35f
                        CloneAct.MEET -> 0.6f
                        else -> 0f
                    },
                    theme = theme,
                    // The script step shrinks it: the paragraphs are the
                    // subject there, and a full-size orb pushes them off.
                    virtualHeight = 64f,
                    modifier = Modifier
                        .size(if (act == CloneAct.SCRIPT) 72.dp else 168.dp)
                        .clip(CircleShape),
                )
            }

            when (act) {
                // Why they are about to read their own voice aloud. Without
                // it the first thing a learner meets is a consent form.
                CloneAct.INTRO -> {
                    StepHeader(
                        stringResource(R.string.another_you_already_fluent),
                        stringResource(R.string.dont_imitate_a_stranger),
                    )
                    Text(stringResource(R.string.time_to_meet_the_you_who_speaks),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Button(onClick = { act = CloneAct.CONSENT },
                        modifier = Modifier.fillMaxWidth()) {
                        Text(stringResource(R.string.next))
                    }
                }

                // Framed as QUALITY, not as a threat: the same instruction
                // reads better as what a good mic buys than as a punishment
                // for getting it wrong. The AirPods line stays because it is
                // the one concrete action — Bluetooth records at phone-call
                // quality, and this is the one surface where the worn mic
                // must NOT win.
                CloneAct.MIC -> {
                    StepHeader(
                        stringResource(R.string.use_the_phones_mic_or_a_better_one),
                        stringResource(R.string.the_better_the_mic_the_better_the_voice),
                    )
                    Row(verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Icon(Icons.Filled.Headphones, contentDescription = null,
                            tint = Color(0xFFFF9500))
                        Text(stringResource(R.string.take_your_earbuds_out_before_recording),
                            style = MaterialTheme.typography.bodyMedium,
                            color = Color(0xFFFF9500))
                    }
                    Button(onClick = { act = CloneAct.SPOT },
                        modifier = Modifier.fillMaxWidth()) {
                        Text(stringResource(R.string.next))
                    }
                }

                // The room, measured. Just give the answer — this used to be
                // "walk until it settles", which asks the reader to wander
                // their home running an experiment whose result we know.
                CloneAct.SPOT -> {
                    StepHeader(
                        stringResource(R.string.a_closet_is_the_best_spot),
                        stringResource(R.string.clothes_soak_up_the_echo),
                    )
                    GateRow(
                        title = stringResource(R.string.noise),
                        value = "%.0f dB".format(ambient),
                        state = RoomGates.noise(ambient),
                        labels = listOf(R.string.quiet, R.string.almost, R.string.too_noisy),
                    )
                    HorizontalDivider()
                    GateRow(
                        title = stringResource(R.string.echo),
                        value = echoTail?.let { "%.0f ms".format(it) },
                        state = RoomGates.echo(echoTail),
                        labels = listOf(R.string.dry, R.string.echoey, R.string.echoey),
                        unknownLabel = R.string.clap_to_check,
                    )
                    // The go-signal only appears once BOTH gates are green —
                    // quiet alone is not enough, an open room can be silent
                    // and still smear the clone with its own reflections.
                    if (RoomGates.bothPass(ambient, echoTail)) {
                        Button(onClick = { act = CloneAct.SCRIPT },
                            modifier = Modifier.fillMaxWidth()) {
                            Text(stringResource(R.string.im_ready))
                        }
                    }
                }

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
                            act = CloneAct.MIC
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
                        Row(verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                            Icon(
                                when (q.rating) {
                                    SampleQuality.Rating.GOOD -> Icons.Filled.CheckCircle
                                    SampleQuality.Rating.OKAY -> Icons.Filled.Info
                                    SampleQuality.Rating.POOR -> Icons.Filled.Warning
                                },
                                contentDescription = null,
                                tint = when (q.rating) {
                                    SampleQuality.Rating.GOOD -> Color(0xFF34C759)
                                    SampleQuality.Rating.OKAY -> Color(0xFFFF9500)
                                    SampleQuality.Rating.POOR -> MaterialTheme.colorScheme.error
                                },
                            )
                            Text(stringResource(when (q.rating) {
                                SampleQuality.Rating.GOOD -> R.string.great_sample
                                SampleQuality.Rating.OKAY -> R.string.usable_could_be_better
                                SampleQuality.Rating.POOR -> R.string.re_record_recommended
                            }), style = MaterialTheme.typography.titleMedium)
                        }
                        q.issues.forEach { issue ->
                            Text(issueText(issue), style = MaterialTheme.typography.bodySmall,
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
                    Text(stringResource(R.string.no_need_to_be_loud_just_be_clear),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
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

                    // The palette, picked while the voice is still in their
                    // ears — this is the moment the surface becomes theirs,
                    // and every Futureself in the app reads the choice.
                    Text(stringResource(R.string.pick_your_look),
                        style = MaterialTheme.typography.titleSmall,
                        modifier = Modifier.padding(top = 8.dp))
                    Row(Modifier.horizontalScroll(rememberScrollState()),
                        horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        FutureselfTheme.entries.forEach { t ->
                            Column(
                                Modifier
                                    .clip(RoundedCornerShape(14.dp))
                                    .border(
                                        width = if (t == theme) 2.dp else 1.dp,
                                        color = if (t == theme) t.tint()
                                        else MaterialTheme.colorScheme.outlineVariant,
                                        shape = RoundedCornerShape(14.dp))
                                    .clickable {
                                        theme = t
                                        context.getSharedPreferences("futurevoice", 0).edit()
                                            .putInt(FutureselfTheme.PREF_KEY, t.ordinal).apply()
                                    }
                                    .padding(8.dp),
                                horizontalAlignment = Alignment.CenterHorizontally,
                            ) {
                                Futureself(
                                    mode = FutureselfMode.IDLE, level = 0f, theme = t,
                                    virtualHeight = 64f,
                                    modifier = Modifier.size(width = 64.dp, height = 34.dp)
                                        .clip(CircleShape),
                                )
                                Text(t.label, style = MaterialTheme.typography.labelSmall)
                            }
                        }
                    }

                    // Two exits, one button. With an account behind the
                    // session this is onboarding's last tap; on an anonymous
                    // one it hands over to the sign-up — which now asks about
                    // a voice they have HEARD rather than a promise.
                    Button(
                        onClick = {
                            if (signedIn) clonedVoiceId?.let(onCloned)
                            else act = CloneAct.ACCOUNT
                        },
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Text(stringResource(
                            if (signedIn) R.string.start_talking else R.string.save_this_voice))
                    }
                }

                // Nothing here CREATES the voice — it only keeps it.
                // Everything before this ran on an anonymous session, which is
                // the whole point of the order: the ask lands after they have
                // heard the thing they are being asked to keep.
                CloneAct.ACCOUNT -> {
                    StepHeader(
                        stringResource(R.string.save_this_voice_to_your_account),
                        stringResource(R.string.its_built_and_its_yours),
                    )
                    onSaveVoice?.let { save ->
                        Button(onClick = save, modifier = Modifier.fillMaxWidth()) {
                            Text(stringResource(R.string.continue_))
                        }
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

/**
 * A step's headline and the one line under it. Every act in this flow wears
 * the same pair, so the wizard reads as one idea per screen rather than a
 * form with varying furniture.
 */
@Composable
private fun StepHeader(title: String, subtitle: String) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(title, style = MaterialTheme.typography.headlineSmall,
            fontWeight = FontWeight.Bold)
        Text(subtitle, style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

/**
 * One measured fact about the room: what it is, where it currently stands,
 * and the reading itself.
 *
 * The VALUE is shown, not just the verdict — a learner who is told "too
 * noisy" with no number has nothing to act on, while one who watches −38 fall
 * to −57 as they walk into a closet can see the room getting better.
 */
@Composable
private fun GateRow(
    title: String,
    value: String?,
    state: RoomGates.State,
    labels: List<Int>,
    unknownLabel: Int? = null,
) {
    val tint = when (state) {
        RoomGates.State.GOOD -> Color(0xFF34C759)
        RoomGates.State.NEAR -> Color(0xFFFF9500)
        RoomGates.State.BAD -> MaterialTheme.colorScheme.error
        RoomGates.State.UNKNOWN -> MaterialTheme.colorScheme.primary
    }
    val label = when (state) {
        RoomGates.State.GOOD -> labels[0]
        RoomGates.State.NEAR -> labels[1]
        RoomGates.State.BAD -> labels[2]
        RoomGates.State.UNKNOWN -> unknownLabel ?: labels[1]
    }
    Row(
        Modifier.fillMaxWidth().padding(vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Text(title, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.weight(1f))
        value?.let {
            Text(it, style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Text(stringResource(label), style = MaterialTheme.typography.labelLarge, color = tint)
    }
}

/**
 * What is wrong with a take, in the learner's own language.
 *
 * The analyzer reports FACTS (`SampleQuality.Issue`) and this writes the
 * sentence — the split exists because the analyzer used to build English
 * strings, which put untranslatable English in front of a Korean learner on
 * the one screen that tells them their recording is bad.
 */
@Composable
private fun issueText(issue: SampleQuality.Issue): String = when (issue) {
    is SampleQuality.Issue.TooShort ->
        stringResource(R.string.too_short_llds_aim_for_60_90s, issue.seconds)
    SampleQuality.Issue.ALittleShort -> stringResource(R.string.a_little_short_60_90s_clones_best)
    SampleQuality.Issue.Clipping -> stringResource(R.string.clipping_detected_move_further)
    SampleQuality.Issue.NoisyBackground -> stringResource(R.string.noisy_background_try_quieter)
    SampleQuality.Issue.SomeNoise -> stringResource(R.string.some_background_noise_quieter_better)
    SampleQuality.Issue.QuietTake -> stringResource(R.string.quiet_take_well_boost_it)
}
