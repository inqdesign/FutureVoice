package com.roro.futurevoice.ui

import androidx.compose.foundation.clickable
import com.roro.futurevoice.ui.brand.ContinuousShape
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
import com.roro.futurevoice.ui.brand.IosButton as Button
import com.roro.futurevoice.data.LanguageCatalog
import androidx.compose.material3.Checkbox
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import com.roro.futurevoice.ui.brand.IosOutlinedButton as OutlinedButton
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
import com.roro.futurevoice.data.ConsentStore
import androidx.compose.material.icons.filled.RecordVoiceOver
import androidx.compose.material.icons.filled.Delete
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.text.style.TextDecoration
import com.roro.futurevoice.R
import com.roro.futurevoice.ui.brand.AppSurfaces
import com.roro.futurevoice.audio.Mp3Player
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.material3.CircularProgressIndicator
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
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.sp
import androidx.compose.material.icons.automirrored.filled.ArrowBackIos
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.CardGiftcard
import androidx.compose.material.icons.filled.FrontHand
import androidx.compose.material.icons.filled.GraphicEq
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.PlayCircleFilled
import androidx.compose.material.icons.filled.Replay
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material.icons.filled.StopCircle
import androidx.compose.material.icons.filled.Waves
import com.roro.futurevoice.ui.brand.DisplayFace

/**
 * The voice-clone act — `VoiceCloneOnboardingView`, act for act. Not a form:
 * one full-screen stage where the Futureself surface is the protagonist from
 * first frame to last — a pixel title, the orb (with its recording ring) and
 * a timer line on top, the act's own copy under it, and ONE action bar at the
 * bottom that never scrolls away.
 *
 * The pre-recording half is a wizard — one idea per screen, nothing sprung on
 * the learner (recording NEVER starts as a side effect of entering a page):
 *
 *   INTRO   — the narrative: another you, already fluent.
 *   CONSENT — the voice model is biometric data, so its permission is its own
 *             screen with its own toggle, before the mic is even asked for.
 *             Skipped once consent is on record (a re-record is the same
 *             permission).
 *   MIC     — never Bluetooth earbuds; the mic permission is asked HERE, on
 *             its own step, so the room check after it can actually listen.
 *   SPOT    — the room, measured. Can't record now → it waits.
 *   SCRIPT  — read the script; only "Record my voice" starts the recording.
 *
 * Then the performance half: RECORDING (the teleprompter, 60–90 s) → REVIEW
 * (listen back + the measured verdict) → UPLOADING (the becoming) → MEET (the
 * clone SPEAKS; colour, speed and accent are picked by eye and ear) →
 * ACCOUNT (sign up to KEEP it).
 *
 * The account sits BEHIND the meet act (iOS 2026-08-18): what the server
 * needs to clone is a session, not an account, so "Use this voice" opens an
 * ANONYMOUS one, the clone speaks, and the sign-up then asks about something
 * already in the learner's ears. Google is LINKED to that anonymous user, so
 * the voice survives the sign-up; a sign-in that lands on another account
 * rebuilds the voice there from the take still on disk.
 */
private enum class CloneAct { INTRO, CONSENT, MIC, SPOT, SCRIPT, RECORDING, REVIEW, UPLOADING, MEET, ACCOUNT }

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CloneFlowScreen(
    targetLanguage: String,
    /** What the learner reads in by default — see the picker on the script
     *  step. */
    nativeLanguage: String = targetLanguage,
    /** "Start talking": the voice is kept and onboarding moves on. */
    onCloned: (voiceId: String) -> Unit,
    /** True once the session has a real account behind it. */
    signedIn: Boolean = false,
    /** A pre-signup session is on stage (iOS `auth.isAnonymous`). */
    sessionAnonymous: Boolean = false,
    /** The voice the app already holds — for an anonymous session that is
     *  the one waiting on the sign-up (iOS `resumeUnclaimedVoice`). */
    existingVoiceId: String? = null,
    /** The sign-up landed on another account (see `AppState`). */
    adoptedExistingAccount: Boolean = false,
    /** The intro's Back — a cross-stage exit (reopen the persona cards, or
     *  leave a re-record from Me). Null hides it. */
    onBack: (() -> Unit)? = null,
    /** Opens the anonymous session at "Use this voice"; throws when one
     *  can't be had, and the flow falls back to sign-up-then-clone. */
    onStartSession: (suspend () -> Unit)? = null,
    /** iOS `holdVoiceOnboarding`: keep this screen on stage. */
    onHold: (Boolean) -> Unit = {},
    googleAvailable: Boolean = false,
    onGoogleSignIn: ((android.content.Context) -> Unit)? = null,
    onAppleSignIn: (() -> Unit)? = null,
    signInBusy: Boolean = false,
    signInError: String? = null,
    /** A Welcome invite code that redeemed at the sign-up. */
    redeemedInvite: com.roro.futurevoice.net.ReferralClient.Redeemed? = null,
    /** DEBUG only (iOS `-cloneStage`): open on one act with stand-in data. */
    debugStage: String? = null,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val prefs = remember { context.getSharedPreferences("futurevoice", 0) }
    val shortScreen = androidx.compose.ui.platform.LocalConfiguration.current.screenHeightDp < 750
    var act by remember {
        mutableStateOf(when (debugStage) {
            "consent" -> CloneAct.CONSENT
            "mic" -> CloneAct.MIC
            "spot" -> CloneAct.SPOT
            "script" -> CloneAct.SCRIPT
            "recording" -> CloneAct.RECORDING
            "reviewing" -> CloneAct.REVIEW
            "uploading" -> CloneAct.UPLOADING
            "meet" -> CloneAct.MEET
            "account" -> CloneAct.ACCOUNT
            else -> CloneAct.INTRO
        })
    }
    // Came back after the unclaimed voice was collected (see [VoiceReclaim]).
    val reclaimed = remember { com.roro.futurevoice.data.VoiceReclaim.wasReclaimed(context) }
    LaunchedEffect(reclaimed) {
        if (reclaimed) com.roro.futurevoice.core.Analytics.capture("voice_reclaimed_notice",
            mapOf("reason" to "unclaimed_grace"))
    }
    val room = remember { RoomCheck() }
    var ambient by remember { mutableFloatStateOf(-90f) }
    var echoTail by remember { mutableStateOf<Double?>(null) }
    var monitoring by remember { mutableStateOf(false) }
    var theme by remember { mutableStateOf(FutureselfTheme.stored(context)) }
    /** Two facts behind ONE toggle, never pre-ticked: it starts off every
     *  time the step is shown (see [stepAfterIntro]). */
    var agreed by remember { mutableStateOf(false) }
    var readInNative by remember { mutableStateOf(true) }
    val nativeScript = remember(nativeLanguage) {
        VoiceCloneScript.handAuthored(nativeLanguage)
            // Same language on both sides means there is nothing to choose.
            ?.takeIf { !LanguageCatalog.sameLanguage(nativeLanguage, targetLanguage) }
    }
    val activeScript = (nativeScript.takeIf { readInNative } ?: VoiceCloneScript.paragraphs(targetLanguage))
    val recorder = remember { WavRecorder() }
    // The clone is built from ONE recording, so it takes the best microphone
    // in the room — the phone's. This is the one mic surface that never asks.
    LaunchedEffect(Unit) { com.roro.futurevoice.data.MicPreference.forceBuiltInForClone(context) }
    /** The recording that made the live voice (VoiceComparison, "Original"). */
    val sampleFile = remember { VoiceComparison.sampleFile(context.filesDir) }
    /** The take under review — kept apart from [sampleFile] so a re-record
     *  the learner then cancels never replaces the recording of the voice
     *  they kept. */
    val takeFile = remember { File(context.filesDir, "voice/clone-take.wav") }
    var elapsed by remember { mutableFloatStateOf(if (debugStage == "recording") 47f else 0f) }
    var level by remember { mutableFloatStateOf(0f) }
    var quality by remember { mutableStateOf<SampleQuality?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var greeting by remember { mutableStateOf<ByteArray?>(null) }
    var clonedVoiceId by remember { mutableStateOf<String?>(null) }
    var accentId by remember { mutableStateOf<String?>(null) }
    var accentToPick by remember { mutableStateOf<com.roro.futurevoice.data.VoiceAccent?>(null) }
    var removingAccent by remember { mutableStateOf(false) }
    /** The second pass, started from the meet act: Back means "keep the
     *  voice I have", not "walk the wizard backwards". */
    var reRecording by remember { mutableStateOf(false) }
    var comparing by remember { mutableStateOf(false) }
    var meetBurst by remember { mutableStateOf(false) }
    var becomingTheme by remember { mutableStateOf(FutureselfTheme.BLUE) }
    var becomingLine by remember { mutableIntStateOf(0) }
    val listenPlayer = remember { MediaPlayer() }
    var listening by remember { mutableStateOf(false) }
    val mp3 = remember { Mp3Player(context.cacheDir, source = "greeting") }
    var speaking by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) {
        while (true) {
            speaking = mp3.isPlaying
            listening = runCatching { listenPlayer.isPlaying }.getOrDefault(false)
            delay(100)
        }
    }
    DisposableEffect(Unit) {
        onDispose { room.stop(); mp3.stop(); runCatching { listenPlayer.release() } }
    }

    /** Where Next goes from the intro, and where Back returns to from the
     *  mic. Consent is SKIPPED once both answers are on record. */
    fun stepAfterIntro(): CloneAct =
        if (ConsentStore.hasVoiceConsent(context) && ConsentStore.ageConfirmedAt(context) != null)
            CloneAct.MIC else CloneAct.CONSENT

    fun hasMic() = context.checkSelfPermission(android.Manifest.permission.RECORD_AUDIO) ==
        android.content.pm.PackageManager.PERMISSION_GRANTED
    val micDenied = stringResource(R.string.microphone_access_denied_enable_it_in_settings)
    /** What a grant moves on to — the room check, or the recording. */
    var afterGrant by remember { mutableStateOf<(() -> Unit)?>(null) }
    val recordPermission = androidx.activity.compose.rememberLauncherForActivityResult(
        androidx.activity.result.contract.ActivityResultContracts.RequestPermission()
    ) { granted ->
        if (granted) { error = null; afterGrant?.invoke() } else error = micDenied
        afterGrant = null
    }
    fun withMic(then: () -> Unit) {
        if (hasMic()) { error = null; then() }
        else { afterGrant = then; recordPermission.launch(android.Manifest.permission.RECORD_AUDIO) }
    }

    // The room is listened to ONLY on the spot step — an open mic on every
    // screen of onboarding is both a battery cost and a thing to explain.
    LaunchedEffect(act) {
        if (act == CloneAct.SPOT && hasMic()) {
            room.start()
            monitoring = room.isMonitoring
            while (act == CloneAct.SPOT) {
                ambient = room.ambientDbfs
                echoTail = room.echoTailMs
                level = room.level
                delay(100)
            }
        }
        room.stop(); monitoring = false
    }

    fun playGreeting() {
        val g = greeting ?: return
        mp3.stop()
        scope.launch { mp3.play(g) }
    }

    /** Entry bloom for the meet act: a full-level burst, then the greeting
     *  takes over the orb. Said ONCE on arrival. */
    fun openMeet() {
        meetBurst = true
        scope.launch {
            delay(700)
            meetBurst = false
            playGreeting()
        }
    }

    fun stopAndReview() {
        recorder.stop()
        quality = SampleQuality.analyze(takeFile)
        // Remember the take so a relaunch reopens review, not step one.
        prefs.edit().putBoolean(PENDING_TAKE_KEY, true).apply()
        act = CloneAct.REVIEW
    }

    LaunchedEffect(act) {
        while (act == CloneAct.RECORDING && debugStage != "recording") {
            elapsed = recorder.elapsedSeconds.toFloat()
            level = recorder.level
            if (elapsed >= MAX_SECONDS) {
                HapticEngine.success(context)   // cue that recording auto-stopped at the cap
                stopAndReview()
            }
            delay(100)
        }
    }

    // The becoming: the palette advances every beat, the narration every
    // other beat. Honest theatre — no fake percentages.
    LaunchedEffect(act) {
        var step = 0
        while (act == CloneAct.UPLOADING) {
            becomingTheme = FutureselfTheme.entries[step % FutureselfTheme.entries.size]
            becomingLine = minOf(step / 2, BECOMING_LINES.size - 1)
            delay(1800)
            step += 1
        }
    }

    fun startRecording() = withMic {
        runCatching { listenPlayer.reset() }
        error = null
        elapsed = 0f
        takeFile.parentFile?.mkdirs()
        recorder.start(takeFile)
        act = CloneAct.RECORDING
    }

    /** Abandon the take before the minimum; the partial file never reaches
     *  review. */
    fun abortRecording() {
        recorder.stop()
        takeFile.delete()
        elapsed = 0f
        error = null
        act = CloneAct.SCRIPT
    }

    fun reRecord() {
        mp3.stop(); runCatching { listenPlayer.reset() }
        takeFile.delete()
        prefs.edit().remove(PENDING_TAKE_KEY).apply()
        quality = null; elapsed = 0f; error = null
        act = CloneAct.SCRIPT
    }

    /** Meet act → straight back to the script. The voice they have stays
     *  live the whole way and is replaced only if the new one is kept. */
    fun beginReRecordFromMeet() {
        reRecording = true
        meetBurst = false
        onHold(true)
        reRecord()
    }

    fun cancelReRecord() {
        mp3.stop(); runCatching { listenPlayer.reset() }
        takeFile.delete()
        prefs.edit().remove(PENDING_TAKE_KEY).apply()
        quality = null; elapsed = 0f; error = null
        reRecording = false
        act = CloneAct.MEET
    }

    /**
     * Another voice became the one on screen — a remixed take was applied,
     * the sheet rebuilt the plain clone to remix from, or "Original" rebuilt
     * it. The outgoing clone is deleted upstream (a slot we pay for), and the
     * greeting is re-made in the new voice. It is replayed only when [greet]:
     * the voice itself changed, so this is a first hearing of a different
     * clone — but never while the take picker is still busy.
     */
    fun adoptVoice(newId: String, accent: String?, greet: Boolean) {
        val old = clonedVoiceId
        clonedVoiceId = newId
        accentId = accent?.takeIf { it.isNotEmpty() }
        if (old != null && old != newId) scope.launch {
            runCatching { com.roro.futurevoice.data.AccountEraser.deleteVoice(old) }
        }
        greeting = null
        scope.launch {
            greeting = runCatching {
                ElevenLabsClient(AuthRepository()).synthesize(
                    voiceId = newId,
                    text = VoiceCloneScript.greeting(targetLanguage),
                    purpose = "greeting",
                )
            }.getOrNull()
            if (greet) playGreeting()
        }
    }

    /** Back to the voice as recorded — the meet act's "Original" pill. */
    fun removeAccentFromMeet() {
        if (accentId == null || removingAccent) return
        mp3.stop()
        removingAccent = true
        com.roro.futurevoice.core.Analytics.capture(
            "voice_accent_removed", mapOf("from" to "meet"))
        scope.launch {
            runCatching {
                VoiceCloneClient(AuthRepository()).cloneVoice(
                    // iOS sends `voiceDisplayName` — the library entry says whose it is.
                    name = com.roro.futurevoice.data.VoiceName.display(context, com.roro.futurevoice.data.PersonaStore.shared(context).load()?.displayName),
                    sample = sampleFile,
                    removeBackgroundNoise = false,
                )
            }.onSuccess { adoptVoice(it, null, greet = true) }
                .onFailure { e -> error = e.message }
            removingAccent = false
        }
    }

    /** Persist the recording, clone, then synthesize the clone's first words
     *  so the meet act can play them. */
    fun performClone() {
        act = CloneAct.UPLOADING
        error = null
        onHold(true)
        com.roro.futurevoice.core.Analytics.capture("voice_clone_started")
        scope.launch {
            try {
                // A sign-up that adopted an existing account rebuilds from the
                // recording already kept; everything else from the fresh take.
                val source = if (takeFile.exists()) takeFile else sampleFile
                // Boost-only normalize; denoise only a take the quality gate
                // itself would flag (SNR < 22) — a clean take passed through
                // the denoiser loses the cues that make it recognizable.
                val normalized = SampleQuality.peakNormalized(source)
                val snr = SampleQuality.analyze(normalized)?.estimatedSnrDb
                val auth = AuthRepository()
                val voiceId = VoiceCloneClient(auth).cloneVoice(
                    // iOS sends `voiceDisplayName` — the library entry says whose it is.
            name = com.roro.futurevoice.data.VoiceName.display(context, com.roro.futurevoice.data.PersonaStore.shared(context).load()?.displayName),
                    sample = normalized,
                    removeBackgroundNoise = (snr ?: 0f) < 22f,
                )
                // Keep the original so the clone can be rebuilt later
                // without recording again (iOS `VoiceSampleStore`).
                if (source != sampleFile) {
                    sampleFile.parentFile?.mkdirs()
                    source.copyTo(sampleFile, overwrite = true)
                    source.delete()
                }
                prefs.edit().remove(PENDING_TAKE_KEY).apply()
                val old = clonedVoiceId
                clonedVoiceId = voiceId
                accentId = null
                if (old != null && old != voiceId) scope.launch {
                    runCatching { com.roro.futurevoice.data.AccountEraser.deleteVoice(old) }
                }
                // Before sign-up the voice is on the reclaim clock; a signed-in
                // clone is not.
                if (signedIn) com.roro.futurevoice.data.VoiceReclaim.clear(context)
                else com.roro.futurevoice.data.VoiceReclaim.markUnclaimed(context)
                com.roro.futurevoice.core.Analytics.capture("voice_clone_succeeded")
                // Into the default accent BEFORE the greeting, so the first
                // words are already in the accent the voice will keep (iOS
                // `AppState.applyDefaultAccent`). Best-effort: a failure
                // keeps the plain clone.
                remixIntoDefaultAccent(context, voiceId, targetLanguage)?.let { (remixed, accent) ->
                    clonedVoiceId = remixed
                    accentId = accent.id
                    scope.launch {
                        runCatching { com.roro.futurevoice.data.AccountEraser.deleteVoice(voiceId) }
                    }
                    com.roro.futurevoice.core.Analytics.capture("voice_accent_applied",
                        mapOf("accent" to accent.id, "source" to "default"))
                }
                val greetVoice = clonedVoiceId ?: voiceId
                // First words in the user's own voice — best-effort: a failed
                // synthesis opens the act silent, never blocks. Said once, at
                // the default rung; the pills below are how speed is heard.
                greeting = runCatching {
                    ElevenLabsClient(auth).synthesize(
                        voiceId = greetVoice,
                        text = VoiceCloneScript.greeting(targetLanguage),
                        purpose = "greeting",
                        speed = com.roro.futurevoice.data.SpeechSpeed.DEFAULT.multiplier(context),
                    )
                }.getOrNull()
                HapticEngine.success(context)
                reRecording = false
                act = CloneAct.MEET
                openMeet()
            } catch (e: Exception) {
                android.util.Log.w("CloneFlow", "clone failed", e)
                com.roro.futurevoice.core.Analytics.capture("voice_clone_failed")
                error = when {
                    e is VoiceCloneClient.VoiceLimitReached ->
                        context.getString(R.string.voice_shelf_full)
                    e is EdgeError -> e.message
                    else -> e.message ?: e::class.java.simpleName
                }
                act = CloneAct.REVIEW
                // Only let go when there's no voice to fall back to: a failed
                // re-clone still has the old one live.
                if (!reRecording) onHold(false)
            }
        }
    }

    /**
     * "Use this voice". Onboarding runs account-free all the way through the
     * meet act: an anonymous session is opened silently here, the clone
     * speaks, and the account is asked for afterwards, to KEEP it.
     */
    fun useThisVoice() {
        mp3.stop(); runCatching { listenPlayer.reset() }
        val start = onStartSession
        if (!signedIn && !sessionAnonymous && start != null) {
            act = CloneAct.UPLOADING
            onHold(true)
            scope.launch {
                try {
                    start()
                    performClone()
                } catch (e: Exception) {
                    // Anonymous sessions unavailable — the setting is off, or
                    // there's no network. Fall back to the ORIGINAL order
                    // (sign up, then clone) rather than stranding the take.
                    act = CloneAct.ACCOUNT
                }
            }
            return
        }
        performClone()
    }

    fun finishMeet() {
        mp3.stop()
        // The accent goes with the voice (same key as iOS); the app reads it
        // when the voice lands.
        prefs.edit().apply {
            accentId?.let { putString("futurevoice.voiceAccentId", it) }
                ?: remove("futurevoice.voiceAccentId")
        }.apply()
        clonedVoiceId?.let(onCloned)
    }

    // The app died between "keep this voice" and the sign-up: reopen on the
    // account act instead of walking a finished voice through the wizard
    // again (iOS `resumeUnclaimedVoice`).
    LaunchedEffect(existingVoiceId, sessionAnonymous) {
        if (act == CloneAct.INTRO && existingVoiceId != null && sessionAnonymous && debugStage == null) {
            clonedVoiceId = existingVoiceId
            onHold(true)
            act = CloneAct.ACCOUNT
        }
    }
    // A reviewed-but-never-cloned take is still on disk: resume at review —
    // the learner's 90 seconds are not lost (iOS `restorePendingTake`).
    LaunchedEffect(Unit) {
        if (act == CloneAct.INTRO && debugStage == null && prefs.getBoolean(PENDING_TAKE_KEY, false)) {
            if (takeFile.exists()) {
                quality = SampleQuality.analyze(takeFile)
                act = CloneAct.REVIEW
            } else prefs.edit().remove(PENDING_TAKE_KEY).apply()
        }
    }
    // Sign-up landed: the account act resolves itself with no second tap. No
    // clone yet (the old order) or a clone under a throwaway user (the
    // identity was already an account) → build it now; otherwise the voice
    // they heard is theirs.
    LaunchedEffect(signedIn, act) {
        if (!signedIn || act != CloneAct.ACCOUNT || debugStage != null) return@LaunchedEffect
        if (clonedVoiceId == null || adoptedExistingAccount) performClone() else finishMeet()
    }

    BackHandler {
        error = null
        when (act) {
            CloneAct.INTRO -> onBack?.invoke()
            CloneAct.CONSENT -> act = CloneAct.INTRO
            CloneAct.MIC -> act = stepAfterIntro()
            CloneAct.SPOT -> act = CloneAct.MIC
            CloneAct.SCRIPT -> if (reRecording) cancelReRecord() else act = CloneAct.SPOT
            CloneAct.ACCOUNT -> act = if (clonedVoiceId == null) CloneAct.REVIEW else CloneAct.MEET
            // Mid-take, mid-clone and the meet act have no Back on iOS either.
            else -> {}
        }
    }

    val orbSize = when {
        act == CloneAct.SCRIPT -> if (shortScreen) 56.dp else 72.dp
        else -> if (shortScreen) 112.dp else 168.dp
    }
    val canReplayGreeting = act == CloneAct.MEET && greeting != null
    val stageTitle = stringResource(when (act) {
        CloneAct.INTRO -> if (reclaimed) R.string.let_s_make_your_voice_again else R.string.your_fluent_self
        CloneAct.CONSENT -> R.string.your_voice_in_safe_hands
        CloneAct.MIC -> R.string.mic_check
        CloneAct.SPOT -> R.string.find_a_quiet_spot
        CloneAct.SCRIPT -> R.string.read_this_aloud
        CloneAct.RECORDING -> R.string.it_s_listening
        CloneAct.REVIEW -> R.string.how_you_sound
        CloneAct.UPLOADING -> R.string.becoming_you
        CloneAct.MEET -> R.string.meet_your_fluent_self
        CloneAct.ACCOUNT -> R.string.make_it_yours
    })
    val timerLine = when (act) {
        // The orb's tap has nothing else pointing at it.
        CloneAct.MEET -> if (canReplayGreeting) stringResource(R.string.tap_to_hear_it_again) else ""
        CloneAct.RECORDING -> "%d:%02d".format(elapsed.toInt() / 60, elapsed.toInt() % 60)
        CloneAct.REVIEW -> quality?.let { stringResource(R.string.llds_recorded, it.durationSeconds.toInt()) } ?: ""
        else -> ""
    }
    val green = Color(0xFF34C759)
    val red = Color(0xFFFF3B30)

    Column(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.surface).systemBarsPadding()) {
        // The stage: one fixed shape across every act so nothing jumps.
        Column(Modifier.fillMaxWidth().padding(top = if (shortScreen) 12.dp else 28.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(if (shortScreen) 10.dp else 20.dp)) {
            // The account step's Back sits on its OWN row above the title,
            // leading — to whatever the step interrupted (iOS: the nav bar's
            // back button over the stage title). Sharing the title's row, a
            // large font pushed "뒤로" into the title.
            Column(Modifier.fillMaxWidth()) {
            if (act == CloneAct.ACCOUNT) {
                Row(Modifier.fillMaxWidth().padding(start = 12.dp)) {
                    Row(Modifier.clip(RoundedCornerShape(8.dp)).clickable {
                            error = null
                            act = if (clonedVoiceId == null) CloneAct.REVIEW else CloneAct.MEET
                        }.padding(horizontal = 4.dp, vertical = 6.dp),
                        verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBackIos, null, Modifier.size(18.dp),
                            tint = MaterialTheme.colorScheme.primary)
                        Text(stringResource(R.string.back), color = MaterialTheme.colorScheme.primary,
                            fontSize = 17.sp)
                    }
                }
            }
            Text(stageTitle, style = DisplayFace.style(stageTitle, TextStyle(fontSize = 24.sp)),
                maxLines = 1, overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis,
                textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp))
            }
            Box(Modifier.size(orbSize + 14.dp), contentAlignment = Alignment.Center) {
                if (act == CloneAct.RECORDING) {
                    val track = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.12f)
                    val ring = if (elapsed >= MIN_SECONDS) green else red
                    androidx.compose.foundation.Canvas(Modifier.fillMaxSize()) {
                        val stroke = 5.dp.toPx()
                        val inset = stroke / 2
                        val arcSize = androidx.compose.ui.geometry.Size(size.width - stroke, size.height - stroke)
                        val topLeft = androidx.compose.ui.geometry.Offset(inset, inset)
                        drawArc(track, 0f, 360f, false, topLeft, arcSize,
                            style = androidx.compose.ui.graphics.drawscope.Stroke(stroke))
                        drawArc(ring, -90f, 360f * (elapsed / MAX_SECONDS).coerceIn(0f, 1f), false,
                            topLeft, arcSize, style = androidx.compose.ui.graphics.drawscope.Stroke(
                                stroke, cap = androidx.compose.ui.graphics.StrokeCap.Round))
                    }
                }
                Futureself(
                    mode = when (act) {
                        CloneAct.SPOT, CloneAct.RECORDING -> FutureselfMode.LISTENING
                        CloneAct.REVIEW -> if (listening) FutureselfMode.SPEAKING else FutureselfMode.IDLE
                        CloneAct.UPLOADING -> FutureselfMode.THINKING
                        CloneAct.MEET -> if (speaking || meetBurst) FutureselfMode.SPEAKING else FutureselfMode.IDLE
                        else -> FutureselfMode.IDLE
                    },
                    level = when (act) {
                        CloneAct.SPOT, CloneAct.RECORDING -> level
                        CloneAct.REVIEW -> if (listening) 0.6f else 0f
                        CloneAct.UPLOADING -> 0.35f
                        CloneAct.MEET -> if (meetBurst) 1f else if (speaking) 0.6f else 0f
                        else -> 0f
                    },
                    // The becoming cycles all six palettes; every other act
                    // follows the stored theme (the meet act's picker
                    // updates it live).
                    theme = if (act == CloneAct.UPLOADING) becomingTheme else theme,
                    virtualHeight = 64f,
                    modifier = Modifier.size(orbSize).clip(CircleShape)
                        .border(0.5.dp, MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f), CircleShape)
                        // On the meet act the orb IS the fluent self, so
                        // tapping it is how the greeting is heard again.
                        .then(if (canReplayGreeting) Modifier.clickable {
                            HapticEngine.light(context); playGreeting()
                        } else Modifier),
                )
            }
            Text(timerLine,
                style = DisplayFace.style(timerLine, TextStyle(fontSize = 16.sp)),
                color = if (act == CloneAct.RECORDING && elapsed >= MIN_SECONDS) green
                    else MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1, modifier = Modifier.height(20.dp))
        }

        // The teleprompter acts scroll their own script; every other act
        // scrolls as a whole when it doesn't fit, so the action bar under
        // it can never be pushed off a short screen.
        val contentModifier = Modifier.weight(1f).fillMaxWidth()
            .padding(top = if (act == CloneAct.SCRIPT || act == CloneAct.RECORDING) 8.dp
                else if (shortScreen) 12.dp else 32.dp)
        if (act == CloneAct.SCRIPT || act == CloneAct.RECORDING) {
            Column(contentModifier, horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(10.dp)) {
                if (act == CloneAct.SCRIPT) {
                    // The language choice is made by LOOKING at the text.
                    if (nativeScript != null) {
                        com.roro.futurevoice.ui.brand.IosSegmented(listOf(LanguageCatalog.endonym(targetLanguage),
                            LanguageCatalog.endonym(nativeLanguage)),
                            if (readInNative) 1 else 0, { readInNative = it == 1 },
                            Modifier.fillMaxWidth().padding(horizontal = 28.dp))
                    }
                    Text(stringResource(if (nativeScript == null)
                        R.string.read_it_naturally_mistakes_are_fine_just_keep_going
                    else R.string.read_whichever_one_feels_natural_we_re_capturing_your_voice_3c04bd),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        textAlign = TextAlign.Center, modifier = Modifier.padding(horizontal = 28.dp))
                }
                Column(Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState())
                    .padding(horizontal = 28.dp, vertical = 16.dp),
                    verticalArrangement = Arrangement.spacedBy(18.dp)) {
                    activeScript.forEach {
                        Text(it, fontSize = 20.sp, lineHeight = 30.sp, fontWeight = FontWeight.Medium)
                    }
                }
                if (act == CloneAct.SCRIPT) {
                    Text(stringResource(R.string.s_1_minute_vary_your_pitch_a_little),
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.outline)
                }
            }
        } else {
            Column(contentModifier.verticalScroll(rememberScrollState()).padding(bottom = 12.dp),
                horizontalAlignment = Alignment.CenterHorizontally) {
                when (act) {
                    CloneAct.INTRO -> Column(horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        if (reclaimed) {
                            StepHeader(stringResource(R.string.one_minute_of_reading_brings_your_fluent_self_back),
                                stringResource(R.string.you_didn_t_finish_signing_up_so_we_deleted_the_voice_you_mad_f40409))
                            SupportLine(stringResource(R.string.everything_else_is_still_here))
                        } else {
                            StepHeader(stringResource(R.string.another_you_already_fluent),
                                stringResource(R.string.don_t_imitate_a_stranger_practice_with_the_fluent_you))
                            SupportLine(stringResource(R.string.time_to_meet_the_you_who_speaks_perfect_in_your_own_voice_on_e62699,
                                LanguageCatalog.ownName(targetLanguage, nativeLanguage)))
                        }
                    }

                    // Age + biometric consent, on one screen, gating Next.
                    CloneAct.CONSENT -> Column(Modifier.padding(horizontal = 8.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(22.dp)) {
                        StepHeader(stringResource(R.string.your_voice_is_handled_with_care), null)
                        // The disclosure the toggle agrees to — above it,
                        // because consent to something unexplained isn't
                        // informed consent.
                        Column(Modifier.widthIn(max = 340.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                            ConsentPoint(Icons.Filled.RecordVoiceOver,
                                stringResource(R.string.your_voice_model_is_built_by_the_most_trusted_service))
                            ConsentPoint(Icons.Filled.Delete,
                                stringResource(R.string.re_record_it_or_delete_it_whenever_you_want_and_deleting_you_5a997f))
                        }
                        Row(Modifier.widthIn(max = 340.dp).fillMaxWidth(),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            Text(stringResource(R.string.i_m_lld_or_older_and_i_agree_to_my_recording_being_used_to_b_a31e9d,
                                ConsentStore.MINIMUM_AGE),
                                style = MaterialTheme.typography.bodyMedium, modifier = Modifier.weight(1f))
                            com.roro.futurevoice.ui.brand.IosSwitch(checked = agreed, onCheckedChange = { agreed = it })
                        }
                        val uriHandler = LocalUriHandler.current
                        Text(stringResource(R.string.privacy_policy),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.primary,
                            modifier = Modifier.clickable { uriHandler.openUri(ConsentStore.privacyUrl()) })
                    }

                    // Framed as QUALITY, not as a threat. The earbuds line is
                    // the one concrete action — the clone is the one surface
                    // where the worn mic must NOT win.
                    CloneAct.MIC -> Column(horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(26.dp)) {
                        StepHeader(stringResource(R.string.use_the_phones_mic_or_a_better_one),
                            stringResource(R.string.the_better_the_mic_the_better_the_voice))
                        Row(verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            Icon(Icons.Filled.Headphones, contentDescription = null,
                                tint = Color(0xFFFF9500), modifier = Modifier.size(18.dp))
                            Text(stringResource(R.string.take_your_earbuds_out_before_recording),
                                style = MaterialTheme.typography.bodyMedium, color = Color(0xFFFF9500))
                        }
                    }

                    // The room, measured — two gates, quiet AND dry. Just give
                    // the answer: a closet.
                    CloneAct.SPOT -> Column(horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(26.dp)) {
                        StepHeader(stringResource(R.string.a_closet_is_the_best_spot),
                            stringResource(R.string.clothes_soak_up_the_echo))
                        if (monitoring) {
                            Column(Modifier.widthIn(max = 340.dp).fillMaxWidth().padding(horizontal = 16.dp)
                                .clip(RoundedCornerShape(14.dp)).background(AppSurfaces.ground)
                                .padding(horizontal = 14.dp)) {
                                GateRow(Icons.Filled.GraphicEq, stringResource(R.string.noise),
                                    "%.0f dB".format(ambient), RoomGates.noise(ambient),
                                    listOf(R.string.quiet, R.string.almost, R.string.too_noisy))
                                HorizontalDivider()
                                val echoState = RoomGates.echo(echoTail)
                                GateRow(when (echoState) {
                                    RoomGates.State.UNKNOWN -> Icons.Filled.FrontHand
                                    RoomGates.State.GOOD -> Icons.Filled.CheckCircle
                                    else -> Icons.Filled.Waves
                                }, stringResource(R.string.echo),
                                    echoTail?.let { "%.0f ms".format(it) }, echoState,
                                    listOf(R.string.dry, R.string.echoey, R.string.echoey),
                                    unknownLabel = R.string.clap_to_check)
                            }
                            if (RoomGates.bothPass(ambient, echoTail)) {
                                Row(verticalAlignment = Alignment.CenterVertically,
                                    horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                    Icon(Icons.Filled.CheckCircle, null, tint = green, modifier = Modifier.size(18.dp))
                                    Text(stringResource(R.string.record_here), color = green,
                                        fontWeight = FontWeight.SemiBold, style = MaterialTheme.typography.bodyMedium)
                                }
                            }
                        }
                        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                            SecondaryLabel(Icons.Filled.Schedule,
                                stringResource(R.string.can_t_record_now_no_rush_this_will_wait))
                            SecondaryLabel(Icons.Filled.Replay,
                                stringResource(R.string.not_happy_with_a_take_you_can_re_record))
                        }
                    }

                    CloneAct.REVIEW -> Column(horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(18.dp)) {
                        quality?.let { q ->
                            Column(Modifier.padding(horizontal = 32.dp),
                                horizontalAlignment = Alignment.CenterHorizontally,
                                verticalArrangement = Arrangement.spacedBy(10.dp)) {
                                Row(verticalAlignment = Alignment.CenterVertically,
                                    horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                                    Icon(when (q.rating) {
                                        SampleQuality.Rating.GOOD -> Icons.Filled.CheckCircle
                                        SampleQuality.Rating.OKAY -> Icons.Filled.Info
                                        SampleQuality.Rating.POOR -> Icons.Filled.Warning
                                    }, contentDescription = null, tint = when (q.rating) {
                                        SampleQuality.Rating.GOOD -> green
                                        SampleQuality.Rating.OKAY -> Color(0xFFFF9500)
                                        SampleQuality.Rating.POOR -> red
                                    })
                                    Text(stringResource(when (q.rating) {
                                        SampleQuality.Rating.GOOD -> R.string.great_sample
                                        SampleQuality.Rating.OKAY -> R.string.usable_could_be_better
                                        SampleQuality.Rating.POOR -> R.string.re_record_recommended
                                    }), style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.SemiBold)
                                }
                                q.issues.forEach { issue ->
                                    Text(issueText(issue), style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                        textAlign = TextAlign.Center)
                                }
                            }
                        }
                        OutlinedButton(onClick = {
                            if (listening) runCatching { listenPlayer.stop(); listenPlayer.reset() }
                            else runCatching {
                                listenPlayer.reset()
                                listenPlayer.setDataSource((if (takeFile.exists()) takeFile else sampleFile).path)
                                listenPlayer.prepare(); listenPlayer.start()
                            }
                        }, modifier = Modifier.widthIn(max = 280.dp).fillMaxWidth()) {
                            Icon(if (listening) Icons.Filled.StopCircle else Icons.Filled.PlayCircleFilled,
                                null, Modifier.size(20.dp))
                            Spacer(Modifier.size(6.dp))
                            Text(stringResource(if (listening) R.string.stop else R.string.listen_to_your_recording))
                        }
                        Text(stringResource(R.string.no_need_to_be_loud_just_be_clear),
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.outline, textAlign = TextAlign.Center,
                            modifier = Modifier.padding(horizontal = 40.dp))
                    }

                    CloneAct.UPLOADING -> Column(horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        Text(stringResource(BECOMING_LINES[becomingLine]), fontSize = 20.sp,
                            color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center)
                        Text(stringResource(R.string.about_half_a_minute),
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.outline)
                    }

                    CloneAct.MEET -> Column(horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(22.dp)) {
                        StepHeader(stringResource(R.string.it_s_you_fluent),
                            stringResource(R.string.pick_how_your_fluent_self_looks_and_sounds))
                        // The palette — a decision made by eye: the big orb
                        // recolours live and that is the feedback. Silent.
                        Row(horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                            FutureselfTheme.entries.forEach { t ->
                                val selected = t == theme
                                Column(Modifier.heightIn(min = 70.dp).clickable {
                                    theme = t
                                    FutureselfTheme.pick(context, t)
                                    HapticEngine.light(context)
                                }, horizontalAlignment = Alignment.CenterHorizontally,
                                    verticalArrangement = Arrangement.spacedBy(5.dp)) {
                                    Futureself(
                                        mode = FutureselfMode.SPEAKING, level = if (selected) 0.75f else 0.3f,
                                        theme = t, virtualHeight = 64f,
                                        modifier = Modifier.size(40.dp).clip(CircleShape)
                                            .border(if (selected) 2.dp else 0.5.dp,
                                                if (selected) t.tint()
                                                else MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f),
                                                CircleShape),
                                    )
                                    Text(t.label, fontSize = 11.sp,
                                        color = if (selected) MaterialTheme.colorScheme.onSurface
                                        else MaterialTheme.colorScheme.onSurfaceVariant)
                                }
                            }
                        }

                        // The speed, chosen BY EAR: a pill selects the rung
                        // and speaks it. Keyed on the voice: an accent applied
                        // below is a new voice.
                        Box(Modifier.padding(horizontal = 24.dp)) {
                            androidx.compose.runtime.key(clonedVoiceId) {
                                SpeedAudition(
                                    voiceId = clonedVoiceId,
                                    line = VoiceCloneScript.paceSample(targetLanguage),
                                    player = mp3,
                                )
                            }
                        }

                        // The accent, as pills on the screen itself. Since
                        // 2026-10-08 the voice arrives already remixed into the
                        // default (`remixIntoDefaultAccent`, iOS
                        // `AppState.applyDefaultAccent`).
                        val accentOptions = remember(targetLanguage) {
                            com.roro.futurevoice.data.VoiceAccentCatalog.options(targetLanguage)
                        }
                        if (accentOptions.isNotEmpty()) {
                            Column(Modifier.fillMaxWidth().padding(horizontal = 24.dp),
                                horizontalAlignment = Alignment.CenterHorizontally,
                                verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                Text(stringResource(R.string.accent),
                                    style = MaterialTheme.typography.labelMedium,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                    // "Original" is a choice on the row again (2026-10-08,
                                    // founder: the pills read clearer with the plain voice
                                    // among them) — but no longer the default: every clone
                                    // arrives remixed, so it is selected only once picked.
                                    AccentPill(
                                        label = stringResource(R.string.accent_original),
                                        selected = accentId == null, loading = removingAccent,
                                        enabled = !removingAccent && (accentId == null || sampleFile.exists()),
                                        modifier = Modifier.weight(1f),
                                    ) { removeAccentFromMeet() }
                                    accentOptions.forEach { o ->
                                        AccentPill(
                                            label = accentLabel(o),
                                            selected = accentId == o.id,
                                            loading = false, enabled = !removingAccent,
                                            modifier = Modifier.weight(1f),
                                        ) { mp3.stop(); accentToPick = o }
                                    }
                                }
                            }
                        }

                        // The verdict on the CLONE, not the take: opens the
                        // A/B, where the re-record decision lives.
                        Row(Modifier.clip(RoundedCornerShape(8.dp)).clickable {
                            mp3.stop(); comparing = true
                        }.padding(6.dp), verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            Icon(Icons.Filled.GraphicEq, null, Modifier.size(16.dp),
                                tint = MaterialTheme.colorScheme.primary)
                            Text(stringResource(R.string.doesn_t_sound_like_you),
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.primary)
                        }

                        // The code typed on Welcome actually landed — said
                        // once, on the last screen before the first call.
                        redeemedInvite?.let { r ->
                            Row(verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                Icon(Icons.Filled.CardGiftcard, null, Modifier.size(16.dp), tint = green)
                                Text(if (r.compPlanId != null) stringResource(R.string.applied_1_month,
                                        stringResource(com.roro.futurevoice.data.AccountStatus.tierNameRes(r.compPlanId)))
                                    else stringResource(R.string.invite_applied_lld_min_of_talk_time,
                                        com.roro.futurevoice.net.ReferralClient.bonusMinutes),
                                    style = MaterialTheme.typography.bodySmall, color = green)
                            }
                        }
                    }

                    // Nothing here CREATES the voice — it only keeps it.
                    CloneAct.ACCOUNT -> Column(horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(26.dp)) {
                        StepHeader(stringResource(R.string.save_this_voice_to_your_account),
                            stringResource(R.string.its_built_and_its_yours))
                        // The code was typed on Welcome, several steps back.
                        // Showing it here is the only sign it's still coming.
                        com.roro.futurevoice.data.PendingInvite.code(context)?.let { code ->
                            Row(verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                Icon(Icons.Filled.CardGiftcard, null, Modifier.size(16.dp),
                                    tint = MaterialTheme.colorScheme.onSurfaceVariant)
                                Text(stringResource(R.string.invite_code_lld_min_when_you_sign_up, code,
                                    com.roro.futurevoice.net.ReferralClient.bonusMinutes),
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                        }
                        if (signInBusy) CircularProgressIndicator(Modifier.size(22.dp), strokeWidth = 2.dp)
                        signInError?.let {
                            Text(it, color = red, style = MaterialTheme.typography.bodySmall,
                                textAlign = TextAlign.Center, modifier = Modifier.padding(horizontal = 32.dp))
                        }
                    }
                    else -> {}
                }
            }
        }

        error?.let {
            Row(Modifier.fillMaxWidth().padding(horizontal = 24.dp).padding(bottom = 8.dp),
                horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Filled.Warning, null, Modifier.size(14.dp), tint = red)
                Spacer(Modifier.size(4.dp))
                Text(it, style = MaterialTheme.typography.bodySmall, color = red, textAlign = TextAlign.Center)
            }
        }

        // The action bar — the same grammar setup uses: a compact Back and
        // the prominent primary.
        Column(Modifier.fillMaxWidth().background(AppSurfaces.ground)
            .padding(horizontal = 16.dp, vertical = 12.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(8.dp)) {
            @Composable fun wizardBar(next: String, nextIcon: androidx.compose.ui.graphics.vector.ImageVector? = null,
                                      nextEnabled: Boolean = true, onBackTap: (() -> Unit)?, onNext: () -> Unit) {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    if (onBackTap != null) {
                        OutlinedButton(onClick = { error = null; onBackTap() }) {
                            Icon(Icons.AutoMirrored.Filled.ArrowBackIos, null, Modifier.size(14.dp))
                            Spacer(Modifier.size(4.dp))
                            Text(stringResource(R.string.back))
                        }
                    }
                    // Only the primary is gated — Back must stay live, or a
                    // step that gates its Next becomes a wall.
                    Button(onClick = onNext, enabled = nextEnabled, modifier = Modifier.weight(1f)) {
                        nextIcon?.let { Icon(it, null, Modifier.size(18.dp)); Spacer(Modifier.size(6.dp)) }
                        Text(next, maxLines = 1)
                    }
                }
            }
            when (act) {
                // Cross-stage back: reopen the persona cards.
                CloneAct.INTRO -> wizardBar(stringResource(R.string.next), onBackTap = onBack) {
                    agreed = false
                    act = stepAfterIntro()
                }
                // Next is dead until the toggle is on.
                CloneAct.CONSENT -> wizardBar(stringResource(R.string.next), nextEnabled = agreed,
                    onBackTap = { act = CloneAct.INTRO }) {
                    ConsentStore.record(context)
                    act = CloneAct.MIC
                }
                // The permission is asked HERE, on its own step, so the room
                // check after it can listen.
                CloneAct.MIC -> wizardBar(stringResource(R.string.next),
                    onBackTap = { act = stepAfterIntro() }) { withMic { act = CloneAct.SPOT } }
                CloneAct.SPOT -> wizardBar(stringResource(R.string.next),
                    onBackTap = { act = CloneAct.MIC }) { act = CloneAct.SCRIPT }
                CloneAct.SCRIPT -> wizardBar(stringResource(R.string.record_my_voice), nextIcon = Icons.Filled.Mic,
                    onBackTap = { if (reRecording) cancelReRecord() else act = CloneAct.SPOT }) { startRecording() }
                // No early submit: before the minimum the only exit is
                // starting over — a short take can't proceed.
                CloneAct.RECORDING -> {
                    if (elapsed >= MIN_SECONDS) {
                        Button(onClick = { stopAndReview() }, modifier = Modifier.fillMaxWidth(),
                            colors = androidx.compose.material3.ButtonDefaults.buttonColors(
                                containerColor = if (elapsed >= RECOMMENDED_SECONDS) green else red,
                                contentColor = Color.White)) {
                            Icon(Icons.Filled.Stop, null, Modifier.size(18.dp))
                            Spacer(Modifier.size(6.dp))
                            Text(stringResource(R.string.stop_review))
                        }
                    } else {
                        OutlinedButton(onClick = { abortRecording() }, enabled = elapsed >= 1f,
                            modifier = Modifier.fillMaxWidth()) {
                            Icon(Icons.Filled.Replay, null, Modifier.size(18.dp))
                            Spacer(Modifier.size(6.dp))
                            Text(stringResource(R.string.start_over))
                        }
                    }
                    when {
                        elapsed < MIN_SECONDS -> Text(stringResource(R.string.keep_going_llds_more,
                            (MIN_SECONDS - elapsed).toInt()), style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                        elapsed < RECOMMENDED_SECONDS -> Text(stringResource(R.string.good_llds_more_for_the_best_result,
                            (RECOMMENDED_SECONDS - elapsed).toInt()), style = MaterialTheme.typography.bodySmall,
                            color = green)
                        else -> Text(stringResource(R.string.that_s_enough_stop_whenever_you_re_ready),
                            style = MaterialTheme.typography.bodySmall, color = green)
                    }
                }
                CloneAct.REVIEW -> {
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        OutlinedButton(onClick = { reRecord() }, modifier = Modifier.weight(1f)) {
                            Icon(Icons.Filled.Replay, null, Modifier.size(18.dp))
                            Spacer(Modifier.size(6.dp))
                            com.roro.futurevoice.ui.brand.FitButtonLabel(stringResource(R.string.re_record), androidx.compose.material3.LocalTextStyle.current)
                        }
                        Button(onClick = { useThisVoice() }, modifier = Modifier.weight(1f)) {
                            Icon(Icons.Filled.Check, null, Modifier.size(18.dp))
                            Spacer(Modifier.size(6.dp))
                            com.roro.futurevoice.ui.brand.FitButtonLabel(stringResource(R.string.use_this_voice), androidx.compose.material3.LocalTextStyle.current)
                        }
                    }
                    // Escape hatch for the second pass — including after a
                    // failed re-clone, where the live voice is still intact.
                    if (reRecording) {
                        Text(stringResource(R.string.keep_my_current_voice),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.primary,
                            modifier = Modifier.clickable { cancelReRecord() }.padding(4.dp))
                    }
                }
                CloneAct.UPLOADING -> Button(onClick = {}, enabled = false, modifier = Modifier.fillMaxWidth()) {
                    Icon(Icons.Filled.GraphicEq, null, Modifier.size(18.dp))
                    Spacer(Modifier.size(6.dp))
                    Text(stringResource(R.string.cloning_your_voice))
                }
                // Two exits, one button: with an account this is onboarding's
                // last tap; on the anonymous session it hands over to the
                // sign-up, which asks about a voice they've HEARD.
                CloneAct.MEET -> Button(onClick = {
                    if (signedIn) finishMeet() else { mp3.stop(); act = CloneAct.ACCOUNT }
                }, modifier = Modifier.fillMaxWidth()) {
                    Text(stringResource(if (signedIn) R.string.start_talking else R.string.save_this_voice))
                }
                // The two providers stacked full-width at equal size; Back
                // lives in the page header.
                CloneAct.ACCOUNT -> {
                    val pill = RoundedCornerShape(50)
                    val dark = androidx.compose.foundation.isSystemInDarkTheme()
                    val ink = if (dark) Color.White else Color.Black
                    val onInk = if (dark) Color.Black else Color.White
                    @Composable fun provider(label: Int, onClick: () -> Unit) {
                        Box(Modifier.fillMaxWidth().height(50.dp).clip(pill).background(ink)
                            .clickable(enabled = !signInBusy, onClick = { error = null; onClick() }),
                            contentAlignment = Alignment.Center) {
                            Text(stringResource(label), color = onInk, fontSize = 19.sp, fontWeight = FontWeight.Medium)
                        }
                    }
                    onAppleSignIn?.let { provider(R.string.continue_with_apple, it) }
                    if (googleAvailable) onGoogleSignIn?.let { g -> provider(R.string.continue_with_google) { g(context) } }
                }
            }
        }
    }

    val picking = accentToPick
    val pickVoice = clonedVoiceId
    if (picking != null && pickVoice != null) {
        VoiceAccentSheet(
            voiceId = pickVoice,
            targetLanguage = targetLanguage,
            appliedAccentId = accentId,
            onApplied = { id, accent -> adoptVoice(id, accent, greet = true) },
            // Leaving without applying leaves the learner on the rebuilt,
            // un-accented clone.
            onCloneRebuilt = { id -> adoptVoice(id, null, greet = false) },
            initialAccent = picking,
            onDismiss = { accentToPick = null },
        )
    }
    val compareVoice = clonedVoiceId
    if (comparing && compareVoice != null) {
        VoiceComparisonSheet(voiceId = compareVoice, targetLanguage = targetLanguage,
            onRerecord = { comparing = false; beginReRecordFromMeet() },
            onDismiss = { comparing = false })
    }
}

private const val MIN_SECONDS = 60f
private const val RECOMMENDED_SECONDS = 75f
private const val MAX_SECONDS = 90f
/** A take that reached review but was never cloned (iOS
 *  `futurevoice.pendingCloneTake`): a relaunch reopens review. */
private const val PENDING_TAKE_KEY = "futurevoice.pendingCloneTake"

/** Staged narration for the cloning wait. */
private val BECOMING_LINES = listOf(
    R.string.listening_back_to_every_word,
    R.string.learning_your_vowels,
    R.string.finding_your_tone,
    R.string.practicing_your_rhythm,
    R.string.almost_there,
)

/**
 * A wizard step's type stack: one big hook over a quiet support line, both
 * centred, the support's measure capped so lines break on phrases.
 */
@Composable
private fun StepHeader(title: String, subtitle: String?) {
    Column(Modifier.padding(horizontal = 32.dp), horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(title, fontSize = 22.sp, lineHeight = 28.sp, fontWeight = FontWeight.SemiBold,
            textAlign = TextAlign.Center)
        subtitle?.let { SupportLine(it) }
    }
}

@Composable
private fun SupportLine(text: String) {
    Text(text, fontSize = 16.sp, lineHeight = 22.sp, textAlign = TextAlign.Center,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.widthIn(max = 300.dp).padding(horizontal = 0.dp))
}

@Composable
private fun SecondaryLabel(icon: androidx.compose.ui.graphics.vector.ImageVector, text: String) {
    Row(Modifier.padding(horizontal = 32.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Icon(icon, null, Modifier.size(18.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(text, style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

/**
 * One measured fact about the room: its symbol, what it is, the reading,
 * and where it stands. The VALUE is shown, not just the verdict — watching
 * −38 fall to −57 while walking into a closet is the instruction.
 */
@Composable
private fun GateRow(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    title: String,
    value: String?,
    state: RoomGates.State,
    labels: List<Int>,
    unknownLabel: Int? = null,
) {
    val tint = when (state) {
        RoomGates.State.GOOD -> Color(0xFF34C759)
        RoomGates.State.NEAR -> Color(0xFFFF9500)
        RoomGates.State.BAD -> Color(0xFFFF3B30)
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
        Icon(icon, null, Modifier.size(20.dp), tint = tint)
        Text(title, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold,
            modifier = Modifier.weight(1f))
        value?.let {
            Text(it, style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Text(stringResource(label), style = MaterialTheme.typography.bodyMedium,
            fontWeight = FontWeight.Medium, color = tint)
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

/**
 * One line of the voice disclosure: a glyph and the promise it stands for.
 * Secondary-coloured because the thing being agreed to is the toggle below —
 * these are what make agreeing to it informed.
 */
@Composable
private fun ConsentPoint(icon: androidx.compose.ui.graphics.vector.ImageVector, text: String) {
    Row(
        Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Icon(icon, contentDescription = null, modifier = Modifier.size(18.dp),
            tint = MaterialTheme.colorScheme.primary)
        Text(text, style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
internal fun SpeedAudition(
    voiceId: String?,
    line: String,
    player: com.roro.futurevoice.audio.Mp3Player,
    /** The "change both later in settings" footnote — onboarding's alone. */
    showLaterHint: Boolean = true,
) {
    val context = androidx.compose.ui.platform.LocalContext.current
    val scope = androidx.compose.runtime.rememberCoroutineScope()
    var selected by remember { mutableStateOf(com.roro.futurevoice.data.SpeechSpeed.current(context)) }
    val takes = remember { mutableStateMapOf<com.roro.futurevoice.data.SpeechSpeed, ByteArray>() }
    var loading by remember { mutableStateOf<com.roro.futurevoice.data.SpeechSpeed?>(null) }
    suspend fun take(s: com.roro.futurevoice.data.SpeechSpeed): ByteArray? {
        takes[s]?.let { return it }
        val id = voiceId ?: return null
        return runCatching {
            ElevenLabsClient(com.roro.futurevoice.data.AuthRepository()).synthesize(
                voiceId = id, text = line, purpose = "greeting", speed = s.multiplier(context))
        }.getOrNull()?.also { takes[s] = it }
    }
    Column(Modifier.fillMaxWidth().padding(top = 8.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            com.roro.futurevoice.data.SpeechSpeed.entries.forEach { s ->
                val onClick: () -> Unit = {
                    selected = s
                    com.roro.futurevoice.data.SpeechSpeed.set(context, s)
                    scope.launch {
                        loading = s
                        val audio = take(s)
                        loading = null
                        audio?.let { player.play(it) }
                        // Warm the other two so the next tap answers at once.
                        com.roro.futurevoice.data.SpeechSpeed.entries.filter { it != s && takes[it] == null }
                            .forEach { launch { take(it) } }
                    }
                }
                val label: @Composable () -> Unit = {
                    if (loading == s) CircularProgressIndicator(Modifier.size(14.dp), strokeWidth = 2.dp)
                    else com.roro.futurevoice.ui.brand.FitButtonLabel(stringResource(s.label),
                        MaterialTheme.typography.labelLarge)
                }
                val pad = androidx.compose.foundation.layout.PaddingValues(horizontal = 8.dp, vertical = 10.dp)
                if (selected == s) Button(onClick = onClick, modifier = Modifier.weight(1f), contentPadding = pad) { label() }
                else OutlinedButton(onClick = onClick, modifier = Modifier.weight(1f), contentPadding = pad) { label() }
            }
        }
        Text(line, style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = androidx.compose.ui.text.style.TextAlign.Center)
        if (showLaterHint) Text(stringResource(R.string.you_can_change_both_later_in_settings),
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f),
            textAlign = androidx.compose.ui.text.style.TextAlign.Center)
    }
}
